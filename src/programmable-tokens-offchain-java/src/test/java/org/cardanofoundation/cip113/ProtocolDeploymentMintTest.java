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
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.quicktx.Tx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.blueprint.Plutus;
import org.cardanofoundation.cip113.model.bootstrap.*;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.util.List;

@Slf4j
public class ProtocolDeploymentMintTest extends AbstractPreviewTest {


    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    private String PROGRAMMABLE_LOGIC_GLOBAL_CONTRACT;

    private String PROGRAMMABLE_LOGIC_BASE_CONTRACT;

    private String PROTOCOL_PARAMS_CONTRACT;

    private String DIRECTORY_MINT_CONTRACT;

    private String DIRECTORY_SPEND_CONTRACT;

    private String ISSUANCE_CBOR_HEX_CONTRACT;

    private String ISSUANCE_CONTRACT;

    @BeforeEach
    public void loadContracts() throws Exception {
        var plutus = OBJECT_MAPPER.readValue(this.getClass().getClassLoader().getResourceAsStream("plutus.json"), Plutus.class);
        var validators = plutus.validators();
        PROGRAMMABLE_LOGIC_GLOBAL_CONTRACT = getCompiledCodeFor("programmable_logic_global.programmable_logic_global.withdraw", validators);
        PROGRAMMABLE_LOGIC_BASE_CONTRACT = getCompiledCodeFor("programmable_logic_base.programmable_logic_base.spend", validators);
        PROTOCOL_PARAMS_CONTRACT = getCompiledCodeFor("protocol_params_mint.protocol_params_mint.mint", validators);
        DIRECTORY_MINT_CONTRACT = getCompiledCodeFor("registry_mint.registry_mint.mint", validators);
        DIRECTORY_SPEND_CONTRACT = getCompiledCodeFor("registry_spend.registry_spend.spend", validators);
        ISSUANCE_CBOR_HEX_CONTRACT = getCompiledCodeFor("issuance_cbor_hex_mint.issuance_cbor_hex_mint.mint", validators);
        ISSUANCE_CONTRACT = getCompiledCodeFor("issuance_mint.issuance_mint.mint", validators);
    }

    @Test
    public void test() throws Exception {

        var dryRun = false;

        var utxosOpt = bfBackendService.getUtxoService().getUtxos(adminAccount.baseAddress(), 100, 1);
        if (!utxosOpt.isSuccessful() || utxosOpt.getValue().size() < 3) {
            Assertions.fail("no(t enough) utxos available");
        }
        var allWalletUtxos = utxosOpt.getValue();
        var walletUtxos = utxosOpt.getValue().stream().limit(2).toList();

        var utxo1 = walletUtxos.getFirst();
        var utxo2 = walletUtxos.getLast();

        Assertions.assertNotEquals(utxo1, utxo2);

        // Output Reference - utxo1
        var utxo1OutputReference = ConstrPlutusData.of(0,
                BytesPlutusData.of(HexUtil.decodeHexString(utxo1.getTxHash())),
                BigIntPlutusData.of(utxo1.getOutputIndex()));

        // Output Reference - utxo2
        var utxo2OutputReference = ConstrPlutusData.of(0,
                BytesPlutusData.of(HexUtil.decodeHexString(utxo2.getTxHash())),
                BigIntPlutusData.of(utxo2.getOutputIndex()));

        // Protocol Params contract parameterization
        var protocolParamsParameters = ListPlutusData.of(utxo1OutputReference);
        var protocolParamsContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(protocolParamsParameters, PROTOCOL_PARAMS_CONTRACT), PlutusVersion.v3);
        log.info("protocolParamsContract, policy: {}", protocolParamsContract.getPolicyId());
        log.info("protocolParamsContract, hash: {}", HexUtil.encodeHexString(protocolParamsContract.getScriptHash()));

        // Programmable Logic Global parameterization
//        var programmableLogicGlobalParameters = ListPlutusData.of(ConstrPlutusData.of(0, BytesPlutusData.of(protocolParamsContract.getScriptHash())));
        var programmableLogicGlobalParameters = ListPlutusData.of(BytesPlutusData.of(protocolParamsContract.getScriptHash()));
        var programmableLogicGlobalContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(programmableLogicGlobalParameters, PROGRAMMABLE_LOGIC_GLOBAL_CONTRACT), PlutusVersion.v3);
        var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobalContract, network);
        log.info("programmableLogicGlobalAddress policy: {}", programmableLogicGlobalAddress.getAddress());

        // Programmable Logic Base parameterization
        var programmableLogicBaseParameters = ListPlutusData.of(ConstrPlutusData.of(1, BytesPlutusData.of(programmableLogicGlobalContract.getScriptHash())));
        var programmableLogicBaseContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(programmableLogicBaseParameters, PROGRAMMABLE_LOGIC_BASE_CONTRACT), PlutusVersion.v3);


        // The payment credentials where all prog tokens live
        var baseProgrammableLogicPaymentCredential = ConstrPlutusData.of(1,
                BytesPlutusData.of(programmableLogicBaseContract.getScriptHash())
        );

        // Issuance Mint parameterization
        // Protocol Params contract parameterization
        var issuanceParameters = ListPlutusData.of(utxo2OutputReference);
        var issuanceContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(issuanceParameters, ISSUANCE_CBOR_HEX_CONTRACT), PlutusVersion.v3);

        // Directory MINT parameterization
        var directoryParameters = ListPlutusData.of(
                ConstrPlutusData.of(0,
                        BytesPlutusData.of(HexUtil.decodeHexString(utxo1.getTxHash())),
                        BigIntPlutusData.of(utxo1.getOutputIndex())),
                BytesPlutusData.of(issuanceContract.getScriptHash())
        );
        var directoryContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(directoryParameters, DIRECTORY_MINT_CONTRACT), PlutusVersion.v3);

        // Directory SPEND parameterization
        var directorySpendParameters = ListPlutusData.of(
                BytesPlutusData.of(protocolParamsContract.getScriptHash())
        );
        var directorySpendContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(directorySpendParameters, DIRECTORY_SPEND_CONTRACT), PlutusVersion.v3);
        var directorySpendContractAddress = AddressProvider.getEntAddress(Credential.fromScript(directorySpendContract.getScriptHash()), network);
        log.info("directorySpendContractAddress: {}", directorySpendContractAddress.getAddress());


        // Protocol Params MINT - NFT, address, datum and value
        var protocolParamNft = Asset.builder()
                .name(HexUtil.encodeHexString("ProtocolParams".getBytes(), true))
                .value(BigInteger.ONE)
                .build();

        var protocolParamsContractAddress = AddressProvider.getEntAddress(Credential.fromScript(protocolParamsContract.getScriptHash()), network);
        log.info("protocolParamsContractAddress: {}", protocolParamsContractAddress.getAddress());

        var protocolParamsDatum = ConstrPlutusData.of(0,
                BytesPlutusData.of(directoryContract.getScriptHash()),
                // This is the payment credential for ALL permissioned tokens
                baseProgrammableLogicPaymentCredential
        );

        Value protocolParamsValue = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(protocolParamsContract.getPolicyId())
                                .assets(List.of(protocolParamNft))
                                .build()
                ))
                .build();

        // Directory MINT - NFT, address, datum and value
        var directoryNft = Asset.builder()
                .name("0x")
                .value(BigInteger.ONE)
                .build();

        var directoryDatum = ConstrPlutusData.of(0,
                BytesPlutusData.of(""),
                BytesPlutusData.of(HexUtil.decodeHexString("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")),
                ConstrPlutusData.of(0, BytesPlutusData.of("")),
                ConstrPlutusData.of(0, BytesPlutusData.of("")),
                BytesPlutusData.of(""));

        Value directoryValue = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(directoryContract.getPolicyId())
                                .assets(List.of(directoryNft))
                                .build()
                ))
                .build();

        // Issuance MINT - NFT, address, datum and value
        var issuanceNft = Asset.builder()
                .name(HexUtil.encodeHexString("IssuanceCborHex".getBytes(), true))
                .value(BigInteger.ONE)
                .build();

        var issuanceAddress = AddressProvider.getEntAddress(Credential.fromScript(issuanceContract.getScriptHash()), network);
        log.info("issuanceAddress: {}", issuanceAddress.getAddress());

        Value issuanceValue = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(issuanceContract.getPolicyId())
                                .assets(List.of(issuanceNft))
                                .build()
                ))
                .build();

        // Issuance Contract Parameterization
        var dummyPolicyId = "deadbeefcafebabedeadbeefcafebabedeadbeefcafebabedeadbeef";
        var issuanceDummyParameters = ListPlutusData.of(
                ConstrPlutusData.of(1,
                        BytesPlutusData.of(programmableLogicBaseContract.getScriptHash())
                ),
                ConstrPlutusData.of(1,
                        BytesPlutusData.of(HexUtil.decodeHexString(dummyPolicyId))
                )
        );
        var issuanceDummyContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(issuanceDummyParameters, ISSUANCE_CONTRACT), PlutusVersion.v3);
        var encodedIssuanceDummyContract = HexUtil.encodeHexString(issuanceDummyContract.serializeScriptBody());
        var contractParts = encodedIssuanceDummyContract.split(dummyPolicyId);

        var issuanceDatum = ConstrPlutusData.of(0,
                BytesPlutusData.of(HexUtil.decodeHexString(contractParts[0])),
                BytesPlutusData.of(HexUtil.decodeHexString(contractParts[1])));

        var tx = new ScriptTx()
                //spend all wallets (coz we need to burn the bootstrap utxo)
                .collectFrom(walletUtxos)
                // Redeemer is DirectoryInit (constr(0))
                .mintAsset(directoryContract, directoryNft, ConstrPlutusData.of(0))
                // Redeemer unused
                .mintAsset(protocolParamsContract, protocolParamNft, ConstrPlutusData.of(1))
                // Redeemer unused
                .mintAsset(issuanceContract, issuanceNft, ConstrPlutusData.of(2))
                // Protocol Params
                .payToContract(protocolParamsContractAddress.getAddress(), ValueUtil.toAmountList(protocolParamsValue), protocolParamsDatum)
                // Directory Params
                .payToContract(directorySpendContractAddress.getAddress(), ValueUtil.toAmountList(directoryValue), directoryDatum)
                // Protocol Params
                .payToContract(issuanceAddress.getAddress(), ValueUtil.toAmountList(issuanceValue), issuanceDatum)
                .payToAddress(refInputAccount.baseAddress(), Amount.ada(1), programmableLogicBaseContract)
                .payToAddress(refInputAccount.baseAddress(), Amount.ada(1), programmableLogicGlobalContract)
                .payToAddress(adminAccount.baseAddress(), Amount.ada(50))
                .payToAddress(adminAccount.baseAddress(), Amount.ada(50))
                .withChangeAddress(adminAccount.baseAddress());

//                    .attachRewardValidator(programmableLogicGlobalContract) // global
//                .attachRewardValidator(substandardTransferContract)
//                .attachSpendingValidator(programmableLogicBaseContract) // base

        var transaction = quickTxBuilder.compose(tx)
                .withSigner(SignerProviders.signerFrom(adminAccount))
                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                .feePayer(adminAccount.baseAddress())
                .mergeOutputs(false)
                .buildAndSign();


        log.info("tx: {}", transaction.serializeToHex());
        log.info("tx: {}", OBJECT_MAPPER.writeValueAsString(transaction));

        String txHash;
        if (!dryRun) {
            var result = bfBackendService.getTransactionService().submitTransaction(transaction.serialize());
            if (result.isSuccessful()) {
                txHash = result.getValue();
                log.info("submitted: {}", result.getValue());
            } else {
                txHash = "error";
                log.warn("error: {}", result.getResponse());
            }

        } else {
            txHash = "dummy";
        }

        var protocolParams = new ProtocolParams(new TxInput(utxo1.getTxHash(), utxo1.getOutputIndex()), protocolParamsContract.getPolicyId());
        var programmableLogicGlobalParams = new ProgrammableLogicGlobalParams(protocolParamsContract.getPolicyId(), programmableLogicGlobalContract.getPolicyId());
        var programmableLogicBaseParams = new ProgrammableLogicBaseParams(programmableLogicGlobalContract.getPolicyId(), programmableLogicBaseContract.getPolicyId());
        var issuanceParams = new IssuanceParams(new TxInput(utxo2.getTxHash(), utxo2.getOutputIndex()), issuanceContract.getPolicyId());
        var directoryParams = new DirectoryMintParams(new TxInput(utxo1.getTxHash(), utxo1.getOutputIndex()), issuanceContract.getPolicyId(), directoryContract.getPolicyId());
        var directorySpendParams = new DirectorySpendParams(protocolParamsContract.getPolicyId(), directorySpendContract.getPolicyId());
        var programmableBaseRefInput = new TxInput(txHash, 3);
        var programmableGlobalRefInput = new TxInput(txHash, 4);

        var protocolBootstrapParams = new ProtocolBootstrapParams(protocolParams,
                programmableLogicGlobalParams,
                programmableLogicBaseParams,
                issuanceParams,
                directoryParams,
                directorySpendParams,
                programmableBaseRefInput,
                programmableGlobalRefInput,
                txHash);

        var stakeRegistrationTx = new Tx()
                .from(adminAccount.baseAddress())
                .collectFrom(List.of(allWalletUtxos.get(2)))
                .registerStakeAddress(programmableLogicGlobalAddress.getAddress())
                .withChangeAddress(adminAccount.baseAddress());

        new QuickTxBuilder(bfBackendService).compose(stakeRegistrationTx)
                .feePayer(adminAccount.baseAddress())
                .withSigner(SignerProviders.signerFrom(adminAccount))
                .completeAndWait();

        log.info("BootstrapParams: {}", OBJECT_MAPPER.writeValueAsString(protocolBootstrapParams));

    }


}
