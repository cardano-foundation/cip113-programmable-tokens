package org.cardanofoundation.cip113;

import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.util.ArrayList;
import java.util.List;

/**
 * Utility test to discover programmable tokens available in the sub-accounts.
 * <p>
 * This helps identify what tokens exist at the programmable addresses for alice and bob,
 * which is required for running the TransferTokenTest.
 * <p>
 * Run with:
 * <pre>
 * ./gradlew manualIntegrationTest --tests "org.cardanofoundation.cip113.DiscoverTokensTest"
 * </pre>
 */
@Slf4j
@Tag("manual-integration")
public class DiscoverTokensTest extends AbstractPreviewTest {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    @Test
    public void discoverTokensAtProgrammableAddresses() throws Exception {
        var protocolBootstrapParams = OBJECT_MAPPER.readValue(
                this.getClass().getClassLoader().getResourceAsStream("protocolBootstrap.json"),
                ProtocolBootstrapParams.class);

        var programmableBaseScriptHash = protocolBootstrapParams.programmableLogicBaseParams().scriptHash();
        log.info("Programmable Logic Base Script Hash: {}", programmableBaseScriptHash);

        // Alice's programmable address
        var aliceAddress = AddressProvider.getBaseAddress(
                Credential.fromScript(programmableBaseScriptHash),
                aliceAccount.getBaseAddress().getDelegationCredential().get(),
                network);
        log.info("Alice's programmable address: {}", aliceAddress.getAddress());

        // Bob's programmable address
        var bobAddress = AddressProvider.getBaseAddress(
                Credential.fromScript(programmableBaseScriptHash),
                bobAccount.getBaseAddress().getDelegationCredential().get(),
                network);
        log.info("Bob's programmable address: {}", bobAddress.getAddress());

        log.info("=========================================");
        log.info("ALICE'S PROGRAMMABLE TOKENS:");
        log.info("=========================================");
        discoverTokensAtAddress(aliceAddress.getAddress());

        log.info("=========================================");
        log.info("BOB'S PROGRAMMABLE TOKENS:");
        log.info("=========================================");
        discoverTokensAtAddress(bobAddress.getAddress());

        // Also check the directory for registered tokens
        log.info("=========================================");
        log.info("REGISTRY (Directory) TOKENS:");
        log.info("=========================================");
        var directorySpendScriptHash = protocolBootstrapParams.directorySpendParams().scriptHash();
        var directoryAddress = AddressProvider.getEntAddress(
                Credential.fromScript(directorySpendScriptHash),
                network);
        log.info("Directory address: {}", directoryAddress.getAddress());
        discoverTokensAtAddress(directoryAddress.getAddress());
    }

    private void discoverTokensAtAddress(String address) {
        try {
            var utxosOpt = bfBackendService.getUtxoService().getUtxos(address, 100, 1);
            if (!utxosOpt.isSuccessful() || utxosOpt.getValue().isEmpty()) {
                log.info("No UTxOs found at address: {}", address);
                return;
            }

            var utxos = utxosOpt.getValue();
            log.info("Found {} UTxOs", utxos.size());

            List<String> tokens = new ArrayList<>();
            for (var utxo : utxos) {
                log.info("UTxO: {}#{}", utxo.getTxHash(), utxo.getOutputIndex());
                for (var amount : utxo.getAmount()) {
                    if (!"lovelace".equals(amount.getUnit())) {
                        String policyId = amount.getUnit().substring(0, 56);
                        String assetName = amount.getUnit().substring(56);
                        String assetNameStr = hexToString(assetName);
                        BigInteger quantity = amount.getQuantity();

                        log.info("  Token: {} ({})", amount.getUnit(), assetNameStr);
                        log.info("    Policy ID: {}", policyId);
                        log.info("    Asset Name (hex): {}", assetName);
                        log.info("    Asset Name (str): {}", assetNameStr);
                        log.info("    Quantity: {}", quantity);
                        tokens.add(amount.getUnit());
                    } else {
                        log.info("  ADA: {} lovelace ({} ADA)",
                                amount.getQuantity(),
                                amount.getQuantity().divide(BigInteger.valueOf(1_000_000)));
                    }
                }
                if (utxo.getInlineDatum() != null) {
                    log.info("  Inline Datum: {}", utxo.getInlineDatum());
                }
            }

            if (tokens.isEmpty()) {
                log.info("No native tokens found at this address.");
            } else {
                log.info("Total unique token types: {}", tokens.size());
            }
        } catch (Exception e) {
            log.error("Error discovering tokens: {}", e.getMessage());
        }
    }

    private String hexToString(String hex) {
        if (hex == null || hex.isEmpty()) {
            return "";
        }
        try {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < hex.length(); i += 2) {
                String str = hex.substring(i, i + 2);
                sb.append((char) Integer.parseInt(str, 16));
            }
            return sb.toString();
        } catch (Exception e) {
            return hex;
        }
    }
}
