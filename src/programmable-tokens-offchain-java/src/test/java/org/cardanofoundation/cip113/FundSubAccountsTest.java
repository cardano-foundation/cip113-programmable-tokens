package org.cardanofoundation.cip113;

import com.bloxbean.cardano.client.account.Account;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.client.common.model.Networks;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.bloxbean.cardano.client.quicktx.Tx;
import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;

import static com.bloxbean.cardano.client.backend.blockfrost.common.Constants.BLOCKFROST_PREVIEW_URL;
import static com.bloxbean.cardano.client.common.ADAConversionUtil.adaToLovelace;

/**
 * Utility to fund sub-accounts (alice, bob) from the admin account.
 * <p>
 * Run this test to transfer tADA from admin to sub-accounts:
 * <pre>
 * ./gradlew test --tests FundSubAccountsTest
 * </pre>
 * <p>
 * Prerequisites:
 * - Admin account must have sufficient tADA (at least 200 tADA recommended)
 */
@Slf4j
@Tag("manual-integration")
public class FundSubAccountsTest {

    private static final BigInteger FUND_AMOUNT = adaToLovelace(50); // 50 ADA each

    @Test
    public void fundAliceAndBob() throws Exception {
        var network = Networks.preview();
        var mnemonic = PreviewConstants.ADMIN_MNEMONIC;

        // Create accounts
        var adminAccount = Account.createFromMnemonic(network, mnemonic);
        var aliceAccount = Account.createFromMnemonic(network, mnemonic, 1, 0);
        var bobAccount = Account.createFromMnemonic(network, mnemonic, 2, 0);

        log.info("Admin Address: {}", adminAccount.baseAddress());
        log.info("Alice Address: {}", aliceAccount.baseAddress());
        log.info("Bob Address: {}", bobAccount.baseAddress());

        // Setup backend
        var bfBackendService = new BFBackendService(BLOCKFROST_PREVIEW_URL, PreviewConstants.BLOCKFROST_KEY);
        var quickTxBuilder = new QuickTxBuilder(bfBackendService);

        // Check admin balance
        var adminUtxos = bfBackendService.getUtxoService().getUtxos(adminAccount.baseAddress(), 100, 1);
        if (!adminUtxos.isSuccessful() || adminUtxos.getValue().isEmpty()) {
            log.error("Admin account has no UTxOs. Please fund admin first: {}", adminAccount.baseAddress());
            throw new RuntimeException("Admin account not funded");
        }

        var adminBalance = adminUtxos.getValue().stream()
                .flatMap(utxo -> utxo.getAmount().stream())
                .filter(a -> "lovelace".equals(a.getUnit()))
                .map(Amount::getQuantity)
                .reduce(BigInteger.ZERO, BigInteger::add);

        log.info("Admin balance: {} lovelace ({} ADA)", adminBalance, adminBalance.divide(BigInteger.valueOf(1_000_000)));

        // Check if we have enough (need ~105 ADA: 50 + 50 + fees)
        var requiredAmount = FUND_AMOUNT.multiply(BigInteger.TWO).add(adaToLovelace(5)); // 105 ADA
        if (adminBalance.compareTo(requiredAmount) < 0) {
            log.error("Insufficient funds. Need at least {} lovelace, have {}", requiredAmount, adminBalance);
            throw new RuntimeException("Insufficient funds in admin account");
        }

        // Check if alice/bob already funded
        var aliceUtxos = bfBackendService.getUtxoService().getUtxos(aliceAccount.baseAddress(), 100, 1);
        var bobUtxos = bfBackendService.getUtxoService().getUtxos(bobAccount.baseAddress(), 100, 1);

        boolean aliceNeedsFunding = !aliceUtxos.isSuccessful() || aliceUtxos.getValue().isEmpty();
        boolean bobNeedsFunding = !bobUtxos.isSuccessful() || bobUtxos.getValue().isEmpty();

        if (!aliceNeedsFunding && !bobNeedsFunding) {
            log.info("Both alice and bob already have UTxOs. Skipping funding.");
            log.info("Alice UTxOs: {}", aliceUtxos.getValue().size());
            log.info("Bob UTxOs: {}", bobUtxos.getValue().size());
            return;
        }

        log.info("Funding sub-accounts...");
        log.info("  Alice needs funding: {}", aliceNeedsFunding);
        log.info("  Bob needs funding: {}", bobNeedsFunding);

        // Build and submit transaction
        var tx = new Tx()
                .payToAddress(aliceAccount.baseAddress(), Amount.lovelace(FUND_AMOUNT))
                .payToAddress(bobAccount.baseAddress(), Amount.lovelace(FUND_AMOUNT))
                .from(adminAccount.baseAddress());

        var result = quickTxBuilder.compose(tx)
                .withSigner(SignerProviders.signerFrom(adminAccount))
                .completeAndWait(msg -> log.info("Tx: {}", msg));

        if (result.isSuccessful()) {
            log.info("================================================================================");
            log.info("SUCCESS! Sub-accounts funded.");
            log.info("================================================================================");
            log.info("Transaction Hash: {}", result.getValue());
            log.info("Alice received: {} ADA at {}", FUND_AMOUNT.divide(BigInteger.valueOf(1_000_000)), aliceAccount.baseAddress());
            log.info("Bob received: {} ADA at {}", FUND_AMOUNT.divide(BigInteger.valueOf(1_000_000)), bobAccount.baseAddress());
            log.info("");
            log.info("View transaction: https://preview.cardanoscan.io/transaction/{}", result.getValue());
            log.info("");
            log.info("You can now run the transfer test:");
            log.info("  ./gradlew manualIntegrationTest");
            log.info("================================================================================");
        } else {
            log.error("Failed to fund sub-accounts: {}", result.getResponse());
            throw new RuntimeException("Funding transaction failed");
        }
    }
}
