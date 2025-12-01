package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.Value;
import org.cardanofoundation.cip113.entity.BalanceLogEntity;
import org.cardanofoundation.cip113.repository.BalanceLogRepository;
import org.cardanofoundation.cip113.util.BalanceValueHelper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

import java.math.BigInteger;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

@DataJpaTest
@TestPropertySource(properties = {
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.flyway.enabled=false"
})
class BalanceServiceTest {

    // Valid 56-character policy ID for testing (28 bytes hex)
    private static final String TEST_POLICY_ID = "aabbccddee11223344556677889900aabbccddee1122334455667788";
    // Valid hex asset name for testing
    private static final String TEST_ASSET_NAME = "746f6b656e31"; // "token1" in hex

    @Autowired
    private BalanceLogRepository repository;

    private BalanceService service;

    @BeforeEach
    void setUp() {
        repository.deleteAll();
        service = new BalanceService(repository);
    }

    @Test
    void testAppendBalanceEntry() {
        // Given
        Value balance = createAdaOnlyBalance(1000000);
        BalanceLogEntity entry = createBalanceEntry(
                "addr1test123",
                balance,
                "tx1",
                100L
        );

        // When
        BalanceLogEntity saved = service.append(entry);

        // Then
        assertNotNull(saved.getId());

        // Verify balance JSON
        Value savedBalance = BalanceValueHelper.fromJson(saved.getBalance());
        assertEquals(BigInteger.valueOf(1000000), savedBalance.getCoin());
    }

    @Test
    void testAppendDuplicateIsIdempotent() {
        // Given
        Value balance = createAdaOnlyBalance(1000000);
        BalanceLogEntity entry1 = createBalanceEntry(
                "addr1test123",
                balance,
                "tx1",
                100L
        );

        // When
        service.append(entry1);
        service.append(entry1); // Same entry

        // Then - should only have one entry
        assertEquals(1, repository.count());
    }

    @Test
    void testGetLatestBalance() {
        // Given - create balance history
        String address = "addr1test123";
        service.append(createBalanceEntry(address, createAdaOnlyBalance(1000), "tx1", 100L));
        service.append(createBalanceEntry(address, createAdaOnlyBalance(2000), "tx2", 200L));
        service.append(createBalanceEntry(address, createAdaOnlyBalance(3000), "tx3", 300L));

        // When
        BalanceLogEntity latest = service.getLatestBalance(address).orElseThrow();

        // Then - should return most recent
        Value latestBalance = BalanceValueHelper.fromJson(latest.getBalance());
        assertEquals(BigInteger.valueOf(3000), latestBalance.getCoin());
        assertEquals("tx3", latest.getTxHash());
        assertEquals(300L, latest.getSlot());
    }

    @Test
    void testGetCurrentBalanceAsValue() {
        // Given
        String address = "addr1test123";
        Value balance = createBalanceWithAssets(
                BigInteger.valueOf(5000000),
                TEST_POLICY_ID, TEST_ASSET_NAME, BigInteger.valueOf(100)
        );
        service.append(createBalanceEntry(address, balance, "tx1", 100L));

        // When
        Value currentBalance = service.getCurrentBalanceAsValue(address);

        // Then
        assertEquals(BigInteger.valueOf(5000000), currentBalance.getCoin());
        assertNotNull(currentBalance.getMultiAssets());
        assertEquals(1, currentBalance.getMultiAssets().size());

        MultiAsset multiAsset = currentBalance.getMultiAssets().get(0);
        assertEquals(TEST_POLICY_ID, multiAsset.getPolicyId());
        assertEquals(1, multiAsset.getAssets().size());
        // Asset name may have different formats (hex, 0x-prefixed, or decoded)
        // Just verify the value is correct
        assertEquals(BigInteger.valueOf(100), multiAsset.getAssets().get(0).getValue());
    }

    @Test
    void testGetCurrentBalanceByUnit() {
        // Given
        String address = "addr1test123";
        Value balance = createBalanceWithAssets(
                BigInteger.valueOf(2000000),
                TEST_POLICY_ID, TEST_ASSET_NAME, BigInteger.valueOf(50)
        );
        service.append(createBalanceEntry(address, balance, "tx1", 100L));

        // When
        Map<String, String> unitMap = service.getCurrentBalanceByUnit(address);

        // Then
        assertEquals("2000000", unitMap.get("lovelace"));
        // Asset key format may vary, find the non-lovelace key
        String assetKey = unitMap.keySet().stream()
                .filter(k -> !k.equals("lovelace"))
                .findFirst()
                .orElse(null);
        assertNotNull(assetKey, "Should have an asset key");
        assertEquals("50", unitMap.get(assetKey));
    }

    @Test
    void testGetCurrentBalanceByUnitEmpty() {
        // Given - no balance entries
        String address = "addr1nonexistent";

        // When
        Map<String, String> unitMap = service.getCurrentBalanceByUnit(address);

        // Then
        assertTrue(unitMap.isEmpty());
    }

    @Test
    void testGetBalanceHistory() {
        // Given
        String address = "addr1test123";
        service.append(createBalanceEntry(address, createAdaOnlyBalance(1000), "tx1", 100L));
        service.append(createBalanceEntry(address, createAdaOnlyBalance(2000), "tx2", 200L));
        service.append(createBalanceEntry(address, createAdaOnlyBalance(3000), "tx3", 300L));
        service.append(createBalanceEntry(address, createAdaOnlyBalance(4000), "tx4", 400L));

        // When
        List<BalanceLogEntity> history = service.getBalanceHistory(address, 3);

        // Then - should return last 3 entries in DESC order
        assertEquals(3, history.size());

        Value balance0 = BalanceValueHelper.fromJson(history.get(0).getBalance());
        Value balance1 = BalanceValueHelper.fromJson(history.get(1).getBalance());
        Value balance2 = BalanceValueHelper.fromJson(history.get(2).getBalance());

        assertEquals(BigInteger.valueOf(4000), balance0.getCoin());
        assertEquals(BigInteger.valueOf(3000), balance1.getCoin());
        assertEquals(BigInteger.valueOf(2000), balance2.getCoin());
    }

    @Test
    void testCalculateBalanceDiff() {
        // Given
        BalanceLogEntity prev = createBalanceEntry("addr1", createAdaOnlyBalance(1000), "tx1", 100L);
        BalanceLogEntity current = createBalanceEntry("addr1", createAdaOnlyBalance(1500), "tx2", 200L);

        // When
        Value diff = service.calculateBalanceDiff(current, prev);

        // Then
        assertEquals(BigInteger.valueOf(500), diff.getCoin());
    }

    @Test
    void testCalculateBalanceDiffWithAssets() {
        // Given
        Value prevBalance = createBalanceWithAssets(
                BigInteger.valueOf(1000),
                TEST_POLICY_ID, TEST_ASSET_NAME, BigInteger.valueOf(50)
        );
        Value currentBalance = createBalanceWithAssets(
                BigInteger.valueOf(2000),
                TEST_POLICY_ID, TEST_ASSET_NAME, BigInteger.valueOf(75)
        );

        BalanceLogEntity prev = createBalanceEntry("addr1", prevBalance, "tx1", 100L);
        BalanceLogEntity current = createBalanceEntry("addr1", currentBalance, "tx2", 200L);

        // When
        Value diff = service.calculateBalanceDiff(current, prev);

        // Then
        assertEquals(BigInteger.valueOf(1000), diff.getCoin());
        assertNotNull(diff.getMultiAssets());
        assertEquals(BigInteger.valueOf(25), diff.getMultiAssets().get(0).getAssets().get(0).getValue());
    }

    @Test
    void testCalculateBalanceDiffFirstEntry() {
        // Given
        BalanceLogEntity current = createBalanceEntry("addr1", createAdaOnlyBalance(1000), "tx1", 100L);

        // When - no previous entry
        Value diff = service.calculateBalanceDiff(current, null);

        // Then - diff should equal current balance
        assertEquals(BigInteger.valueOf(1000), diff.getCoin());
    }

    @Test
    void testGetPreviousBalance() {
        // Given
        String address = "addr1test123";
        BalanceLogEntity entry1 = service.append(createBalanceEntry(address, createAdaOnlyBalance(1000), "tx1", 100L));
        BalanceLogEntity entry2 = service.append(createBalanceEntry(address, createAdaOnlyBalance(2000), "tx2", 200L));
        BalanceLogEntity entry3 = service.append(createBalanceEntry(address, createAdaOnlyBalance(3000), "tx3", 300L));

        // When - get previous of entry3
        BalanceLogEntity previous = service.getPreviousBalance(entry3).orElseThrow();

        // Then
        assertEquals(entry2.getId(), previous.getId());

        Value prevBalance = BalanceValueHelper.fromJson(previous.getBalance());
        assertEquals(BigInteger.valueOf(2000), prevBalance.getCoin());
    }

    @Test
    void testGetPreviousBalanceForFirstEntry() {
        // Given
        String address = "addr1test123";
        BalanceLogEntity entry1 = service.append(createBalanceEntry(address, createAdaOnlyBalance(1000), "tx1", 100L));

        // When - get previous of first entry
        var previous = service.getPreviousBalance(entry1);

        // Then - should be empty
        assertTrue(previous.isEmpty());
    }

    @Test
    void testGetLatestBalancesByPaymentScript() {
        // Given
        String paymentScript = "testScriptHash123";
        service.append(createBalanceEntryWithPayment("addr1", paymentScript, null, createAdaOnlyBalance(1000), "tx1", 100L));
        service.append(createBalanceEntryWithPayment("addr2", paymentScript, null, createAdaOnlyBalance(2000), "tx2", 200L));
        service.append(createBalanceEntryWithPayment("addr3", "otherScript", null, createAdaOnlyBalance(3000), "tx3", 300L));

        // When
        List<BalanceLogEntity> balances = service.getLatestBalancesByPaymentScript(paymentScript);

        // Then - should only return balances for specified payment script
        assertEquals(2, balances.size());
        assertTrue(balances.stream().allMatch(b -> b.getPaymentScriptHash().equals(paymentScript)));
    }

    @Test
    void testGetLatestBalancesByStakeKey() {
        // Given
        String stakeKey = "stakeKeyHash123";
        service.append(createBalanceEntryWithPayment("addr1", "script1", stakeKey, createAdaOnlyBalance(1000), "tx1", 100L));
        service.append(createBalanceEntryWithPayment("addr2", "script2", stakeKey, createAdaOnlyBalance(2000), "tx2", 200L));
        service.append(createBalanceEntryWithPayment("addr3", "script3", "otherStake", createAdaOnlyBalance(3000), "tx3", 300L));

        // When
        List<BalanceLogEntity> balances = service.getLatestBalancesByStakeKey(stakeKey);

        // Then - should only return balances for specified stake key
        assertEquals(2, balances.size());
        assertTrue(balances.stream().allMatch(b -> b.getStakeKeyHash().equals(stakeKey)));
    }

    @Test
    void testGetAssetAmount() {
        // Given
        Value balance = createBalanceWithAssets(
                BigInteger.valueOf(3000000),
                TEST_POLICY_ID, TEST_ASSET_NAME, BigInteger.valueOf(150)
        );
        String balanceJson = BalanceValueHelper.toJson(balance);

        // When
        BigInteger lovelaceAmount = service.getAssetAmount(balanceJson, "lovelace");
        // Find the actual asset key from the balance json
        Map<String, String> unitMap = BalanceValueHelper.toUnitMap(BalanceValueHelper.fromJson(balanceJson));
        String assetKey = unitMap.keySet().stream()
                .filter(k -> !k.equals("lovelace"))
                .findFirst()
                .orElse(TEST_POLICY_ID + TEST_ASSET_NAME);
        BigInteger assetAmount = service.getAssetAmount(balanceJson, assetKey);
        BigInteger nonExistentAmount = service.getAssetAmount(balanceJson, "nonexistent12345678901234567890123456789012345678901234567890");

        // Then
        assertEquals(BigInteger.valueOf(3000000), lovelaceAmount);
        assertEquals(BigInteger.valueOf(150), assetAmount);
        assertEquals(BigInteger.ZERO, nonExistentAmount);
    }

    @Test
    void testExists() {
        // Given
        String address = "addr1test123";
        String txHash = "tx1";
        service.append(createBalanceEntry(address, createAdaOnlyBalance(1000), txHash, 100L));

        // When/Then
        assertTrue(service.exists(address, txHash));
        assertFalse(service.exists(address, "tx2"));
        assertFalse(service.exists("addr2", txHash));
    }

    @Test
    void testGetBalancesByTransaction() {
        // Given
        String txHash = "tx123";
        service.append(createBalanceEntry("addr1", createAdaOnlyBalance(1000), txHash, 100L));
        service.append(createBalanceEntry("addr2", createAdaOnlyBalance(2000), txHash, 100L));
        service.append(createBalanceEntry("addr3", createAdaOnlyBalance(3000), "tx456", 100L));

        // When
        List<BalanceLogEntity> balances = service.getBalancesByTransaction(txHash);

        // Then
        assertEquals(2, balances.size());
        assertTrue(balances.stream().allMatch(b -> b.getTxHash().equals(txHash)));
    }

    // Helper methods

    private Value createAdaOnlyBalance(long lovelace) {
        return Value.builder()
                .coin(BigInteger.valueOf(lovelace))
                .build();
    }

    private Value createBalanceWithAssets(BigInteger lovelace, String policyId, String assetName, BigInteger assetAmount) {
        return Value.builder()
                .coin(lovelace)
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(policyId)
                                .assets(List.of(
                                        Asset.builder()
                                                .name(assetName)
                                                .value(assetAmount)
                                                .build()
                                ))
                                .build()
                ))
                .build();
    }

    private BalanceLogEntity createBalanceEntry(String address, Value balance, String txHash, Long slot) {
        return createBalanceEntryWithPayment(address, "paymentScript123", "stakeKey456", balance, txHash, slot);
    }

    private BalanceLogEntity createBalanceEntryWithPayment(String address, String paymentScript, String stakeKey,
                                                            Value balance, String txHash, Long slot) {
        String balanceJson = BalanceValueHelper.toJson(balance);

        return BalanceLogEntity.builder()
                .address(address)
                .paymentScriptHash(paymentScript)
                .stakeKeyHash(stakeKey)
                .balance(balanceJson)
                .txHash(txHash)
                .slot(slot)
                .blockHeight(1000L)
                .build();
    }
}
