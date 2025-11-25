package org.cardanofoundation.cip113.util;

import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.Value;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class BalanceValueHelperTest {

    @Test
    void testCalculateSignedDiff_PositiveDiff() {
        // Given - balance increased
        Value previous = Value.builder().coin(BigInteger.valueOf(1000)).build();
        Value current = Value.builder().coin(BigInteger.valueOf(1500)).build();

        String previousJson = BalanceValueHelper.toJson(previous);
        String currentJson = BalanceValueHelper.toJson(current);

        // When
        Map<String, String> diff = BalanceValueHelper.calculateSignedDiff(currentJson, previousJson);

        // Then
        assertEquals("500", diff.get("lovelace"));
    }

    @Test
    void testCalculateSignedDiff_NegativeDiff() {
        // Given - balance decreased
        Value previous = Value.builder().coin(BigInteger.valueOf(2000)).build();
        Value current = Value.builder().coin(BigInteger.valueOf(1500)).build();

        String previousJson = BalanceValueHelper.toJson(previous);
        String currentJson = BalanceValueHelper.toJson(current);

        // When
        Map<String, String> diff = BalanceValueHelper.calculateSignedDiff(currentJson, previousJson);

        // Then
        assertEquals("-500", diff.get("lovelace"));
    }

    @Test
    void testCalculateSignedDiff_WithAssets() {
        // Given
        Value previous = createBalanceWithAssets(
                BigInteger.valueOf(1000),
                "policyId1", "assetName1", BigInteger.valueOf(100)
        );
        Value current = createBalanceWithAssets(
                BigInteger.valueOf(2000),
                "policyId1", "assetName1", BigInteger.valueOf(75)
        );

        String previousJson = BalanceValueHelper.toJson(previous);
        String currentJson = BalanceValueHelper.toJson(current);

        // When
        Map<String, String> diff = BalanceValueHelper.calculateSignedDiff(currentJson, previousJson);

        // Then
        assertEquals("1000", diff.get("lovelace")); // Increased by 1000
        assertEquals("-25", diff.get("policyId1assetName1")); // Decreased by 25
    }

    @Test
    void testCalculateSignedDiff_FirstTransaction() {
        // Given - no previous balance
        Value current = Value.builder().coin(BigInteger.valueOf(1000)).build();
        String currentJson = BalanceValueHelper.toJson(current);

        // When
        Map<String, String> diff = BalanceValueHelper.calculateSignedDiff(currentJson, null);

        // Then
        assertEquals("1000", diff.get("lovelace"));
    }

    @Test
    void testCalculateSignedDiff_NewAssetAdded() {
        // Given - asset added in current
        Value previous = Value.builder().coin(BigInteger.valueOf(1000)).build();
        Value current = createBalanceWithAssets(
                BigInteger.valueOf(1000),
                "policyId1", "assetName1", BigInteger.valueOf(50)
        );

        String previousJson = BalanceValueHelper.toJson(previous);
        String currentJson = BalanceValueHelper.toJson(current);

        // When
        Map<String, String> diff = BalanceValueHelper.calculateSignedDiff(currentJson, previousJson);

        // Then
        assertFalse(diff.containsKey("lovelace")); // No change in lovelace
        assertEquals("50", diff.get("policyId1assetName1")); // New asset
    }

    @Test
    void testCalculateSignedDiff_AssetRemoved() {
        // Given - asset removed in current
        Value previous = createBalanceWithAssets(
                BigInteger.valueOf(1000),
                "policyId1", "assetName1", BigInteger.valueOf(50)
        );
        Value current = Value.builder().coin(BigInteger.valueOf(1000)).build();

        String previousJson = BalanceValueHelper.toJson(previous);
        String currentJson = BalanceValueHelper.toJson(current);

        // When
        Map<String, String> diff = BalanceValueHelper.calculateSignedDiff(currentJson, previousJson);

        // Then
        assertFalse(diff.containsKey("lovelace")); // No change in lovelace
        assertEquals("-50", diff.get("policyId1assetName1")); // Asset removed (negative)
    }

    @Test
    void testCalculateSignedDiff_NoChange() {
        // Given - identical balances
        Value balance = Value.builder().coin(BigInteger.valueOf(1000)).build();
        String json = BalanceValueHelper.toJson(balance);

        // When
        Map<String, String> diff = BalanceValueHelper.calculateSignedDiff(json, json);

        // Then
        assertTrue(diff.isEmpty()); // No changes
    }

    // Helper method
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
}
