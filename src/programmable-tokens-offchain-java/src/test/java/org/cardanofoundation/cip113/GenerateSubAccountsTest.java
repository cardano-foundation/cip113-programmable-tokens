package org.cardanofoundation.cip113;

import com.bloxbean.cardano.client.account.Account;
import com.bloxbean.cardano.client.common.model.Networks;
import org.junit.jupiter.api.Test;

/**
 * Utility to generate sub-account addresses for funding.
 * <p>
 * Run this test to get all addresses that need to be funded for the TransferTokenTest:
 * <pre>
 * ./gradlew test --tests GenerateSubAccountsTest
 * </pre>
 * <p>
 * After running, fund each address with at least 10 ADA from the Cardano Preview Faucet:
 * https://docs.cardano.org/cardano-testnets/tools/faucet/
 */
public class GenerateSubAccountsTest {

    @Test
    public void generateAllSubAccountAddresses() {
        var network = Networks.preview();
        var mnemonic = PreviewConstants.ADMIN_MNEMONIC;

        System.out.println("\n" + "=".repeat(80));
        System.out.println("SUB-ACCOUNT ADDRESSES FOR TRANSFER TOKEN TEST");
        System.out.println("=".repeat(80));
        System.out.println("\nMnemonic (first 4 words): " +
            String.join(" ", mnemonic.split(" ")[0], mnemonic.split(" ")[1],
                        mnemonic.split(" ")[2], mnemonic.split(" ")[3]) + " ...");
        System.out.println("\n" + "-".repeat(80));

        // Admin Account (derivation path: m/1852'/1815'/0'/0/0)
        var adminAccount = Account.createFromMnemonic(network, mnemonic);
        System.out.println("\n1. ADMIN ACCOUNT (Account Index 0)");
        System.out.println("   Base Address: " + adminAccount.baseAddress());
        System.out.println("   Stake Address: " + adminAccount.stakeAddress());
        System.out.println("   Status: PRIMARY - should already be funded with ~10,000 tADA");

        // Alice Account (derivation path: m/1852'/1815'/1'/0/0)
        var aliceAccount = Account.createFromMnemonic(network, mnemonic, 1, 0);
        System.out.println("\n2. ALICE ACCOUNT (Account Index 1)");
        System.out.println("   Base Address: " + aliceAccount.baseAddress());
        System.out.println("   Stake Address: " + aliceAccount.stakeAddress());
        System.out.println("   Required: YES - needs ~50 tADA for transfer tests");

        // Bob Account (derivation path: m/1852'/1815'/2'/0/0)
        var bobAccount = Account.createFromMnemonic(network, mnemonic, 2, 0);
        System.out.println("\n3. BOB ACCOUNT (Account Index 2)");
        System.out.println("   Base Address: " + bobAccount.baseAddress());
        System.out.println("   Stake Address: " + bobAccount.stakeAddress());
        System.out.println("   Required: YES - needs ~50 tADA for transfer tests");

        // Ref Input Account (derivation path: m/1852'/1815'/10'/0/0)
        var refInputAccount = Account.createFromMnemonic(network, mnemonic, 10, 0);
        System.out.println("\n4. REF INPUT ACCOUNT (Account Index 10)");
        System.out.println("   Base Address: " + refInputAccount.baseAddress());
        System.out.println("   Stake Address: " + refInputAccount.stakeAddress());
        System.out.println("   Required: OPTIONAL - for reference inputs if needed");

        System.out.println("\n" + "-".repeat(80));
        System.out.println("\nFUNDING INSTRUCTIONS:");
        System.out.println("-".repeat(80));
        System.out.println("\n1. Go to the Cardano Preview Faucet:");
        System.out.println("   https://docs.cardano.org/cardano-testnets/tools/faucet/");
        System.out.println("\n2. Select 'Preview' network");
        System.out.println("\n3. Fund each address (copy the Base Address):");
        System.out.println("\n   ALICE: " + aliceAccount.baseAddress());
        System.out.println("   BOB:   " + bobAccount.baseAddress());

        System.out.println("\n4. Wait for transactions to confirm (~20 seconds)");
        System.out.println("\n5. Run the transfer test:");
        System.out.println("   ./gradlew manualIntegrationTest");

        System.out.println("\n" + "=".repeat(80));
        System.out.println("QUICK COPY - ADDRESSES TO FUND:");
        System.out.println("=".repeat(80));
        System.out.println("\nALICE: " + aliceAccount.baseAddress());
        System.out.println("BOB:   " + bobAccount.baseAddress());
        System.out.println("\n" + "=".repeat(80) + "\n");
    }
}
