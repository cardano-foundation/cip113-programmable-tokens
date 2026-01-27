package org.cardanofoundation.cip113.substandards.freezeandsieze;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.aiken.AikenTransactionEvaluator;
import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.TransactionEvaluator;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.common.model.Network;
import com.bloxbean.cardano.client.common.model.Networks;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BigIntPlutusData;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.supplier.ogmios.OgmiosTransactionEvaluator;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.easy1staking.cardano.comparator.TransactionInputComparator;
import com.easy1staking.cardano.comparator.UtxoComparator;
import com.easy1staking.cardano.model.AssetType;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.AbstractPreviewTest;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistBootstrap;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistNodeParser;
import org.cardanofoundation.cip113.service.*;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.util.stream.Stream;

import static org.cardanofoundation.cip113.util.PlutusSerializationHelper.serialize;

@Slf4j
public class PreviewSeizeTest extends AbstractPreviewTest implements PreviewFreezeAndSieze {

    private static final String DEFAULT_PROTOCOL = "114adc8ee212b5ded1f895ab53c7741e5521feff735d05aeef2a92dcf05c9ae2";

    private final Network network = Networks.preview();

    private final UtxoProvider utxoProvider = new UtxoProvider(bfBackendService, null);

    private final AccountService accountService = new AccountService(utxoProvider);

    private final LinkedListService linkedListService = new LinkedListService(utxoProvider);

    private final ProtocolBootstrapService protocolBootstrapService = new ProtocolBootstrapService(OBJECT_MAPPER, new AppConfig.Network("preview"));

    private final ProtocolScriptBuilderService protocolScriptBuilderService = new ProtocolScriptBuilderService(protocolBootstrapService);

    private SubstandardService substandardService;

    private final RegistryNodeParser registryNodeParser = new RegistryNodeParser(OBJECT_MAPPER);

    private final BlacklistNodeParser blacklistNodeParser = new BlacklistNodeParser(OBJECT_MAPPER);

    @BeforeEach
    public void init() {
        substandardService = new SubstandardService(OBJECT_MAPPER);
        substandardService.init();

        protocolBootstrapService.init();
    }

    @Test
    public void test() throws Exception {

        var dryRun = false;

        var blacklistBoostrap = OBJECT_MAPPER.readValue(BL_BOOTSTRAP_V3, BlacklistBootstrap.class);
        log.info("blacklistBoostrap: {}", blacklistBoostrap);

        var substandardName = "freeze-and-seize";

        var issuerAdminAccount = bobAccount;

        var adminUtxos = accountService.findAdaOnlyUtxo(issuerAdminAccount.baseAddress(), 10_000_000L);

        var protocolBootstrapParamsOpt = protocolBootstrapService.getProtocolBootstrapParamsByTxHash(DEFAULT_PROTOCOL);
        var protocolBootstrapParams = protocolBootstrapParamsOpt.get();
        log.info("protocolBootstrapParams: {}", protocolBootstrapParams);

        var bootstrapTxHash = protocolBootstrapParams.txHash();

        var progToken = AssetType.fromUnit("76658c4afd597ba7524f85bf32ac59d9e58856593a2e8399326f853a7455534454");
        log.info("policy id: {}, asset name: {}", progToken.policyId(), progToken.unsafeHumanAssetName());

        // Directory SPEND parameterization
        var registrySpendContract = protocolScriptBuilderService.getParameterizedDirectorySpendScript(protocolBootstrapParams);
        log.info("registrySpendContract: {}", HexUtil.encodeHexString(registrySpendContract.getScriptHash()));

        var registryAddress = AddressProvider.getEntAddress(registrySpendContract, network);
        log.info("registryAddress: {}", registryAddress.getAddress());

        var registryEntries = utxoProvider.findUtxos(registryAddress.getAddress());

        var progTokenRegistryOpt = registryEntries.stream()
                .filter(utxo -> {
                    var registryDatumOpt = registryNodeParser.parse(utxo.getInlineDatum());
                    return registryDatumOpt.map(registryDatum -> registryDatum.key().equals(progToken.policyId())).orElse(false);
                })
                .findAny();

        if (progTokenRegistryOpt.isEmpty()) {
            Assertions.fail("could not find registry entry for token");
        }

        var progTokenRegistry = progTokenRegistryOpt.get();
        log.info("progTokenRegistry: {}", progTokenRegistry);

        var registryOpt = registryNodeParser.parse(progTokenRegistry.getInlineDatum());
        if (registryOpt.isEmpty()) {
            Assertions.fail("could not find registry entry for token");
        }

        var registry = registryOpt.get();
        log.info("registry: {}", registry);

        var protocolParamsUtxoOpt = utxoProvider.findUtxo(bootstrapTxHash, 0);

        if (protocolParamsUtxoOpt.isEmpty()) {
            Assertions.fail("could not resolve protocol params");
        }

        var protocolParamsUtxo = protocolParamsUtxoOpt.get();
        log.info("protocolParamsUtxo: {}", protocolParamsUtxo);

        var seizedAddress = aliceAccount.getBaseAddress();
        var seizedProgrammableTokenAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                seizedAddress.getDelegationCredential().get(),
                network);

        var recipientAddress = new Address(bobAccount.baseAddress());
        var recipientProgrammableTokenAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                recipientAddress.getDelegationCredential().get(),
                network);

        var seizedProgTokensUtxos = utxoProvider.findUtxos(seizedProgrammableTokenAddress.getAddress());


//        // Programmable Logic Global parameterization
        var programmableLogicGlobal = protocolScriptBuilderService.getParameterizedProgrammableLogicGlobalScript(protocolBootstrapParams);
        var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobal, network);
        log.info("programmableLogicGlobalAddress policy: {}", programmableLogicGlobalAddress.getAddress());
        log.info("protocolBootstrapParams.programmableLogicGlobalPrams().scriptHash(): {}", protocolBootstrapParams.programmableLogicGlobalPrams().scriptHash());
//
////            // Programmable Logic Base parameterization
        var programmableLogicBase = protocolScriptBuilderService.getParameterizedProgrammableLogicBaseScript(protocolBootstrapParams);
        log.info("programmableLogicBase policy: {}", programmableLogicBase.getPolicyId());

        // Issuer to be used for minting/burning/sieze
        var issuerContractOpt = substandardService.getSubstandardValidator(substandardName, "example_transfer_logic.issuer_admin_contract.withdraw");
        var issuerContract = issuerContractOpt.get();

        var issuerAdminContractInitParams = ListPlutusData.of(serialize(issuerAdminAccount.getBaseAddress().getPaymentCredential().get()));

        var substandardIssueAdminContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                AikenScriptUtil.applyParamToScript(issuerAdminContractInitParams, issuerContract.scriptBytes()),
                PlutusVersion.v3
        );
        log.info("substandardIssueAdminContract: {}", substandardIssueAdminContract.getPolicyId());

        var substandardIssueAdminAddress = AddressProvider.getRewardAddress(substandardIssueAdminContract, network);

        var substandardTransferContractOpt = substandardService.getSubstandardValidator(substandardName, "example_transfer_logic.transfer.withdraw");
        if (substandardTransferContractOpt.isEmpty()) {
            log.warn("could not resolve transfer contract");
            Assertions.fail("could not resolve transfer contract");
        }

        var substandardTransferContract1 = substandardTransferContractOpt.get();

        var transferContractInitParams = ListPlutusData.of(serialize(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash())),
                BytesPlutusData.of(HexUtil.decodeHexString(blacklistBoostrap.blacklistMintBootstrap().scriptHash()))
        );

        var parameterisedSubstandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                AikenScriptUtil.applyParamToScript(transferContractInitParams, substandardTransferContract1.scriptBytes()),
                PlutusVersion.v3
        );

        var substandardTransferAddress = AddressProvider.getRewardAddress(parameterisedSubstandardTransferContract, network);

        var inputUtxoToSeizeOpt = seizedProgTokensUtxos.stream()
                .filter(utxo -> utxo.toValue().amountOf(progToken.policyId(), "0x" + progToken.assetName()).compareTo(BigInteger.ZERO) > 0)
                .findAny();

        if (inputUtxoToSeizeOpt.isEmpty()) {
            Assertions.fail("could not resolve prog token");
        }

        var inputUtxoToSeize = inputUtxoToSeizeOpt.get();
        log.info("inputUtxoToSeize: {}", inputUtxoToSeize);

        var valueToSeize = inputUtxoToSeize.toValue().amountOf(progToken.policyId(), "0x" + progToken.assetName());
        log.info("amount to seize: {}", valueToSeize);

        var tokenAssetToSeize = Value.from(progToken.policyId(), "0x" + progToken.assetName(), valueToSeize);

        var blacklistSpendScriptHash = blacklistBoostrap.blacklistSpendBootstrap().scriptHash();
        var blacklistAddress = AddressProvider.getEntAddress(Credential.fromScript(blacklistSpendScriptHash), network);
        var blacklistUtxos = utxoProvider.findUtxos(blacklistAddress.getAddress());

        var sortedInputs = Stream.concat(adminUtxos.stream(), Stream.of(inputUtxoToSeize))
                .sorted(new UtxoComparator())
                .toList();

        var seizeInputIndex = sortedInputs.indexOf(inputUtxoToSeize);
        log.info("seizeInputIndex: {}", seizeInputIndex);

        var registryRefInput = TransactionInput.builder()
                .transactionId(progTokenRegistry.getTxHash())
                .index(progTokenRegistry.getOutputIndex())
                .build();
        var sortedReferenceInputs = Stream.of(TransactionInput.builder()
                        .transactionId(protocolParamsUtxo.getTxHash())
                        .index(protocolParamsUtxo.getOutputIndex())
                        .build(), registryRefInput)
                .sorted(new TransactionInputComparator())
                .toList();

        var registryRefInputInex = sortedReferenceInputs.indexOf(registryRefInput);
        log.info("registryRefInputInex: {}", registryRefInputInex);

        var programmableGlobalRedeemer = ConstrPlutusData.of(1,
                BigIntPlutusData.of(registryRefInputInex),
                ListPlutusData.of(BigIntPlutusData.of(seizeInputIndex)),
                BigIntPlutusData.of(2), // Index of the first output
                BigIntPlutusData.of(1)
        );

        var tx = new ScriptTx()
                .collectFrom(adminUtxos)
                .collectFrom(inputUtxoToSeize, ConstrPlutusData.of(0))
                .withdraw(substandardIssueAdminAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                .withdraw(programmableLogicGlobalAddress.getAddress(), BigInteger.ZERO, programmableGlobalRedeemer)
                .payToContract(recipientProgrammableTokenAddress.getAddress(), ValueUtil.toAmountList(tokenAssetToSeize), ConstrPlutusData.of(0))
                .payToContract(inputUtxoToSeize.getAddress(), ValueUtil.toAmountList(inputUtxoToSeize.toValue().subtract(tokenAssetToSeize)), ConstrPlutusData.of(0))
                .readFrom(sortedReferenceInputs.toArray(new TransactionInput[0]))
                .attachRewardValidator(programmableLogicGlobal) // global
                .attachRewardValidator(substandardIssueAdminContract)
                .attachSpendingValidator(programmableLogicBase) // base
                .withChangeAddress(issuerAdminAccount.baseAddress());


        var transaction = quickTxBuilder.compose(tx)

                .feePayer(issuerAdminAccount.baseAddress())
                .mergeOutputs(false)
//                .withTxEvaluator(ogmiosTxEvaluator())
                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                .withRequiredSigners(issuerAdminAccount.getBaseAddress())
                .withSigner(SignerProviders.signerFrom(issuerAdminAccount))
                .buildAndSign();


        log.info("tx: {}", transaction.serializeToHex());
        log.info("tx: {}", OBJECT_MAPPER.writeValueAsString(transaction));

        if (!dryRun) {
            var result = bfBackendService.getTransactionService().submitTransaction(transaction.serialize());
            log.info("result: {}", result);
        }

    }

    public TransactionEvaluator ogmiosTxEvaluator() {

        return new OgmiosTransactionEvaluator("http://panic-station:31357");

    }


}
