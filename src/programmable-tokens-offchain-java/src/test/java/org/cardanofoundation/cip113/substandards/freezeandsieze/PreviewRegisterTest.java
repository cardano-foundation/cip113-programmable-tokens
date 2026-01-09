package org.cardanofoundation.cip113.substandards.freezeandsieze;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.aiken.AikenTransactionEvaluator;
import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.common.model.Network;
import com.bloxbean.cardano.client.common.model.Networks;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.quicktx.Tx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.easy1staking.cardano.model.AssetType;
import com.fasterxml.jackson.core.JsonProcessingException;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.AbstractPreviewTest;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.model.onchain.RegistryNode;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistBootstrap;
import org.cardanofoundation.cip113.service.*;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.util.List;
import java.util.Optional;

import static java.math.BigInteger.ONE;
import static org.cardanofoundation.cip113.util.PlutusSerializationHelper.serialize;

@Slf4j
public class PreviewRegisterTest extends AbstractPreviewTest {

    private static final String DEFAULT_PROTOCOL = "0c8e4c5da192e0c814495f685aebf31d27e2eec55a302c08ae56d3f8dd564489";

    private final Network network = Networks.preview();

    private final UtxoService utxoService = new UtxoService(bfBackendService, null);

    private final AccountService accountService = new AccountService(utxoService);

    private final ProtocolBootstrapService protocolBootstrapService = new ProtocolBootstrapService(OBJECT_MAPPER, new AppConfig.Network("preview"));

    private final ProtocolScriptBuilderService protocolScriptBuilderService = new ProtocolScriptBuilderService(protocolBootstrapService);

    private SubstandardService substandardService;

    private final RegistryNodeParser registryNodeParser = new RegistryNodeParser(OBJECT_MAPPER);

    @BeforeEach
    public void init() {
        substandardService = new SubstandardService(OBJECT_MAPPER);
        substandardService.init();

        protocolBootstrapService.init();
    }

    @Test
    public void test() throws Exception {

        var dryRun = false;

        var blacklistBoostrapJson = "{\"blacklistMintBootstrap\":{\"txInput\":{\"txHash\":\"7172a517d98d65dc9fdaf270cb52383de54840fbf44721d8ae82ae8d8175a1a5\",\"outputIndex\":1},\"adminPubKeyHash\":\"32e7e00eae28502a2aa271cf4202b1b01b94ca8efe642e380c93d5e2\",\"scriptHash\":\"30a8c9cc2fd9e9424dc4732f2ccdcf5bee863e5b77817090a1acefbb\"},\"blacklistSpendBootstrap\":{\"blacklistMintScriptHash\":\"30a8c9cc2fd9e9424dc4732f2ccdcf5bee863e5b77817090a1acefbb\",\"scriptHash\":\"97c007326cf3839c4820da1d8fa3c097abeab42d1f5f18044c0188d8\"}}";
        var blacklistBoostrap = OBJECT_MAPPER.readValue(blacklistBoostrapJson, BlacklistBootstrap.class);

        var substandardName = "freeze-and-seize";

        var adminUtxos = accountService.findAdaOnlyUtxo(adminAccount.baseAddress(), 10_000_000L);

        var protocolBootstrapParamsOpt = protocolBootstrapService.getProtocolBootstrapParamsByTxHash(DEFAULT_PROTOCOL);
        var protocolBootstrapParams = protocolBootstrapParamsOpt.get();

        var bootstrapTxHash = protocolBootstrapParams.txHash();

        var directorySpendContract = protocolScriptBuilderService.getParameterizedDirectorySpendScript(protocolBootstrapParams);

        var protocolParamsUtxoOpt = utxoService.findUtxo(bootstrapTxHash, 0);
        if (protocolParamsUtxoOpt.isEmpty()) {
            Assertions.fail("could not resolve protocol params");
        }

        var protocolParamsUtxo = protocolParamsUtxoOpt.get();

        var directorySpendContractAddress = AddressProvider.getEntAddress(directorySpendContract, network);
        log.info("directorySpendContractAddress: {}", directorySpendContractAddress.getAddress());

        var issuanceUtxoOpt = utxoService.findUtxo(bootstrapTxHash, 2);
        if (issuanceUtxoOpt.isEmpty()) {
            Assertions.fail("could not resolve issuance params");
        }
        var issuanceUtxo = issuanceUtxoOpt.get();
        log.info("issuanceUtxo: {}", issuanceUtxo);

        /// Getting Substandard Contracts and parameterize
        // Issuer to be used for minting/burning/sieze
        var issuerContractOpt = substandardService.getSubstandardValidator(substandardName, "example_transfer_logic.issuer_admin_contract.withdraw");
        var issuerContract = issuerContractOpt.get();

        var issuerAdminContractInitParams = ListPlutusData.of(serialize(adminAccount.getBaseAddress().getPaymentCredential().get()));

        var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                AikenScriptUtil.applyParamToScript(issuerAdminContractInitParams, issuerContract.scriptBytes()),
                PlutusVersion.v3
        );

        var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network);
        log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

        var transferContractOpt = substandardService.getSubstandardValidator(substandardName, "example_transfer_logic.transfer.withdraw");
        var transferContract = transferContractOpt.get();

        var transferContractInitParams = ListPlutusData.of(serialize(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash())),
                BytesPlutusData.of(HexUtil.decodeHexString(blacklistBoostrap.blacklistMintBootstrap().scriptHash()))
        );

        var substandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                AikenScriptUtil.applyParamToScript(transferContractInitParams, transferContract.scriptBytes()),
                PlutusVersion.v3
        );

        var issuanceContract = protocolScriptBuilderService.getParameterizedIssuanceMintScript(protocolBootstrapParams, substandardIssueContract);
        final var progTokenPolicyId = issuanceContract.getPolicyId();

        var registryAddress = AddressProvider.getEntAddress(directorySpendContract, network);

        var registryEntries = utxoService.findUtxos(registryAddress.getAddress());

        var registryEntryOpt = registryEntries.stream()
                .filter(addressUtxoEntity -> registryNodeParser.parse(addressUtxoEntity.getInlineDatum())
                        .map(registryNode -> registryNode.key().equals(progTokenPolicyId))
                        .orElse(false)
                )
                .findAny();

        if (registryEntryOpt.isPresent()) {
            Assertions.fail("registry node already present");
        }

        var nodeToReplaceOpt = registryEntries.stream()
                .filter(utxo -> {
                    var registryDatumOpt = registryNodeParser.parse(utxo.getInlineDatum());

                    if (registryDatumOpt.isEmpty()) {
                        log.warn("could not parse registry datum for: {}", utxo.getInlineDatum());
                        return false;
                    }

                    var registryDatum = registryDatumOpt.get();

                    var after = registryDatum.key().compareTo(progTokenPolicyId) < 0;
                    var before = progTokenPolicyId.compareTo(registryDatum.next()) < 0;
                    log.info("after:{}, before: {}", after, before);
                    return after && before;

                })
                .findAny();

        if (nodeToReplaceOpt.isEmpty()) {
            Assertions.fail("could not find node to replace");
        }

        var directoryUtxo = nodeToReplaceOpt.get();
        log.info("directoryUtxo: {}", directoryUtxo);
        var existingRegistryNodeDatumOpt = registryNodeParser.parse(directoryUtxo.getInlineDatum());

        if (existingRegistryNodeDatumOpt.isEmpty()) {
            Assertions.fail("could not parse current registry node");
        }

        var existingRegistryNodeDatum = existingRegistryNodeDatumOpt.get();

        // Directory MINT - NFT, address, datum and value
        var directoryMintContract = protocolScriptBuilderService.getParameterizedDirectoryMintScript(protocolBootstrapParams);
        var directoryMintPolicyId = directoryMintContract.getPolicyId();

        var directoryMintRedeemer = ConstrPlutusData.of(1,
                BytesPlutusData.of(issuanceContract.getScriptHash()),
                BytesPlutusData.of(substandardIssueContract.getScriptHash())
        );

        var directoryMintNft = Asset.builder()
                .name("0x" + issuanceContract.getPolicyId())
                .value(ONE)
                .build();

        Optional<Amount> registrySpentNftOpt = directoryUtxo.getAmount()
                .stream()
                .filter(amount -> amount.getQuantity().equals(ONE) && directoryMintPolicyId.equals(AssetType.fromUnit(amount.getUnit()).policyId()))
                .findAny();

        if (registrySpentNftOpt.isEmpty()) {
            Assertions.fail("could not find amount for directory mint");
        }

        var registrySpentNft = AssetType.fromUnit(registrySpentNftOpt.get().getUnit());

        var directorySpendNft = Asset.builder()
                .name("0x" + registrySpentNft.assetName())
                .value(ONE)
                .build();

        var directorySpendDatum = existingRegistryNodeDatum.toBuilder()
                .next(HexUtil.encodeHexString(issuanceContract.getScriptHash()))
                .build();
        log.info("directorySpendDatum: {}", directorySpendDatum);

        var thirdPartyScriptHash = "";

        var directoryMintDatum = new RegistryNode(HexUtil.encodeHexString(issuanceContract.getScriptHash()),
                existingRegistryNodeDatum.next(),
                HexUtil.encodeHexString(substandardTransferContract.getScriptHash()),
                thirdPartyScriptHash,
                "");
        log.info("directoryMintDatum: {}", directoryMintDatum);

        Value directoryMintValue = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(directoryMintPolicyId)
                                .assets(List.of(directoryMintNft))
                                .build()
                ))
                .build();
        log.info("directoryMintValue: {}", directoryMintValue);

        Value directorySpendValue = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(directoryMintPolicyId)
                                .assets(List.of(directorySpendNft))
                                .build()
                ))
                .build();
        log.info("directorySpendValue: {}", directorySpendValue);


        var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));

        // Programmable Token Mint
        var programmableToken = Asset.builder()
                .name("0x" + HexUtil.encodeHexString("tUSDT".getBytes()))
                .value(ONE)
                .build();

        Value programmableTokenValue = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(issuanceContract.getPolicyId())
                                .assets(List.of(programmableToken))
                                .build()
                ))
                .build();

        var payee = adminAccount.getBaseAddress().getAddress();
        log.info("payee: {}", payee);

        var payeeAddress = new Address(payee);

        var targetAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                payeeAddress.getDelegationCredential().get(),
                network);

//        var registerAddressTx = new Tx()
//                .from(adminAccount.baseAddress())
//                .registerStakeAddress(substandardIssueAddress.getAddress())
//                .withChangeAddress(adminAccount.baseAddress());
//
//        quickTxBuilder.compose(registerAddressTx)
//                .feePayer(adminAccount.baseAddress())
//                .withSigner(SignerProviders.signerFrom(adminAccount))
//                .completeAndWait();
//
//        Thread.sleep(20000L);


        var tx = new ScriptTx()
                .collectFrom(adminUtxos)
                .collectFrom(directoryUtxo, ConstrPlutusData.of(0))
                // No redeemer for substandard
                .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                // Mint Token
                .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                // Redeemer is DirectoryInit (constr(0))
                .mintAsset(directoryMintContract, directoryMintNft, directoryMintRedeemer)
                .payToContract(targetAddress.getAddress(), ValueUtil.toAmountList(programmableTokenValue), ConstrPlutusData.of(0))
                // Directory Params
                .payToContract(directorySpendContractAddress.getAddress(), ValueUtil.toAmountList(directorySpendValue), directorySpendDatum.toPlutusData())
                // Directory Params
                .payToContract(directorySpendContractAddress.getAddress(), ValueUtil.toAmountList(directoryMintValue), directoryMintDatum.toPlutusData())
                .readFrom(TransactionInput.builder()
                                .transactionId(protocolParamsUtxo.getTxHash())
                                .index(protocolParamsUtxo.getOutputIndex())
                                .build(),
                        TransactionInput.builder()
                                .transactionId(issuanceUtxo.getTxHash())
                                .index(issuanceUtxo.getOutputIndex())
                                .build())
                .attachSpendingValidator(directorySpendContract)
                .attachRewardValidator(substandardIssueContract)
                .withChangeAddress(adminAccount.baseAddress());

        var transaction = quickTxBuilder.compose(tx)
                .withRequiredSigners(adminAccount.getBaseAddress())
                .withSigner(SignerProviders.signerFrom(adminAccount))
//                    .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                .feePayer(adminAccount.baseAddress())
                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                .preBalanceTx((txBuilderContext, transaction1) -> {
                    var outputs = transaction1.getBody().getOutputs();
                    if (outputs.getFirst().getAddress().equals(adminAccount.baseAddress())) {
                        log.info("found dummy input, moving it...");
                        var first = outputs.removeFirst();
                        outputs.addLast(first);
                    }
                    try {
                        log.info("pre tx: {}", OBJECT_MAPPER.writeValueAsString(transaction1));
                    } catch (JsonProcessingException e) {
                        throw new RuntimeException(e);
                    }
                })
                .postBalanceTx((txBuilderContext, transaction1) -> {
                    try {
                        log.info("post tx: {}", OBJECT_MAPPER.writeValueAsString(transaction1));
                    } catch (JsonProcessingException e) {
                        throw new RuntimeException(e);
                    }
                })
                .buildAndSign();

        log.info("tx: {}", transaction.serializeToHex());
        log.info("tx: {}", OBJECT_MAPPER.writeValueAsString(transaction));

        if (!dryRun) {
            var txHash = bfBackendService.getTransactionService().submitTransaction(transaction.serialize());
            log.info("txHash: {}", txHash);
        }


    }


}
