package org.cardanofoundation.cip113;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.aiken.AikenTransactionEvaluator;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BigIntPlutusData;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.easy1staking.cardano.model.AssetType;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.blueprint.Plutus;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.util.List;

@Slf4j
@Disabled("Integration test - requires Blockfrost API key and Preview network access")
public class TransferTokenTest extends AbstractPreviewTest {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    private static final String SUBSTANDARD_ISSUE_CONTRACT = "585701010029800aba2aba1aab9eaab9dab9a4888896600264646644b30013370e900218031baa00289919b87375a6012008906400980418039baa0028a504014600c600e002600c004600c00260066ea801a29344d9590011";

    private static final String SUBSTANDARD_TRANSFER_CONTRACT = "585701010029800aba2aba1aab9eaab9dab9a4888896600264646644b30013370e900218031baa00289919b87375a6012008904801980418039baa0028a504014600c600e002600c004600c00260066ea801a29344d9590011";

    private String DIRECTORY_SPEND_CONTRACT, PROGRAMMABLE_LOGIC_BASE_CONTRACT, PROGRAMMABLE_LOGIC_GLOBAL_CONTRACT;

    private ProtocolBootstrapParams protocolBootstrapParams;

    @BeforeEach
    public void loadContracts() throws Exception {
        protocolBootstrapParams = OBJECT_MAPPER.readValue(this.getClass().getClassLoader().getResourceAsStream("protocolBootstrap.json"), ProtocolBootstrapParams.class);
        var plutus = OBJECT_MAPPER.readValue(this.getClass().getClassLoader().getResourceAsStream("plutus.json"), Plutus.class);
        var validators = plutus.validators();
        DIRECTORY_SPEND_CONTRACT = getCompiledCodeFor("registry_spend.registry_spend.spend", validators);
        PROGRAMMABLE_LOGIC_BASE_CONTRACT = getCompiledCodeFor("programmable_logic_base.programmable_logic_base.spend", validators);
        PROGRAMMABLE_LOGIC_GLOBAL_CONTRACT = getCompiledCodeFor("programmable_logic_global.programmable_logic_global.withdraw", validators);
    }

    @Test
    public void test() throws Exception {

        var dryRun = false;

        var bootstrapTxHash = protocolBootstrapParams.txHash();

        var progToken = AssetType.fromUnit("0befd1269cf3b5b41cce136c92c64b45dde93e4bfe11875839b713d150494e54");
        var directoryNftUnit = "430eee9d0a6a57bd6552133a60bc2a8fe81e9e915ccb2392d7129bc60befd1269cf3b5b41cce136c92c64b45dde93e4bfe11875839b713d1";

        // Protocol Params 2592ff5b2810679c30996c309080a3635071f923b43edb494a87597c1e6a5be5:0
        // Directory 2592ff5b2810679c30996c309080a3635071f923b43edb494a87597c1e6a5be5:1
        // Issuance 2592ff5b2810679c30996c309080a3635071f923b43edb494a87597c1e6a5be5:2


        var protocolParamsUtxoOpt = bfBackendService.getUtxoService().getTxOutput(bootstrapTxHash, 0);
        if (!protocolParamsUtxoOpt.isSuccessful()) {
            Assertions.fail("could not fetch protocol params utxo");
        }
        var protocolParamsUtxo = protocolParamsUtxoOpt.getValue();
        log.info("protocolParamsUtxo: {}", protocolParamsUtxo);

        var utxosOpt = bfBackendService.getUtxoService().getUtxos(aliceAccount.baseAddress(), 100, 1);
        if (!utxosOpt.isSuccessful() || utxosOpt.getValue().isEmpty()) {
            Assertions.fail("no utxos available");
        }
        var walletUtxos = utxosOpt.getValue();

        var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(SUBSTANDARD_ISSUE_CONTRACT, PlutusVersion.v3);
        log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());
        var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network);
        log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

        var substandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(SUBSTANDARD_TRANSFER_CONTRACT, PlutusVersion.v3);
        log.info("substandardTransferContract: {}", substandardTransferContract.getPolicyId());
        var substandardTransferAddress = AddressProvider.getRewardAddress(substandardTransferContract, network);
        log.info("substandardTransferAddress: {}", substandardTransferAddress.getAddress());


        // Programmable Logic Global parameterization
        var programmableLogicGlobalParameters = ListPlutusData.of(BytesPlutusData.of(HexUtil.decodeHexString(protocolBootstrapParams.protocolParams().scriptHash())));
        var programmableLogicGlobalContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(programmableLogicGlobalParameters, PROGRAMMABLE_LOGIC_GLOBAL_CONTRACT), PlutusVersion.v3);
        log.info("programmableLogicGlobalContract policy: {}", programmableLogicGlobalContract.getPolicyId());
        var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobalContract, network);
        log.info("programmableLogicGlobalAddress policy: {}", programmableLogicGlobalAddress.getAddress());
//
//        var registerAddressTx = new Tx()
//                .from(adminAccount.baseAddress())
//                .registerStakeAddress(programmableLogicGlobalAddress.getAddress())
//                .withChangeAddress(adminAccount.baseAddress());
//
//        quickTxBuilder.compose(registerAddressTx)
//                .feePayer(adminAccount.baseAddress())
//                .withSigner(SignerProviders.signerFrom(adminAccount))
//                .completeAndWait();

        // Programmable Logic Base parameterization
        var programmableLogicBaseParameters = ListPlutusData.of(ConstrPlutusData.of(1, BytesPlutusData.of(programmableLogicGlobalContract.getScriptHash())));
        var programmableLogicBaseContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(programmableLogicBaseParameters, PROGRAMMABLE_LOGIC_BASE_CONTRACT), PlutusVersion.v3);
        log.info("programmableLogicBaseContract policy: {}", programmableLogicBaseContract.getPolicyId());


        // Directory SPEND parameterization
        var directorySpendParameters = ListPlutusData.of(
                BytesPlutusData.of(HexUtil.decodeHexString(protocolBootstrapParams.protocolParams().scriptHash()))
        );
        var directorySpendContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(directorySpendParameters, DIRECTORY_SPEND_CONTRACT), PlutusVersion.v3);
        var directorySpendContractAddress = AddressProvider.getEntAddress(Credential.fromScript(directorySpendContract.getScriptHash()), network);


        var directoryUtxosOpt = bfBackendService.getUtxoService().getUtxos(directorySpendContractAddress.getAddress(), 100, 1);
        if (!directoryUtxosOpt.isSuccessful()) {
            Assertions.fail("no directories");
        }
        var directoryUtxos = directoryUtxosOpt.getValue();
        directoryUtxos.forEach(utxo -> log.info("directory utxo: {}", utxo));

        var directoryUtxoOpt = directoryUtxos.stream().filter(utxo -> utxo.getAmount().stream().anyMatch(amount -> directoryNftUnit.equals(amount.getUnit()))).findAny();
        if (directoryUtxoOpt.isEmpty()) {
            Assertions.fail("no directory utxo for unit: " + directoryNftUnit);
        }
        var directoryUtxo = directoryUtxoOpt.get();
        log.info("directoryUtxo: {}", directoryUtxo);


        var aliceAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                aliceAccount.getBaseAddress().getDelegationCredential().get(),
                network);
        log.info("aliceAddress: {}", aliceAddress);
        var progBaseAddressUtxosOpt = bfBackendService.getUtxoService().getUtxos(aliceAddress.getAddress(), 100, 1);
        if (!progBaseAddressUtxosOpt.isSuccessful() || progBaseAddressUtxosOpt.getValue().isEmpty()) {
            Assertions.fail("not progBaseAddresses");
        }

        var bobAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                bobAccount.getBaseAddress().getDelegationCredential().get(),
                network);
        log.info("bobAddress: {}", bobAddress);

        var progBaseAddressUtxos = progBaseAddressUtxosOpt.getValue();
        progBaseAddressUtxos.forEach(utxo -> log.info("prog tokens utxo: {}", utxo));
        var progTokenUtxoOpt = progBaseAddressUtxos.stream().filter(utxo -> utxo.getAmount().stream().anyMatch(amount -> progToken.toUnit().equals(amount.getUnit()))).findAny();
        if (progTokenUtxoOpt.isEmpty()) {
            Assertions.fail("no prog token utxo for unit: " + progToken);
        }
        var progTokenUtxo = progTokenUtxoOpt.get();
        log.info("progTokenUtxo: {}", progTokenUtxo);

        var initialValue = progTokenUtxo.toValue();
        var tokenAmount = initialValue.amountOf(progToken.policyId(), "0x" + progToken.assetName());
        var amount1 = tokenAmount.divide(BigInteger.TWO);
        var amount2 = tokenAmount.subtract(amount1);

        // Programmable Token Mint
        var tokenAsset1 = Asset.builder()
                .name(HexUtil.encodeHexString("PINT".getBytes(), true))
                .value(amount1)
                .build();

        var tokenAsset2 = Asset.builder()
                .name(HexUtil.encodeHexString("PINT".getBytes(), true))
                .value(amount1)
                .build();

        Value tokenValue1 = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(progToken.policyId())
                                .assets(List.of(tokenAsset1))
                                .build()
                ))
                .build();

        Value tokenValue2 = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(progToken.policyId())
                                .assets(List.of(tokenAsset2))
                                .build()
                ))
                .build();


//        /// Redeemer for the global programmable logic stake validator
//pub type ProgrammableLogicGlobalRedeemer {
//  /// Transfer action with proofs for each token type
//  TransferAct { proofs: List<TokenProof> }
//  /// Seize action to confiscate tokens from blacklisted address
//  SeizeAct {
//    seize_input_idx: Int,
//    seize_output_idx: Int,
//    directory_node_idx: Int,
//  }
//}

        var programmableGlobalRedeemer = ConstrPlutusData.of(0,
                // only one prop and it's a list
                ListPlutusData.of(ConstrPlutusData.of(0, BigIntPlutusData.of(1)))
        );

        log.info("protocolBootstrapParams.programmableGlobalRefInput(): {}", protocolBootstrapParams.programmableGlobalRefInput());

        var tx = new ScriptTx()
                .collectFrom(walletUtxos)
                .collectFrom(progTokenUtxo, ConstrPlutusData.of(0))
                // must be first Provide proofs
                .withdraw(substandardTransferAddress.getAddress(), BigInteger.ZERO, BigIntPlutusData.of(200))
                .withdraw(programmableLogicGlobalAddress.getAddress(), BigInteger.ZERO, programmableGlobalRedeemer)
                .payToContract(aliceAddress.getAddress(), ValueUtil.toAmountList(tokenValue1), ConstrPlutusData.of(0))
                .payToContract(bobAddress.getAddress(), ValueUtil.toAmountList(tokenValue2), ConstrPlutusData.of(0))
                .payToAddress(aliceAccount.baseAddress(), Amount.ada(5))
                .payToAddress(aliceAccount.baseAddress(), Amount.ada(5))
                .readFrom(TransactionInput.builder()
                        .transactionId(protocolParamsUtxo.getTxHash())
                        .index(protocolParamsUtxo.getOutputIndex())
                        .build(), TransactionInput.builder()
                        .transactionId(directoryUtxo.getTxHash())
                        .index(directoryUtxo.getOutputIndex())
                        .build())
                .attachRewardValidator(programmableLogicGlobalContract) // global
                .attachRewardValidator(substandardTransferContract)
                .attachSpendingValidator(programmableLogicBaseContract) // base
                .withChangeAddress(aliceAccount.baseAddress());

        var transaction = quickTxBuilder.compose(tx)
                .withSigner(SignerProviders.signerFrom(aliceAccount))
                .withSigner(SignerProviders.stakeKeySignerFrom(aliceAccount))
                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                .withRequiredSigners(aliceAccount.getBaseAddress().getDelegationCredentialHash().get())
                .feePayer(aliceAccount.baseAddress())
                .mergeOutputs(false)
                .buildAndSign();

        log.info("tx: {}", transaction.serializeToHex());
        log.info("tx: {}", OBJECT_MAPPER.writeValueAsString(transaction));

        if (!dryRun) {
            var result = bfBackendService.getTransactionService().submitTransaction(transaction.serialize());
            if (result.isSuccessful()) {
                log.info("submitted: {}", result.getValue());
            } else {
                log.warn("error: {}", result.getResponse());
            }
        }

    }


}
