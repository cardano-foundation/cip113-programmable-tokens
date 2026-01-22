package org.cardanofoundation.cip113.service.substandard;

import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.model.Utxo;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BigIntPlutusData;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.model.UtxoId;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.repository.UtxoRepository;
import com.easy1staking.cardano.model.AssetType;
import com.easy1staking.cardano.util.UtxoUtil;
import com.easy1staking.util.Pair;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.TransactionContext.RegistrationResult;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.model.onchain.RegistryNode;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.repository.ProgrammableTokenRegistryRepository;
import org.cardanofoundation.cip113.service.ProtocolScriptBuilderService;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.cardanofoundation.cip113.service.substandard.capabilities.BasicOperations;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import java.math.BigInteger;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

import static java.math.BigInteger.ONE;

/**
 * Handler for the "dummy" programmable token substandard.
 * This is a simple reference implementation with basic issue and transfer validators.
 *
 * <p>Capabilities: {@link BasicOperations} only (register, mint, burn, transfer)</p>
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class DummySubstandardHandler implements SubstandardHandler, BasicOperations<DummyRegisterRequest> {

    private static final String SUBSTANDARD_ID = "dummy";

    private final ObjectMapper objectMapper;

    private final AppConfig.Network network;

    private final UtxoRepository utxoRepository;

    private final RegistryNodeParser registryNodeParser;

    private final SubstandardService substandardService;

    private final ProtocolScriptBuilderService protocolScriptBuilderService;

    private final QuickTxBuilder quickTxBuilder;

    private final ProgrammableTokenRegistryRepository programmableTokenRegistryRepository;

    @Override
    public String getSubstandardId() {
        return SUBSTANDARD_ID;
    }

    @Override
    public TransactionContext<RegistrationResult> buildRegistrationTransaction(DummyRegisterRequest registerTokenRequest,
                                                                               ProtocolBootstrapParams protocolBootstrapParams) {

        try {

            var directorySpendContract = protocolScriptBuilderService.getParameterizedDirectorySpendScript(protocolBootstrapParams);

            var bootstrapTxHash = protocolBootstrapParams.txHash();

            var protocolParamsUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(bootstrapTxHash)
                    .outputIndex(0)
                    .build());

            if (protocolParamsUtxoOpt.isEmpty()) {
                return TransactionContext.typedError("could not resolve protocol params");
            }

            var protocolParamsUtxo = protocolParamsUtxoOpt.get();

            var directorySpendContractAddress = AddressProvider.getEntAddress(directorySpendContract, network.getCardanoNetwork());
            log.info("directorySpendContractAddress: {}", directorySpendContractAddress.getAddress());

            var directoryMintContract = protocolScriptBuilderService.getParameterizedDirectoryMintScript(protocolBootstrapParams);
            var directoryMintPolicyId = directoryMintContract.getPolicyId();

            var issuanceUtxoOpt = utxoRepository.findById(UtxoId.builder().txHash(bootstrapTxHash).outputIndex(2).build());
            if (issuanceUtxoOpt.isEmpty()) {
                return TransactionContext.typedError("could not resolve issuance params");
            }
            var issuanceUtxo = issuanceUtxoOpt.get();
            log.info("issuanceUtxo: {}", issuanceUtxo);

            var rigistrarUtxosOpt = utxoRepository.findUnspentByOwnerAddr(registerTokenRequest.getFeePayerAddress(), Pageable.unpaged());
            if (rigistrarUtxosOpt.isEmpty()) {
                return TransactionContext.typedError("issuer wallet is empty");
            }
            var registrarUtxos = rigistrarUtxosOpt.get().stream().map(UtxoUtil::toUtxo).toList();

            // Handler knows its own contract names internally
            var substandardIssuanceContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "issue.issue.withdraw");
            var substandardTransferContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "transfer.transfer.withdraw");

            var thirdPartyScriptHash = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "third_party.third_party.withdraw")
                    .map(SubstandardValidator::scriptHash)
                    .orElse("");

            if (substandardIssuanceContractOpt.isEmpty() || substandardTransferContractOpt.isEmpty()) {
                log.warn("substandard issuance or transfer contract are empty");
                return TransactionContext.typedError("substandard issuance or transfer contract are empty");
            }

            var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardIssuanceContractOpt.get().scriptBytes(), PlutusVersion.v3);
            log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

            var substandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardTransferContractOpt.get().scriptBytes(), PlutusVersion.v3);

            var issuanceContract = protocolScriptBuilderService.getParameterizedIssuanceMintScript(protocolBootstrapParams, substandardIssueContract);
            final var progTokenPolicyId = issuanceContract.getPolicyId();
            log.info("issuanceContract: {}", progTokenPolicyId);

            var registryEntries = utxoRepository.findUnspentByOwnerPaymentCredential(directorySpendContract.getPolicyId(), Pageable.unpaged());

            var registryEntryOpt = registryEntries.stream()
                    .flatMap(Collection::stream)
                    .filter(addressUtxoEntity -> registryNodeParser.parse(addressUtxoEntity.getInlineDatum())
                            .map(registryNode -> registryNode.key().equals(progTokenPolicyId))
                            .orElse(false)
                    )
                    .findAny();

            if (registryEntryOpt.isEmpty()) {

                var nodeToReplaceOpt = registryEntries.stream()
                        .flatMap(Collection::stream)
                        .filter(addressUtxoEntity -> {
                            var registryDatumOpt = registryNodeParser.parse(addressUtxoEntity.getInlineDatum());

                            if (registryDatumOpt.isEmpty()) {
                                log.warn("could not parse registry datum for: {}", addressUtxoEntity.getInlineDatum());
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
                    return TransactionContext.typedError("could not find node to replace");
                }

                var directoryUtxo = UtxoUtil.toUtxo(nodeToReplaceOpt.get());
                log.info("directoryUtxo: {}", directoryUtxo);
                var existingRegistryNodeDatumOpt = registryNodeParser.parse(directoryUtxo.getInlineDatum());

                if (existingRegistryNodeDatumOpt.isEmpty()) {
                    return TransactionContext.typedError("could not parse current registry node");
                }

                var existingRegistryNodeDatum = existingRegistryNodeDatumOpt.get();

                // Directory MINT - NFT, address, datum and value
                var directoryMintRedeemer = ConstrPlutusData.of(1,
                        BytesPlutusData.of(issuanceContract.getScriptHash()),
                        BytesPlutusData.of(substandardIssueContract.getScriptHash())
                );

                var directoryMintNft = Asset.builder()
                        .name("0x" + issuanceContract.getPolicyId())
                        .value(BigInteger.ONE)
                        .build();

                Optional<Amount> registrySpentNftOpt = directoryUtxo.getAmount()
                        .stream()
                        .filter(amount -> amount.getQuantity().equals(ONE) && directoryMintPolicyId.equals(AssetType.fromUnit(amount.getUnit()).policyId()))
                        .findAny();

                if (registrySpentNftOpt.isEmpty()) {
                    return TransactionContext.typedError("could not find amount for directory mint");
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
                                        .policyId(directoryMintContract.getPolicyId())
                                        .assets(List.of(directoryMintNft))
                                        .build()
                        ))
                        .build();
                log.info("directoryMintValue: {}", directoryMintValue);

                Value directorySpendValue = Value.builder()
                        .coin(Amount.ada(1).getQuantity())
                        .multiAssets(List.of(
                                MultiAsset.builder()
                                        .policyId(directoryMintContract.getPolicyId())
                                        .assets(List.of(directorySpendNft))
                                        .build()
                        ))
                        .build();
                log.info("directorySpendValue: {}", directorySpendValue);


                var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));

                // Programmable Token Mint
                var programmableToken = Asset.builder()
                        .name("0x" + registerTokenRequest.getAssetName())
                        .value(new BigInteger(registerTokenRequest.getQuantity()))
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

                var payee = registerTokenRequest.getRecipientAddress() == null || registerTokenRequest.getRecipientAddress().isBlank() ? registerTokenRequest.getFeePayerAddress() : registerTokenRequest.getRecipientAddress();
                log.info("payee: {}", payee);

                var payeeAddress = new Address(payee);

                var targetAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                        payeeAddress.getDelegationCredential().get(),
                        network.getCardanoNetwork());


                var tx = new ScriptTx()
                        .collectFrom(registrarUtxos)
                        .collectFrom(directoryUtxo, ConstrPlutusData.of(0))
                        .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, BigIntPlutusData.of(100))
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
                        .withChangeAddress(registerTokenRequest.getFeePayerAddress());

                var transaction = quickTxBuilder.compose(tx)
//                    .withSigner(SignerProviders.signerFrom(adminAccount))
//                    .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                        .feePayer(registerTokenRequest.getFeePayerAddress())
                        .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                        .preBalanceTx((txBuilderContext, transaction1) -> {
                            var outputs = transaction1.getBody().getOutputs();
                            if (outputs.getFirst().getAddress().equals(registerTokenRequest.getFeePayerAddress())) {
                                log.info("found dummy input, moving it...");
                                var first = outputs.removeFirst();
                                outputs.addLast(first);
                            }
                            try {
                                log.info("pre tx: {}", objectMapper.writeValueAsString(transaction1));
                            } catch (JsonProcessingException e) {
                                throw new RuntimeException(e);
                            }
                        })
                        .postBalanceTx((txBuilderContext, transaction1) -> {
                            try {
                                log.info("post tx: {}", objectMapper.writeValueAsString(transaction1));
                            } catch (JsonProcessingException e) {
                                throw new RuntimeException(e);
                            }
                        })
                        .build();

                log.info("tx: {}", transaction.serializeToHex());
                log.info("tx: {}", objectMapper.writeValueAsString(transaction));

                // Save to unified programmable token registry (policyId -> substandardId binding)
                programmableTokenRegistryRepository.save(ProgrammableTokenRegistryEntity.builder()
                        .policyId(progTokenPolicyId)
                        .substandardId(SUBSTANDARD_ID)
                        .build());

                return TransactionContext.ok(transaction.serializeToHex(), new RegistrationResult(progTokenPolicyId));
            } else {

                return TransactionContext.typedError(String.format("Token policy %s already registered", progTokenPolicyId));
            }


        } catch (Exception e) {
            return TransactionContext.typedError(e.getMessage());
        }

    }

    @Override
    public TransactionContext<Void> buildMintTransaction(MintTokenRequest mintTokenRequest,
                                                         ProtocolBootstrapParams protocolBootstrapParams) {


        try {

            var feePayerUtxosOpt = utxoRepository.findUnspentByOwnerAddr(mintTokenRequest.feePayerAddress(), Pageable.unpaged());
            if (feePayerUtxosOpt.isEmpty()) {
                return TransactionContext.error("fee payer wallet is empty");
            }
            var feePayerUtxos = feePayerUtxosOpt.get().stream().map(UtxoUtil::toUtxo).toList();

            // Handler knows its own contract names internally
            var substandardIssuanceContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "issue.issue.withdraw");

            var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardIssuanceContractOpt.get().scriptBytes(), PlutusVersion.v3);
            log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

            var issuanceContract = protocolScriptBuilderService.getParameterizedIssuanceMintScript(protocolBootstrapParams, substandardIssueContract);
            log.info("issuanceContract: {}", issuanceContract.getPolicyId());

            var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));

            // Programmable Token Mint
            var programmableToken = Asset.builder()
                    .name("0x" + mintTokenRequest.assetName())
                    .value(new BigInteger(mintTokenRequest.quantity()))
                    .build();

            Value progammableTokenValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(
                            MultiAsset.builder()
                                    .policyId(issuanceContract.getPolicyId())
                                    .assets(List.of(programmableToken))
                                    .build()
                    ))
                    .build();

            var recipient = Optional.ofNullable(mintTokenRequest.recipientAddress())
                    .orElse(mintTokenRequest.feePayerAddress());

            var recipientAddress = new Address(recipient);

            var targetAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                    recipientAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            var tx = new ScriptTx()
                    .collectFrom(feePayerUtxos)
                    .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, BigIntPlutusData.of(100))
                    // Redeemer is DirectoryInit (constr(0))
                    .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                    .payToContract(targetAddress.getAddress(), ValueUtil.toAmountList(progammableTokenValue), ConstrPlutusData.of(0))
                    .attachRewardValidator(substandardIssueContract)
                    .withChangeAddress(mintTokenRequest.feePayerAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .feePayer(mintTokenRequest.feePayerAddress())
                    .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                    .preBalanceTx((txBuilderContext, transaction1) -> {
                        var outputs = transaction1.getBody().getOutputs();
                        if (outputs.getFirst().getAddress().equals(mintTokenRequest.feePayerAddress())) {
                            log.info("found dummy input, moving it...");
                            var first = outputs.removeFirst();
                            outputs.addLast(first);
                        }
                        try {
                            log.info("pre tx: {}", objectMapper.writeValueAsString(transaction1));
                        } catch (JsonProcessingException e) {
                            throw new RuntimeException(e);
                        }
                    })
                    .postBalanceTx((txBuilderContext, transaction1) -> {
                        try {
                            log.info("post tx: {}", objectMapper.writeValueAsString(transaction1));
                        } catch (JsonProcessingException e) {
                            throw new RuntimeException(e);
                        }
                    })
                    .build();

            log.info("tx: {}", transaction.serializeToHex());
            log.info("tx: {}", objectMapper.writeValueAsString(transaction));

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.warn("error", e);
            return TransactionContext.error(e.getMessage());
        }

    }

    @Override
    public TransactionContext<Void> buildTransferTransaction(TransferTokenRequest transferTokenRequest,
                                                             ProtocolBootstrapParams protocolBootstrapParams) {

        try {

            var bootstrapTxHash = protocolBootstrapParams.txHash();

            var progToken = AssetType.fromUnit(transferTokenRequest.unit());
            log.info("policy id: {}, asset name: {}", progToken.policyId(), progToken.unsafeHumanAssetName());

            // Directory SPEND parameterization
            var directorySpendContract = protocolScriptBuilderService.getParameterizedDirectorySpendScript(protocolBootstrapParams);
            log.info("directorySpendContract: {}", HexUtil.encodeHexString(directorySpendContract.getScriptHash()));

            var registryEntries = utxoRepository.findUnspentByOwnerPaymentCredential(directorySpendContract.getPolicyId(), Pageable.unpaged());

            var progTokenRegistryOpt = registryEntries.stream()
                    .flatMap(Collection::stream)
                    .filter(addressUtxoEntity -> {
                        var registryDatumOpt = registryNodeParser.parse(addressUtxoEntity.getInlineDatum());
                        return registryDatumOpt.map(registryDatum -> registryDatum.key().equals(progToken.policyId())).orElse(false);
                    })
                    .findAny()
                    .map(UtxoUtil::toUtxo);

            if (progTokenRegistryOpt.isEmpty()) {
                return TransactionContext.error("could not find registry entry for token");
            }

            var progTokenRegistry = progTokenRegistryOpt.get();

            var protocolParamsUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(bootstrapTxHash)
                    .outputIndex(0)
                    .build());

            if (protocolParamsUtxoOpt.isEmpty()) {
                return TransactionContext.error("could not resolve protocol params");
            }

            var protocolParamsUtxo = protocolParamsUtxoOpt.get();
            log.info("protocolParamsUtxo: {}", protocolParamsUtxo);

            var senderAddress = new Address(transferTokenRequest.senderAddress());
            var senderProgrammableTokenAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                    senderAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            var recipientAddress = new Address(transferTokenRequest.recipientAddress());
            var recipientProgrammableTokenAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                    recipientAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            var senderProgTokenAddressesOpt = utxoRepository.findUnspentByOwnerAddr(senderProgrammableTokenAddress.getAddress(), Pageable.unpaged());
            var senderProgTokensUtxos = senderProgTokenAddressesOpt.stream()
                    .flatMap(Collection::stream)
                    .map(UtxoUtil::toUtxo)
                    .toList();

            var senderProgTokensValue = senderProgTokensUtxos.stream()
                    .map(Utxo::toValue)
                    .filter(value -> value.amountOf(progToken.policyId(), "0x" + progToken.assetName()).compareTo(BigInteger.ZERO) > 0)
                    .reduce(Value::add)
                    .orElse(Value.builder().build());

            var progTokenAmount = senderProgTokensValue.amountOf(progToken.policyId(), "0x" + progToken.assetName());

            if (progTokenAmount.compareTo(new BigInteger(transferTokenRequest.quantity())) < 0) {
                return TransactionContext.error("Not enough funds");
            }

            var senderUtxos = utxoRepository.findUnspentByOwnerAddr(transferTokenRequest.senderAddress(), Pageable.unpaged())
                    .stream()
                    .flatMap(Collection::stream)
                    .map(UtxoUtil::toUtxo)
                    .toList();

            // Programmable Logic Global parameterization
            var programmableLogicGlobal = protocolScriptBuilderService.getParameterizedProgrammableLogicGlobalScript(protocolBootstrapParams);
            var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobal, network.getCardanoNetwork());
            log.info("programmableLogicGlobalAddress policy: {}", programmableLogicGlobalAddress.getAddress());
            log.info("protocolBootstrapParams.programmableLogicGlobalPrams().scriptHash(): {}", protocolBootstrapParams.programmableLogicGlobalPrams().scriptHash());

//            // Programmable Logic Base parameterization
            var programmableLogicBase = protocolScriptBuilderService.getParameterizedProgrammableLogicBaseScript(protocolBootstrapParams);
            log.info("programmableLogicBase policy: {}", programmableLogicBase.getPolicyId());

            // Programmable Token Mint
            var valueToSend = Value.from(progToken.policyId(), "0x" + progToken.assetName(), new BigInteger(transferTokenRequest.quantity()));
            var returningValue = senderProgTokensValue.subtract(valueToSend);

            var tokenAsset2 = Asset.builder()
                    .name("0x" + progToken.assetName())
                    .value(new BigInteger(transferTokenRequest.quantity()))
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


            var programmableGlobalRedeemer = ConstrPlutusData.of(0,
                    // only one prop and it's a list
                    ListPlutusData.of(ConstrPlutusData.of(0, BigIntPlutusData.of(1)))
            );

            // FIXME:
            var substandardTransferContractOpt = substandardService.getSubstandardValidator("dummy", "transfer.transfer.withdraw");
            if (substandardTransferContractOpt.isEmpty()) {
                log.warn("could not resolve transfer contract");
                return TransactionContext.error("could not resolve transfer contract");
            }
            var substandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardTransferContractOpt.get().scriptBytes(), PlutusVersion.v3);
            var substandardTransferAddress = AddressProvider.getRewardAddress(substandardTransferContract, network.getCardanoNetwork());
            log.info("substandardTransferAddress: {}", substandardTransferAddress.getAddress());

            var inputUtxos = senderProgTokensUtxos.stream()
                    .reduce(new Pair<List<Utxo>, Value>(List.of(), Value.builder().build()),
                            (listValuePair, utxo) -> {
                                if (listValuePair.second().subtract(valueToSend).isPositive()) {
                                    return listValuePair;
                                } else {
                                    if (utxo.toValue().amountOf(progToken.policyId(), "0x" + progToken.assetName()).compareTo(BigInteger.ZERO) > 0) {
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

            var tx = new ScriptTx()
                    .collectFrom(senderUtxos);

            inputUtxos.forEach(utxo -> {
                tx.collectFrom(utxo, ConstrPlutusData.of(0));
            });

            // must be first Provide proofs
            tx.withdraw(substandardTransferAddress.getAddress(), BigInteger.ZERO, BigIntPlutusData.of(200))
                    .withdraw(programmableLogicGlobalAddress.getAddress(), BigInteger.ZERO, programmableGlobalRedeemer)
                    .payToContract(senderProgrammableTokenAddress.getAddress(), ValueUtil.toAmountList(returningValue), ConstrPlutusData.of(0))
                    .payToContract(recipientProgrammableTokenAddress.getAddress(), ValueUtil.toAmountList(tokenValue2), ConstrPlutusData.of(0))
                    .readFrom(TransactionInput.builder()
                            .transactionId(protocolParamsUtxo.getTxHash())
                            .index(protocolParamsUtxo.getOutputIndex())
                            .build(), TransactionInput.builder()
                            .transactionId(progTokenRegistry.getTxHash())
                            .index(progTokenRegistry.getOutputIndex())
                            .build())
                    .attachRewardValidator(programmableLogicGlobal) // global
                    .attachRewardValidator(substandardTransferContract)
                    .attachSpendingValidator(programmableLogicBase) // base
                    .withChangeAddress(senderAddress.getAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(senderAddress.getDelegationCredentialHash().get())
                    .feePayer(senderAddress.getAddress())
                    .mergeOutputs(false)
                    .postBalanceTx((txBuilderContext, transaction1) -> {
                        var fees = transaction1.getBody().getFee();
                        var newFees = fees.add(BigInteger.valueOf(200_000L));
                        transaction1.getBody().setFee(newFees);

                        transaction1.getBody()
                                .getOutputs()
                                .stream()
                                .filter(transactionOutput -> senderAddress.getAddress().equals(transactionOutput.getAddress()) && transactionOutput.getValue().getCoin().compareTo(BigInteger.valueOf(2_000_000)) > 0)
                                .findAny()
                                .ifPresent(transactionOutput -> {
                                    transactionOutput.setValue(transactionOutput.getValue().substractCoin(BigInteger.valueOf(200_000L)));
                                });

                        transaction1.getBody().setTotalCollateral(transaction1.getBody().getTotalCollateral().add(BigInteger.valueOf(500_000L)));
                        var collateralReturn = transaction1.getBody().getCollateralReturn();
                        collateralReturn.setValue(collateralReturn.getValue().substractCoin(BigInteger.valueOf(500_000L)));
                    })
                    .build();


            log.info("tx: {}", transaction.serializeToHex());
            log.info("tx: {}", objectMapper.writeValueAsString(transaction));

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            return TransactionContext.error(e.getMessage());
        }

    }

}
