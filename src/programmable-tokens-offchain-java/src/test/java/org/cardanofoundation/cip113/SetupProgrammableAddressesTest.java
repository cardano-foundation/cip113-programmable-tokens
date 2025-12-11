package org.cardanofoundation.cip113;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.quicktx.Tx;
import com.bloxbean.cardano.client.util.HexUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.blueprint.Plutus;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;

import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Sends ADA to alice and bob's programmable token addresses.
 * This is needed before tokens can be received at those addresses.
 * <p>
 * Run with: ./gradlew manualIntegrationTest --tests SetupProgrammableAddressesTest
 */
@Slf4j
@Tag("manual-integration")
public class SetupProgrammableAddressesTest extends AbstractPreviewTest {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
    private ProtocolBootstrapParams protocolBootstrapParams;
    private String PROGRAMMABLE_LOGIC_BASE_CONTRACT;
    private String PROGRAMMABLE_LOGIC_GLOBAL_CONTRACT;

    @BeforeEach
    public void loadContracts() throws Exception {
        protocolBootstrapParams = OBJECT_MAPPER.readValue(
            getClass().getClassLoader().getResourceAsStream("protocolBootstrap.json"),
            ProtocolBootstrapParams.class);
        var plutus = OBJECT_MAPPER.readValue(
            getClass().getClassLoader().getResourceAsStream("plutus.json"),
            Plutus.class);
        PROGRAMMABLE_LOGIC_BASE_CONTRACT = getCompiledCodeFor("programmable_logic_base.programmable_logic_base.spend", plutus.validators());
        PROGRAMMABLE_LOGIC_GLOBAL_CONTRACT = getCompiledCodeFor("programmable_logic_global.programmable_logic_global.withdraw", plutus.validators());
    }

    @Test
    public void setupAliceAndBobProgrammableAddresses() throws Exception {
        log.info("=== Setting up Programmable Token Addresses for Alice and Bob ===");

        // Get the programmable logic base script
        var programmableLogicGlobalParameters = ListPlutusData.of(
            BytesPlutusData.of(HexUtil.decodeHexString(protocolBootstrapParams.protocolParams().scriptHash())));
        var programmableLogicGlobalContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
            AikenScriptUtil.applyParamToScript(programmableLogicGlobalParameters, PROGRAMMABLE_LOGIC_GLOBAL_CONTRACT),
            PlutusVersion.v3);

        var programmableLogicBaseParameters = ListPlutusData.of(
            ConstrPlutusData.of(1, BytesPlutusData.of(programmableLogicGlobalContract.getScriptHash())));
        var programmableLogicBaseContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
            AikenScriptUtil.applyParamToScript(programmableLogicBaseParameters, PROGRAMMABLE_LOGIC_BASE_CONTRACT),
            PlutusVersion.v3);

        log.info("Programmable Logic Base Script Hash: {}", programmableLogicBaseContract.getPolicyId());

        // Create alice's programmable address (script + alice's stake credential)
        var aliceProgrammableAddress = AddressProvider.getBaseAddress(
            Credential.fromScript(programmableLogicBaseContract.getScriptHash()),
            aliceAccount.getBaseAddress().getDelegationCredential().get(),
            network);
        log.info("Alice Programmable Address: {}", aliceProgrammableAddress.getAddress());

        // Create bob's programmable address (script + bob's stake credential)
        var bobProgrammableAddress = AddressProvider.getBaseAddress(
            Credential.fromScript(programmableLogicBaseContract.getScriptHash()),
            bobAccount.getBaseAddress().getDelegationCredential().get(),
            network);
        log.info("Bob Programmable Address: {}", bobProgrammableAddress.getAddress());

        // Check if addresses already have UTxOs
        var aliceUtxos = bfBackendService.getUtxoService().getUtxos(aliceProgrammableAddress.getAddress(), 10, 1);
        var bobUtxos = bfBackendService.getUtxoService().getUtxos(bobProgrammableAddress.getAddress(), 10, 1);

        boolean aliceNeedsFunding = !aliceUtxos.isSuccessful() || aliceUtxos.getValue().isEmpty();
        boolean bobNeedsFunding = !bobUtxos.isSuccessful() || bobUtxos.getValue().isEmpty();

        if (!aliceNeedsFunding && !bobNeedsFunding) {
            log.info("Both programmable addresses already have UTxOs:");
            log.info("  Alice has {} UTxOs", aliceUtxos.getValue().size());
            log.info("  Bob has {} UTxOs", bobUtxos.getValue().size());
            return;
        }

        log.info("Sending ADA to programmable addresses...");

        // Send 5 ADA to each programmable address with empty datum
        var tx = new Tx()
            .payToContract(aliceProgrammableAddress.getAddress(), Amount.ada(5), ConstrPlutusData.of(0))
            .payToContract(bobProgrammableAddress.getAddress(), Amount.ada(5), ConstrPlutusData.of(0))
            .from(adminAccount.baseAddress());

        var result = quickTxBuilder.compose(tx)
            .withSigner(SignerProviders.signerFrom(adminAccount))
            .completeAndWait(msg -> log.info("Tx: {}", msg));

        assertTrue(result.isSuccessful(), "Failed to send ADA: " + result.getResponse());

        log.info("================================================================================");
        log.info("SUCCESS! Programmable addresses funded with empty datum UTxOs.");
        log.info("================================================================================");
        log.info("Transaction: {}", result.getValue());
        log.info("Alice Programmable: {}", aliceProgrammableAddress.getAddress());
        log.info("Bob Programmable: {}", bobProgrammableAddress.getAddress());
        log.info("");
        log.info("View: https://preview.cardanoscan.io/transaction/{}", result.getValue());
        log.info("================================================================================");
    }
}
