package org.cardanofoundation.cip113.substandards.freezeandsieze;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.TransactionEvaluator;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.model.Utxo;
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
import com.bloxbean.cardano.client.quicktx.Tx;
import com.bloxbean.cardano.client.supplier.ogmios.OgmiosTransactionEvaluator;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.easy1staking.cardano.comparator.TransactionInputComparator;
import com.easy1staking.cardano.comparator.UtxoComparator;
import com.easy1staking.cardano.model.AssetType;
import com.easy1staking.util.Pair;
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
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

import static org.cardanofoundation.cip113.util.PlutusSerializationHelper.serialize;

@Slf4j
public class PreviewTransferTest extends AbstractPreviewTest {

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

        var blacklistBoostrapJson = "{\"blacklistMintBootstrap\":{\"txInput\":{\"txHash\":\"7172a517d98d65dc9fdaf270cb52383de54840fbf44721d8ae82ae8d8175a1a5\",\"outputIndex\":1},\"adminPubKeyHash\":\"32e7e00eae28502a2aa271cf4202b1b01b94ca8efe642e380c93d5e2\",\"scriptHash\":\"30a8c9cc2fd9e9424dc4732f2ccdcf5bee863e5b77817090a1acefbb\"},\"blacklistSpendBootstrap\":{\"blacklistMintScriptHash\":\"30a8c9cc2fd9e9424dc4732f2ccdcf5bee863e5b77817090a1acefbb\",\"scriptHash\":\"97c007326cf3839c4820da1d8fa3c097abeab42d1f5f18044c0188d8\"}}";
        var blacklistBoostrap = OBJECT_MAPPER.readValue(blacklistBoostrapJson, BlacklistBootstrap.class);
        log.info("blacklistBoostrap: {}", blacklistBoostrap);

        var substandardName = "freeze-and-seize";

        var adminUtxos = accountService.findAdaOnlyUtxo(adminAccount.baseAddress(), 10_000_000L);

        var protocolBootstrapParamsOpt = protocolBootstrapService.getProtocolBootstrapParamsByTxHash(DEFAULT_PROTOCOL);
        var protocolBootstrapParams = protocolBootstrapParamsOpt.get();
        log.info("protocolBootstrapParams: {}", protocolBootstrapParams);

        var bootstrapTxHash = protocolBootstrapParams.txHash();

        var progToken = AssetType.fromUnit("034457562a217be56f2e4e8dd22d798f1d81a524196fab0e11cbc8327455534454");
        log.info("policy id: {}, asset name: {}", progToken.policyId(), progToken.unsafeHumanAssetName());

        var amountToTransfer = BigInteger.valueOf(10_000_000L);

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

        var protocolParamsUtxoOpt = utxoProvider.findUtxo(bootstrapTxHash, 0);

        if (protocolParamsUtxoOpt.isEmpty()) {
            Assertions.fail("could not resolve protocol params");
        }

        var protocolParamsUtxo = protocolParamsUtxoOpt.get();
        log.info("protocolParamsUtxo: {}", protocolParamsUtxo);

        var senderAddress = adminAccount.getBaseAddress();
        var senderProgrammableTokenAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                senderAddress.getDelegationCredential().get(),
                network);

        var recipientAddress = new Address(aliceAccount.baseAddress());
        var recipientProgrammableTokenAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                recipientAddress.getDelegationCredential().get(),
                network);

        var senderProgTokensUtxos = utxoProvider.findUtxos(senderProgrammableTokenAddress.getAddress());


//        // Programmable Logic Global parameterization
        var programmableLogicGlobal = protocolScriptBuilderService.getParameterizedProgrammableLogicGlobalScript(protocolBootstrapParams);
        var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobal, network);
        log.info("programmableLogicGlobalAddress policy: {}", programmableLogicGlobalAddress.getAddress());
        log.info("protocolBootstrapParams.programmableLogicGlobalPrams().scriptHash(): {}", protocolBootstrapParams.programmableLogicGlobalPrams().scriptHash());
//
////            // Programmable Logic Base parameterization
        var programmableLogicBase = protocolScriptBuilderService.getParameterizedProgrammableLogicBaseScript(protocolBootstrapParams);
        log.info("programmableLogicBase policy: {}", programmableLogicBase.getPolicyId());

        // FIXME:
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

        var registerAddressTx = new Tx()
                .from(adminAccount.baseAddress())
                .registerStakeAddress(substandardTransferAddress.getAddress())
                .withChangeAddress(adminAccount.baseAddress());

        quickTxBuilder.compose(registerAddressTx)
                .feePayer(adminAccount.baseAddress())
                .withSigner(SignerProviders.signerFrom(adminAccount))
                .completeAndWait();

        Thread.sleep(20000L);

        var valueToSend = Value.from(progToken.policyId(), "0x" + progToken.assetName(), amountToTransfer);

        var inputUtxos = senderProgTokensUtxos.stream()
                .reduce(new Pair<List<Utxo>, Value>(List.of(), Value.builder().build()),
                        (listValuePair, utxo) -> {
                            if (listValuePair.second().subtract(valueToSend).isPositive()) {
                                return listValuePair;
                            } else {
                                if (utxo.toValue().amountOf(progToken.policyId(), "0x" + progToken.assetName()).compareTo(BigInteger.ONE) > 0) {
                                    var newUtxos = Stream.concat(Stream.of(utxo), listValuePair.first().stream());
                                    return new Pair<>(newUtxos.toList(), listValuePair.second().add(utxo.toValue()));
                                } else {
                                    return listValuePair;
                                }
                            }
                        }, (listValuePair, listValuePair2) -> {
                            var newUtxos = Stream.concat(listValuePair.first().stream(), listValuePair.first().stream());
                            return new Pair<>(newUtxos.toList(), listValuePair.second().add(listValuePair2.second()));
                        })
                .first();

        var senderProgTokensValue = inputUtxos.stream()
                .map(Utxo::toValue)
                .filter(value -> value.amountOf(progToken.policyId(), "0x" + progToken.assetName()).compareTo(BigInteger.ZERO) > 0)
                .reduce(Value::add)
                .orElse(Value.builder().build());

        var returningValue = senderProgTokensValue.subtract(valueToSend);

        var tokenAsset2 = Asset.builder()
                .name("0x" + progToken.assetName())
                .value(amountToTransfer)
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

        var progTokenAmount = senderProgTokensValue.amountOf(progToken.policyId(), "0x" + progToken.assetName());
        log.info("progTokenAmount: {}", progTokenAmount);

        if (progTokenAmount.compareTo(amountToTransfer) < 0) {
            Assertions.fail("Not enough funds");
        }

        var blacklistSpendScriptHash = blacklistBoostrap.blacklistSpendBootstrap().scriptHash();
        var blacklistAddress = AddressProvider.getEntAddress(Credential.fromScript(blacklistSpendScriptHash), network);
        var blacklistUtxos = utxoProvider.findUtxos(blacklistAddress.getAddress());

        var sortedInputUtxos = Stream.concat(adminUtxos.stream(), inputUtxos.stream())
                .sorted(new UtxoComparator())
                .toList();

        var proofs = new ArrayList<Pair<Utxo, Utxo>>();
        var progTokenBaseScriptHash = protocolBootstrapParams.programmableLogicBaseParams().scriptHash();
        for (Utxo utxo : sortedInputUtxos) {
            var address = new Address(utxo.getAddress());
            var addressPkh = address.getPaymentCredentialHash().map(HexUtil::encodeHexString).get();
            if (progTokenBaseScriptHash.equals(addressPkh)) {
                var stakingPkh = address.getDelegationCredentialHash().map(HexUtil::encodeHexString).get();
                var relevantBlacklistNodeOpt = blacklistUtxos.stream()
                        .filter(blackListUtxo -> blacklistNodeParser
                                .parse(blackListUtxo.getInlineDatum())
                                .map(blacklistNode -> blacklistNode.key().compareTo(stakingPkh) < 0 && blacklistNode.next().compareTo(stakingPkh) > 0)
                                .orElse(false))
                        .findAny();
                if (relevantBlacklistNodeOpt.isEmpty()) {
                    Assertions.fail("could not resolve blacklist exemption");
                }
                proofs.add(new Pair<>(utxo, relevantBlacklistNodeOpt.get()));
            }
        }

        var sortedReferenceInputs = Stream.concat(proofs.stream().map(Pair::second).map(utxo -> TransactionInput.builder()
                                .transactionId(utxo.getTxHash())
                                .index(utxo.getOutputIndex())
                                .build()),
                        Stream.of(TransactionInput.builder()
                                .transactionId(protocolParamsUtxo.getTxHash())
                                .index(protocolParamsUtxo.getOutputIndex())
                                .build(), TransactionInput.builder()
                                .transactionId(progTokenRegistry.getTxHash())
                                .index(progTokenRegistry.getOutputIndex())
                                .build())
                )
                .sorted(new TransactionInputComparator())
                .toList();

        var proofList = proofs.stream().map(pair -> {
            log.info("first: {}, second: {}", pair.first(), pair.second());
            var index = sortedReferenceInputs.indexOf(TransactionInput.builder().transactionId(pair.second().getTxHash()).index(pair.second().getOutputIndex()).build());
            log.info("adding index: {} as a blacklist non-belonging proof", index);
            return ConstrPlutusData.of(0, BigIntPlutusData.of(index));
        }).toList();
        var freezeAndSeizeRedeemer = ListPlutusData.of();
        proofList.forEach(freezeAndSeizeRedeemer::add);

        var registryIndex = sortedReferenceInputs.indexOf(TransactionInput.builder().transactionId(progTokenRegistry.getTxHash()).index(progTokenRegistry.getOutputIndex()).build());

        var programmableGlobalRedeemer = ConstrPlutusData.of(0,
                // only one prop and it's a list
                ListPlutusData.of(ConstrPlutusData.of(0, BigIntPlutusData.of(registryIndex)))
        );

        var tx = new ScriptTx()
                .collectFrom(adminUtxos);

        inputUtxos.forEach(utxo -> {
            tx.collectFrom(utxo, ConstrPlutusData.of(0));
        });

//        // must be first Provide proofs
        tx.withdraw(substandardTransferAddress.getAddress(), BigInteger.ZERO, freezeAndSeizeRedeemer)
                .withdraw(programmableLogicGlobalAddress.getAddress(), BigInteger.ZERO, programmableGlobalRedeemer)
                .payToContract(senderProgrammableTokenAddress.getAddress(), ValueUtil.toAmountList(returningValue), ConstrPlutusData.of(0))
                .payToContract(recipientProgrammableTokenAddress.getAddress(), ValueUtil.toAmountList(tokenValue2), ConstrPlutusData.of(0));

        sortedReferenceInputs.forEach(tx::readFrom);

        tx.attachRewardValidator(programmableLogicGlobal) // global
                .attachRewardValidator(parameterisedSubstandardTransferContract)
                .attachSpendingValidator(programmableLogicBase) // base
                .withChangeAddress(senderAddress.getAddress());


        var transaction = quickTxBuilder.compose(tx)
                .withRequiredSigners(senderAddress.getDelegationCredentialHash().get())
                .feePayer(senderAddress.getAddress())
                .mergeOutputs(false)
                .withTxEvaluator(ogmiosTxEvaluator())
//                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                .withSigner(SignerProviders.signerFrom(adminAccount))
                .withSigner(SignerProviders.stakeKeySignerFrom(adminAccount))
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
