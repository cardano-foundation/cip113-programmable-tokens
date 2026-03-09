package org.cardanofoundation.cip113.service.substandard;

import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.address.CredentialType;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.model.Utxo;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.client.plutus.spec.*;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.bloxbean.cardano.client.quicktx.Tx;
import com.bloxbean.cardano.client.transaction.spec.*;
import com.bloxbean.cardano.client.transaction.util.TransactionUtil;
import com.bloxbean.cardano.client.util.HexUtil;
import com.bloxbean.cardano.yaci.core.model.certs.CertificateType;
import com.easy1staking.cardano.comparator.TransactionInputComparator;
import com.easy1staking.cardano.comparator.UtxoComparator;
import com.easy1staking.cardano.model.AssetType;
import com.easy1staking.util.Pair;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.entity.*;
import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.TransactionContext.RegistrationResult;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.model.onchain.RegistryNode;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.repository.*;
import org.cardanofoundation.cip113.service.*;
import org.cardanofoundation.cip113.service.substandard.capabilities.BasicOperations;
import org.cardanofoundation.cip113.service.substandard.capabilities.SubstandardGovernance;
import org.cardanofoundation.cip113.service.substandard.capabilities.WhitelistManageable;
import org.cardanofoundation.cip113.service.substandard.context.WhitelistMultiAdminContext;
import org.springframework.context.annotation.Scope;
import org.springframework.stereotype.Component;

import java.math.BigInteger;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import static java.math.BigInteger.ONE;

/**
 * Handler for the "whitelist-send-receive-multiadmin" programmable token substandard.
 *
 * <p>This handler supports regulated security tokens with KYC compliance features:</p>
 * <ul>
 *   <li><b>BasicOperations</b> - Register, mint, burn, transfer programmable tokens</li>
 *   <li><b>WhitelistManageable</b> - Add/remove addresses from whitelist</li>
 *   <li><b>SubstandardGovernance</b> - Add/remove managers from manager list</li>
 * </ul>
 *
 * <p>Three-tier authority hierarchy:</p>
 * <ul>
 *   <li><b>Super-admin</b> (ISSUER_ADMIN) - manages managers via manager_signatures + manager_list</li>
 *   <li><b>Manager</b> (WHITELIST_MANAGER) - manages user whitelist via manager_auth + whitelist_mint</li>
 *   <li><b>User</b> - must be whitelisted to send OR receive tokens</li>
 * </ul>
 */
@Component
@Scope("prototype")
@RequiredArgsConstructor
@Slf4j
public class WhitelistSendReceiveMultiAdminHandler implements SubstandardHandler,
        BasicOperations<WhitelistMultiAdminRegisterRequest>,
        WhitelistManageable,
        SubstandardGovernance {

    private static final String SUBSTANDARD_ID = "whitelist-send-receive-multiadmin";

    private final ObjectMapper objectMapper;
    private final AppConfig.Network network;
    private final RegistryNodeParser registryNodeParser;
    private final AccountService accountService;
    private final SubstandardService substandardService;
    private final ProtocolScriptBuilderService protocolScriptBuilderService;
    private final WhitelistMultiAdminScriptBuilderService wlScriptBuilder;
    private final LinkedListService linkedListService;
    private final QuickTxBuilder quickTxBuilder;
    private final HybridUtxoSupplier hybridUtxoSupplier;
    private final WhitelistTokenRegistrationRepository whitelistTokenRegistrationRepository;
    private final ManagerSignaturesInitRepository managerSignaturesInitRepository;
    private final ManagerListInitRepository managerListInitRepository;
    private final WhitelistInitRepository whitelistInitRepository;
    private final ProgrammableTokenRegistryRepository programmableTokenRegistryRepository;
    private final CustomStakeRegistrationRepository stakeRegistrationRepository;
    private final UtxoProvider utxoProvider;
    private final BFBackendService bfBackendService;

    @Setter
    private WhitelistMultiAdminContext context;

    @Override
    public String getSubstandardId() {
        return SUBSTANDARD_ID;
    }

    // ========== BasicOperations Implementation ==========

    @Override
    public TransactionContext<List<String>> buildPreRegistrationTransaction(
            WhitelistMultiAdminRegisterRequest request,
            ProtocolBootstrapParams protocolParams) {
        // Whitelist substandard handles stake registration during init/registration
        return TransactionContext.typedError("Use combined registration flow instead");
    }

    @Override
    public TransactionContext<RegistrationResult> buildRegistrationTransaction(
            WhitelistMultiAdminRegisterRequest request,
            ProtocolBootstrapParams protocolParams) {

        try {
            var adminPkh = Credential.fromKey(request.getAdminPubKeyHash());

            // Resolve init entities from context or request
            var whitelistPolicyId = request.getWhitelistPolicyId() != null
                    ? request.getWhitelistPolicyId()
                    : (context != null ? context.getWhitelistPolicyId() : null);

            if (whitelistPolicyId == null) {
                return TransactionContext.typedError("whitelistPolicyId is required. Run init first.");
            }

            var managerListPolicyId = request.getManagerListPolicyId() != null
                    ? request.getManagerListPolicyId()
                    : (context != null ? context.getManagerListPolicyId() : null);

            var managerSigsPolicyId = request.getManagerSigsPolicyId() != null
                    ? request.getManagerSigsPolicyId()
                    : (context != null ? context.getManagerSigsPolicyId() : null);

            List<Utxo> feePayerUtxos;
            if (request.getChainingTransactionCborHex() != null) {
                var chainingTxBytes = HexUtil.decodeHexString(request.getChainingTransactionCborHex());
                var chainingTxHash = TransactionUtil.getTxHash(chainingTxBytes);
                var chainingTx = Transaction.deserialize(chainingTxBytes);
                var chainingTxOutputs = chainingTx.getBody().getOutputs();
                Utxo inputUtxo = null;
                for (int i = 0; i < chainingTxOutputs.size(); i++) {
                    var output = chainingTxOutputs.get(i);
                    if (output.getAddress().equals(request.getFeePayerAddress()) &&
                            output.getValue().getCoin().compareTo(BigInteger.valueOf(10_000_000L)) > 0) {
                        inputUtxo = Utxo.builder()
                                .address(output.getAddress())
                                .txHash(chainingTxHash)
                                .outputIndex(i)
                                .amount(ValueUtil.toAmountList(output.getValue()))
                                .build();
                    }
                }
                if (inputUtxo == null) {
                    return TransactionContext.typedError("could not chain tx");
                }
                feePayerUtxos = List.of(inputUtxo);
                feePayerUtxos.forEach(hybridUtxoSupplier::add);
            } else {
                feePayerUtxos = accountService.findAdaOnlyUtxo(request.getFeePayerAddress(), 10_000_000L);
            }

            var bootstrapTxHash = protocolParams.txHash();
            var directorySpendContract = protocolScriptBuilderService.getParameterizedDirectorySpendScript(protocolParams);

            var protocolParamsUtxoOpt = utxoProvider.findUtxo(bootstrapTxHash, 0);
            if (protocolParamsUtxoOpt.isEmpty()) {
                return TransactionContext.typedError("could not resolve protocol params");
            }
            var protocolParamsUtxo = protocolParamsUtxoOpt.get();

            var directorySpendContractAddress = AddressProvider.getEntAddress(directorySpendContract, network.getCardanoNetwork());

            var issuanceUtxoOpt = utxoProvider.findUtxo(bootstrapTxHash, 2);
            if (issuanceUtxoOpt.isEmpty()) {
                return TransactionContext.typedError("could not resolve issuance params");
            }
            var issuanceUtxo = issuanceUtxoOpt.get();

            // Build issuer admin contract (same pattern as FES — uses admin PKH)
            var substandardIssueContract = buildIssuerAdminScript(adminPkh);
            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());

            // Build transfer contract
            var substandardTransferContract = wlScriptBuilder.buildTransferScript(
                    protocolParams.programmableLogicBaseParams().scriptHash(),
                    whitelistPolicyId
            );
            var substandardTransferAddress = AddressProvider.getRewardAddress(substandardTransferContract, network.getCardanoNetwork());

            var issuanceContract = protocolScriptBuilderService.getParameterizedIssuanceMintScript(protocolParams, substandardIssueContract);
            final var progTokenPolicyId = issuanceContract.getPolicyId();

            var registryAddress = AddressProvider.getEntAddress(directorySpendContract, network.getCardanoNetwork());
            var registryEntries = utxoProvider.findUtxos(registryAddress.getAddress());

            var nodeAlreadyPresent = linkedListService.nodeAlreadyPresent(progTokenPolicyId, registryEntries,
                    utxo -> registryNodeParser.parse(utxo.getInlineDatum()).map(RegistryNode::key));

            if (nodeAlreadyPresent) {
                return TransactionContext.typedError("registry node already present");
            }

            var nodeToReplaceOpt = linkedListService.findNodeToReplace(progTokenPolicyId, registryEntries,
                    utxo -> registryNodeParser.parse(utxo.getInlineDatum())
                            .map(node -> new LinkedListNode(node.key(), node.next())));

            if (nodeToReplaceOpt.isEmpty()) {
                return TransactionContext.typedError("could not find node to replace");
            }

            var directoryUtxo = nodeToReplaceOpt.get();
            var existingRegistryNodeDatumOpt = registryNodeParser.parse(directoryUtxo.getInlineDatum());
            if (existingRegistryNodeDatumOpt.isEmpty()) {
                return TransactionContext.typedError("could not parse current registry node");
            }
            var existingRegistryNodeDatum = existingRegistryNodeDatumOpt.get();

            // Directory MINT
            var directoryMintContract = protocolScriptBuilderService.getParameterizedDirectoryMintScript(protocolParams);
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

            var directoryMintDatum = new RegistryNode(
                    HexUtil.encodeHexString(issuanceContract.getScriptHash()),
                    existingRegistryNodeDatum.next(),
                    HexUtil.encodeHexString(substandardTransferContract.getScriptHash()),
                    HexUtil.encodeHexString(substandardIssueContract.getScriptHash()),
                    ""
            );

            Value directoryMintValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(MultiAsset.builder()
                            .policyId(directoryMintPolicyId)
                            .assets(List.of(directoryMintNft))
                            .build()))
                    .build();

            Value directorySpendValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(MultiAsset.builder()
                            .policyId(directoryMintPolicyId)
                            .assets(List.of(directorySpendNft))
                            .build()))
                    .build();

            var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));

            var programmableToken = Asset.builder()
                    .name("0x" + request.getAssetName())
                    .value(new BigInteger(request.getQuantity()))
                    .build();

            Value programmableTokenValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(MultiAsset.builder()
                            .policyId(issuanceContract.getPolicyId())
                            .assets(List.of(programmableToken))
                            .build()))
                    .build();

            var payeeAddress = new Address(request.getRecipientAddress());
            var targetAddress = AddressProvider.getBaseAddress(
                    Credential.fromScript(protocolParams.programmableLogicBaseParams().scriptHash()),
                    payeeAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            var tx = new Tx()
                    .collectFrom(feePayerUtxos)
                    .collectFrom(directoryUtxo, ConstrPlutusData.of(0))
                    .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                    .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                    .mintAsset(directoryMintContract, directoryMintNft, directoryMintRedeemer)
                    .payToContract(targetAddress.getAddress(), ValueUtil.toAmountList(programmableTokenValue), ConstrPlutusData.of(0))
                    .payToContract(directorySpendContractAddress.getAddress(), ValueUtil.toAmountList(directorySpendValue), directorySpendDatum.toPlutusData())
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
                    .withChangeAddress(request.getFeePayerAddress());

            var firstUtxo = feePayerUtxos.getFirst();
            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(adminPkh.getBytes())
                    .feePayer(request.getFeePayerAddress())
                    .mergeOutputs(false)
                    .withCollateralInputs(TransactionInput.builder()
                            .transactionId(firstUtxo.getTxHash())
                            .index(firstUtxo.getOutputIndex())
                            .build())
                    .preBalanceTx((txBuilderContext, transaction1) -> {
                        var outputs = transaction1.getBody().getOutputs();
                        if (outputs.getFirst().getAddress().equals(request.getFeePayerAddress())) {
                            var first = outputs.removeFirst();
                            outputs.addLast(first);
                        }
                    })
                    .ignoreScriptCostEvaluationError(false)
                    .build();

            log.info("registration tx: {}", transaction.serializeToHex());

            // Persist registration data
            var managerSigsInitOpt = managerSignaturesInitRepository.findByManagerSigsPolicyId(managerSigsPolicyId);
            var managerListInitOpt = managerListInitRepository.findByManagerListPolicyId(managerListPolicyId);
            var whitelistInitOpt = whitelistInitRepository.findByWhitelistPolicyId(whitelistPolicyId);

            if (managerSigsInitOpt.isEmpty() || managerListInitOpt.isEmpty() || whitelistInitOpt.isEmpty()) {
                return TransactionContext.typedError("init records not found — run init first");
            }

            whitelistTokenRegistrationRepository.save(WhitelistTokenRegistrationEntity.builder()
                    .programmableTokenPolicyId(progTokenPolicyId)
                    .issuerAdminPkh(HexUtil.encodeHexString(adminPkh.getBytes()))
                    .whitelistInit(whitelistInitOpt.get())
                    .managerListInit(managerListInitOpt.get())
                    .managerSigsInit(managerSigsInitOpt.get())
                    .build());

            programmableTokenRegistryRepository.save(ProgrammableTokenRegistryEntity.builder()
                    .policyId(progTokenPolicyId)
                    .substandardId(SUBSTANDARD_ID)
                    .assetName(request.getAssetName())
                    .build());

            hybridUtxoSupplier.clear();

            return TransactionContext.ok(transaction.serializeToHex(), new RegistrationResult(progTokenPolicyId));

        } catch (Exception e) {
            log.error("error building registration tx", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    @Override
    public TransactionContext<Void> buildMintTransaction(
            MintTokenRequest request,
            ProtocolBootstrapParams protocolParams) {

        try {
            var adminUtxos = accountService.findAdaOnlyUtxo(request.feePayerAddress(), 10_000_000L);

            var issuanceUtxoOpt = utxoProvider.findUtxo(protocolParams.txHash(), 2);
            if (issuanceUtxoOpt.isEmpty()) {
                return TransactionContext.typedError("could not resolve issuance params");
            }
            var issuanceUtxo = issuanceUtxoOpt.get();

            var adminPkh = Credential.fromKey(context.getIssuerAdminPkh());
            var substandardIssueContract = buildIssuerAdminScript(adminPkh);
            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());

            var issuanceContract = protocolScriptBuilderService.getParameterizedIssuanceMintScript(protocolParams, substandardIssueContract);

            var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));

            var programmableToken = Asset.builder()
                    .name("0x" + request.assetName())
                    .value(new BigInteger(request.quantity()))
                    .build();

            Value programmableTokenValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(MultiAsset.builder()
                            .policyId(issuanceContract.getPolicyId())
                            .assets(List.of(programmableToken))
                            .build()))
                    .build();

            var payeeAddress = new Address(request.recipientAddress());
            var targetAddress = AddressProvider.getBaseAddress(
                    Credential.fromScript(protocolParams.programmableLogicBaseParams().scriptHash()),
                    payeeAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            var tx = new Tx()
                    .collectFrom(adminUtxos)
                    .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                    .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                    .payToContract(targetAddress.getAddress(), ValueUtil.toAmountList(programmableTokenValue), ConstrPlutusData.of(0))
                    .attachRewardValidator(substandardIssueContract)
                    .withChangeAddress(request.feePayerAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(adminPkh.getBytes())
                    .feePayer(request.feePayerAddress())
                    .mergeOutputs(false)
                    .preBalanceTx((txBuilderContext, transaction1) -> {
                        var outputs = transaction1.getBody().getOutputs();
                        if (outputs.getFirst().getAddress().equals(request.feePayerAddress())) {
                            var first = outputs.removeFirst();
                            outputs.addLast(first);
                        }
                    })
                    .build();

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.error("error building mint tx", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    @Override
    public TransactionContext<Void> buildBurnTransaction(BurnTokenRequest request, ProtocolBootstrapParams protocolParams) {
        try {
            var assetTypeToBurn = new AssetType(request.tokenPolicyId(), request.assetName());
            var adminUtxos = accountService.findAdaOnlyUtxo(request.feePayerAddress(), 10_000_000L);

            var utxoToBurnOpt = utxoProvider.findUtxo(request.utxoTxHash(), request.utxoOutputIndex());
            if (utxoToBurnOpt.isEmpty()) {
                return TransactionContext.error("utxo to burn could not be found");
            }
            var utxoToBurn = utxoToBurnOpt.get();

            var utxoTokenAmount = utxoToBurn.toValue().amountOf(assetTypeToBurn.policyId(), "0x" + assetTypeToBurn.assetName());

            var adminPkh = Credential.fromKey(context.getIssuerAdminPkh());
            var substandardIssueContract = buildIssuerAdminScript(adminPkh);
            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());

            var issuanceContract = protocolScriptBuilderService.getParameterizedIssuanceMintScript(protocolParams, substandardIssueContract);
            var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));

            var programmableToken = Asset.builder()
                    .name("0x" + assetTypeToBurn.assetName())
                    .value(utxoTokenAmount.abs().negate())
                    .build();

            var programmableLogicGlobal = protocolScriptBuilderService.getParameterizedProgrammableLogicGlobalScript(protocolParams);
            var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobal, network.getCardanoNetwork());

            var registrySpendContract = protocolScriptBuilderService.getParameterizedDirectorySpendScript(protocolParams);
            var registryAddress = AddressProvider.getEntAddress(registrySpendContract, network.getCardanoNetwork());
            var registryEntries = utxoProvider.findUtxos(registryAddress.getAddress());

            var progTokenRegistryOpt = registryEntries.stream()
                    .filter(utxo -> registryNodeParser.parse(utxo.getInlineDatum())
                            .map(registryDatum -> registryDatum.key().equals(assetTypeToBurn.policyId())).orElse(false))
                    .findAny();

            if (progTokenRegistryOpt.isEmpty()) {
                return TransactionContext.typedError("could not find registry entry for token");
            }
            var progTokenRegistry = progTokenRegistryOpt.get();

            var sortedInputUtxos = Stream.concat(adminUtxos.stream(), Stream.of(utxoToBurn))
                    .sorted(new UtxoComparator())
                    .toList();

            var protocolParamsUtxoOpt = utxoProvider.findUtxo(protocolParams.txHash(), 0);
            if (protocolParamsUtxoOpt.isEmpty()) {
                return TransactionContext.typedError("could not resolve protocol params");
            }
            var protocolParamsUtxo = protocolParamsUtxoOpt.get();

            var registryRefInput = TransactionInput.builder()
                    .transactionId(progTokenRegistry.getTxHash())
                    .index(progTokenRegistry.getOutputIndex())
                    .build();

            var sortedReferenceInputs = Stream.of(
                            TransactionInput.builder()
                                    .transactionId(protocolParamsUtxo.getTxHash())
                                    .index(protocolParamsUtxo.getOutputIndex())
                                    .build(),
                            registryRefInput)
                    .sorted(new TransactionInputComparator())
                    .toList();

            var registryRefInputIndex = sortedReferenceInputs.indexOf(registryRefInput);
            var burnInputIndex = sortedInputUtxos.indexOf(utxoToBurn);

            var programmableGlobalRedeemer = ConstrPlutusData.of(1,
                    BigIntPlutusData.of(registryRefInputIndex),
                    ListPlutusData.of(BigIntPlutusData.of(burnInputIndex)),
                    BigIntPlutusData.of(1),
                    BigIntPlutusData.of(1)
            );

            var programmableLogicBase = protocolScriptBuilderService.getParameterizedProgrammableLogicBaseScript(protocolParams);

            // Remove entire policy from UTxO value
            var utxoValue = utxoToBurn.toValue();
            var filteredMultiAssets = utxoValue.getMultiAssets() == null
                    ? List.<MultiAsset>of()
                    : utxoValue.getMultiAssets().stream()
                    .filter(ma -> !ma.getPolicyId().equals(assetTypeToBurn.policyId()))
                    .collect(Collectors.toList());
            var returningValue = Value.builder()
                    .coin(utxoValue.getCoin())
                    .multiAssets(filteredMultiAssets)
                    .build();

            var tx = new Tx()
                    .collectFrom(adminUtxos)
                    .collectFrom(utxoToBurn, ConstrPlutusData.of(0))
                    .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                    .withdraw(programmableLogicGlobalAddress.getAddress(), BigInteger.ZERO, programmableGlobalRedeemer)
                    .payToContract(utxoToBurn.getAddress(), ValueUtil.toAmountList(returningValue), ConstrPlutusData.of(0))
                    .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                    .readFrom(sortedReferenceInputs.toArray(new TransactionInput[0]))
                    .attachSpendingValidator(programmableLogicBase)
                    .attachRewardValidator(programmableLogicGlobal)
                    .attachRewardValidator(substandardIssueContract)
                    .withChangeAddress(request.feePayerAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(adminPkh.getBytes())
                    .feePayer(request.feePayerAddress())
                    .mergeOutputs(false)
                    .build();

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.error("error building burn tx", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    @Override
    public TransactionContext<Void> buildTransferTransaction(
            TransferTokenRequest request,
            ProtocolBootstrapParams protocolParams) {

        try {
            var senderAddress = new Address(request.senderAddress());
            var receiverAddress = new Address(request.recipientAddress());
            var whitelistPolicyId = context.getWhitelistPolicyId();

            var adminUtxos = accountService.findAdaOnlyUtxo(senderAddress.getAddress(), 10_000_000L);
            var progToken = AssetType.fromUnit(request.unit());
            var amountToTransfer = new BigInteger(request.quantity());

            // Build registry and protocol params
            var registrySpendContract = protocolScriptBuilderService.getParameterizedDirectorySpendScript(protocolParams);
            var registryAddress = AddressProvider.getEntAddress(registrySpendContract, network.getCardanoNetwork());
            var registryEntries = utxoProvider.findUtxos(registryAddress.getAddress());

            var progTokenRegistryOpt = registryEntries.stream()
                    .filter(utxo -> registryNodeParser.parse(utxo.getInlineDatum())
                            .map(registryDatum -> registryDatum.key().equals(progToken.policyId())).orElse(false))
                    .findAny();

            if (progTokenRegistryOpt.isEmpty()) {
                return TransactionContext.typedError("could not find registry entry for token");
            }
            var progTokenRegistry = progTokenRegistryOpt.get();

            var protocolParamsUtxoOpt = utxoProvider.findUtxo(protocolParams.txHash(), 0);
            if (protocolParamsUtxoOpt.isEmpty()) {
                return TransactionContext.typedError("could not resolve protocol params");
            }
            var protocolParamsUtxo = protocolParamsUtxoOpt.get();

            var senderProgrammableTokenAddress = AddressProvider.getBaseAddress(
                    Credential.fromScript(protocolParams.programmableLogicBaseParams().scriptHash()),
                    senderAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            var recipientProgrammableTokenAddress = AddressProvider.getBaseAddress(
                    Credential.fromScript(protocolParams.programmableLogicBaseParams().scriptHash()),
                    receiverAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            var senderProgTokensUtxos = utxoProvider.findUtxos(senderProgrammableTokenAddress.getAddress());

            var programmableLogicGlobal = protocolScriptBuilderService.getParameterizedProgrammableLogicGlobalScript(protocolParams);
            var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobal, network.getCardanoNetwork());
            var programmableLogicBase = protocolScriptBuilderService.getParameterizedProgrammableLogicBaseScript(protocolParams);

            var parameterisedTransferContract = wlScriptBuilder.buildTransferScript(
                    protocolParams.programmableLogicBaseParams().scriptHash(),
                    whitelistPolicyId
            );
            var substandardTransferAddress = AddressProvider.getRewardAddress(parameterisedTransferContract, network.getCardanoNetwork());

            var valueToSend = Value.from(progToken.policyId(), "0x" + progToken.assetName(), amountToTransfer);

            // Gather input UTxOs with enough tokens
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
                            }, (a, b) -> {
                                var combined = Stream.concat(a.first().stream(), b.first().stream()).toList();
                                return new Pair<>(combined, a.second().add(b.second()));
                            })
                    .first();

            var senderProgTokensValue = inputUtxos.stream()
                    .map(Utxo::toValue)
                    .filter(value -> value.amountOf(progToken.policyId(), "0x" + progToken.assetName()).compareTo(BigInteger.ZERO) > 0)
                    .reduce(Value::add)
                    .orElse(Value.builder().build());

            var progTokenAmount = senderProgTokensValue.amountOf(progToken.policyId(), "0x" + progToken.assetName());
            if (progTokenAmount.compareTo(amountToTransfer) < 0) {
                return TransactionContext.typedError("Not enough funds");
            }

            var returningValue = senderProgTokensValue.subtract(valueToSend);

            Value tokenValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(MultiAsset.builder()
                            .policyId(progToken.policyId())
                            .assets(List.of(Asset.builder()
                                    .name("0x" + progToken.assetName())
                                    .value(amountToTransfer)
                                    .build()))
                            .build()))
                    .build();

            // Build whitelist MEMBERSHIP proofs (unlike FES non-membership proofs)
            var whitelistSpendScript = wlScriptBuilder.buildWhitelistSpendScript(whitelistPolicyId);
            var whitelistAddress = AddressProvider.getEntAddress(whitelistSpendScript, network.getCardanoNetwork());
            var whitelistUtxos = utxoProvider.findUtxos(whitelistAddress.getAddress());

            var sortedInputUtxos = Stream.concat(adminUtxos.stream(), inputUtxos.stream())
                    .sorted(new UtxoComparator())
                    .toList();

            // Collect all unique credentials that need whitelist proofs (senders + receivers)
            var progTokenBaseScriptHash = protocolParams.programmableLogicBaseParams().scriptHash();
            var senderProofs = new ArrayList<Pair<Utxo, Utxo>>();
            for (Utxo utxo : sortedInputUtxos) {
                var address = new Address(utxo.getAddress());
                var addressPkh = address.getPaymentCredentialHash().map(HexUtil::encodeHexString).get();
                if (progTokenBaseScriptHash.equals(addressPkh)) {
                    var stakingPkh = address.getDelegationCredentialHash().map(HexUtil::encodeHexString).get();
                    // Membership proof: find node where key == credential
                    var relevantWhitelistNodeOpt = findWhitelistMembershipNode(whitelistUtxos, stakingPkh);
                    if (relevantWhitelistNodeOpt.isEmpty()) {
                        return TransactionContext.typedError("sender address not whitelisted: " + stakingPkh);
                    }
                    senderProofs.add(new Pair<>(utxo, relevantWhitelistNodeOpt.get()));
                }
            }

            // Receiver whitelist proof
            var receiverStakingPkh = receiverAddress.getDelegationCredentialHash()
                    .map(HexUtil::encodeHexString)
                    .orElseThrow(() -> new RuntimeException("receiver has no delegation credential"));
            var receiverWhitelistNodeOpt = findWhitelistMembershipNode(whitelistUtxos, receiverStakingPkh);
            if (receiverWhitelistNodeOpt.isEmpty()) {
                return TransactionContext.typedError("receiver address not whitelisted: " + receiverStakingPkh);
            }
            var receiverWhitelistNode = receiverWhitelistNodeOpt.get();

            // Build sorted reference inputs
            var allWhitelistNodeUtxos = Stream.concat(
                    senderProofs.stream().map(Pair::second),
                    Stream.of(receiverWhitelistNode)
            ).distinct().toList();

            var sortedReferenceInputs = Stream.concat(
                            allWhitelistNodeUtxos.stream().map(utxo -> TransactionInput.builder()
                                    .transactionId(utxo.getTxHash())
                                    .index(utxo.getOutputIndex())
                                    .build()),
                            Stream.of(
                                    TransactionInput.builder()
                                            .transactionId(protocolParamsUtxo.getTxHash())
                                            .index(protocolParamsUtxo.getOutputIndex())
                                            .build(),
                                    TransactionInput.builder()
                                            .transactionId(progTokenRegistry.getTxHash())
                                            .index(progTokenRegistry.getOutputIndex())
                                            .build())
                    )
                    .sorted(new TransactionInputComparator())
                    .toList();

            // Build sender proofs as MembershipProof { node_idx }
            var senderProofList = senderProofs.stream().map(pair -> {
                var index = sortedReferenceInputs.indexOf(TransactionInput.builder()
                        .transactionId(pair.second().getTxHash())
                        .index(pair.second().getOutputIndex())
                        .build());
                return ConstrPlutusData.of(0, BigIntPlutusData.of(index));
            }).toList();

            // Build receiver proofs
            var receiverProofIndex = sortedReferenceInputs.indexOf(TransactionInput.builder()
                    .transactionId(receiverWhitelistNode.getTxHash())
                    .index(receiverWhitelistNode.getOutputIndex())
                    .build());
            var receiverProofList = List.of(ConstrPlutusData.of(0, BigIntPlutusData.of(receiverProofIndex)));

            // TransferRedeemer { sender_proofs, receiver_proofs }
            var senderProofsPlutus = ListPlutusData.of();
            senderProofList.forEach(senderProofsPlutus::add);
            var receiverProofsPlutus = ListPlutusData.of();
            receiverProofList.forEach(receiverProofsPlutus::add);
            var transferRedeemer = ConstrPlutusData.of(0, senderProofsPlutus, receiverProofsPlutus);

            var registryIndex = sortedReferenceInputs.indexOf(TransactionInput.builder()
                    .transactionId(progTokenRegistry.getTxHash())
                    .index(progTokenRegistry.getOutputIndex())
                    .build());

            var programmableGlobalRedeemer = ConstrPlutusData.of(0,
                    ListPlutusData.of(ConstrPlutusData.of(0, BigIntPlutusData.of(registryIndex)))
            );

            var tx = new Tx()
                    .collectFrom(adminUtxos);

            inputUtxos.forEach(utxo -> tx.collectFrom(utxo, ConstrPlutusData.of(0)));

            tx.withdraw(substandardTransferAddress.getAddress(), BigInteger.ZERO, transferRedeemer)
                    .withdraw(programmableLogicGlobalAddress.getAddress(), BigInteger.ZERO, programmableGlobalRedeemer)
                    .payToContract(senderProgrammableTokenAddress.getAddress(), ValueUtil.toAmountList(returningValue), ConstrPlutusData.of(0))
                    .payToContract(recipientProgrammableTokenAddress.getAddress(), ValueUtil.toAmountList(tokenValue), ConstrPlutusData.of(0));

            sortedReferenceInputs.forEach(tx::readFrom);

            tx.attachRewardValidator(programmableLogicGlobal)
                    .attachRewardValidator(parameterisedTransferContract)
                    .attachSpendingValidator(programmableLogicBase)
                    .withChangeAddress(senderAddress.getAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(senderAddress.getDelegationCredentialHash().get())
                    .additionalSignersCount(1)
                    .feePayer(senderAddress.getAddress())
                    .mergeOutputs(false)
                    .build();

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.warn("error building transfer tx", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    // ========== WhitelistManageable Implementation ==========

    @Override
    public TransactionContext<WhitelistInitResult> buildWhitelistInitTransaction(
            WhitelistInitRequest request,
            ProtocolBootstrapParams protocolParams) {

        try {
            var adminAddress = new Address(request.adminAddress());
            var utilityUtxos = accountService.findAdaOnlyUtxo(request.adminAddress(), 10_000_000L);

            // Use first UTxO as seed for whitelist mint
            var bootstrapUtxo = utilityUtxos.getFirst();
            var bootstrapTxInput = TransactionInput.builder()
                    .transactionId(bootstrapUtxo.getTxHash())
                    .index(bootstrapUtxo.getOutputIndex())
                    .build();

            // Need manager_auth_hash from context
            var managerAuthHash = context != null ? context.getManagerAuthHash() : null;
            if (managerAuthHash == null) {
                return TransactionContext.typedError("managerAuthHash required from context");
            }

            var whitelistMintScript = wlScriptBuilder.buildWhitelistMintScript(bootstrapTxInput, managerAuthHash);
            var whitelistSpendScript = wlScriptBuilder.buildWhitelistSpendScript(whitelistMintScript.getPolicyId());
            var whitelistSpendAddress = AddressProvider.getEntAddress(whitelistSpendScript, network.getCardanoNetwork());

            // Init datum: head node with key="" and next="ff...ff"
            var initDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(""),
                    BytesPlutusData.of(HexUtil.decodeHexString("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
            );

            var whitelistNft = Asset.builder().name("0x").value(ONE).build();

            Value whitelistValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(MultiAsset.builder()
                            .policyId(whitelistMintScript.getPolicyId())
                            .assets(List.of(whitelistNft))
                            .build()))
                    .build();

            var whitelistRedeemer = ConstrPlutusData.of(0,
                    ListPlutusData.of(BytesPlutusData.of(adminAddress.getPaymentCredentialHash().get()))
            );

            var tx = new Tx()
                    .collectFrom(utilityUtxos)
                    .mintAsset(whitelistMintScript, whitelistNft, whitelistRedeemer)
                    .payToAddress(request.adminAddress(), Amount.ada(40L))
                    .payToContract(whitelistSpendAddress.getAddress(), ValueUtil.toAmountList(whitelistValue), initDatum)
                    .withChangeAddress(request.adminAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .feePayer(request.adminAddress())
                    .ignoreScriptCostEvaluationError(false)
                    .mergeOutputs(false)
                    .build();

            // Persist
            whitelistInitRepository.save(WhitelistInitEntity.builder()
                    .whitelistPolicyId(whitelistMintScript.getPolicyId())
                    .managerAuthHash(managerAuthHash)
                    .txHash(bootstrapUtxo.getTxHash())
                    .outputIndex(bootstrapUtxo.getOutputIndex())
                    .build());

            return TransactionContext.ok(transaction.serializeToHex(),
                    new WhitelistInitResult(whitelistMintScript.getPolicyId()));

        } catch (Exception e) {
            log.error("error building whitelist init tx", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    @Override
    public TransactionContext<Void> buildAddToWhitelistTransaction(
            AddToWhitelistRequest request,
            ProtocolBootstrapParams protocolParams) {

        try {
            var whitelistPolicyId = context.getWhitelistPolicyId();
            var managerAuthHash = context.getManagerAuthHash();

            var managerUtxos = accountService.findAdaOnlyUtxo(request.adminAddress(), 10_000_000L);

            var whitelistSpendScript = wlScriptBuilder.buildWhitelistSpendScript(whitelistPolicyId);
            var whitelistAddress = AddressProvider.getEntAddress(whitelistSpendScript, network.getCardanoNetwork());
            var whitelistUtxos = utxoProvider.findUtxos(whitelistAddress.getAddress());

            // Build manager_auth script and get its reward address
            var managerListPolicyId = context.getManagerListPolicyId();
            var managerAuthScript = wlScriptBuilder.buildManagerAuthScript(managerListPolicyId);
            var managerAuthAddress = AddressProvider.getRewardAddress(managerAuthScript, network.getCardanoNetwork());

            // Find the covering node (node.key < targetCredential < node.next)
            var targetCredential = request.targetCredential();
            var nodeToReplaceOpt = findCoveringNode(whitelistUtxos, targetCredential);
            if (nodeToReplaceOpt.isEmpty()) {
                return TransactionContext.typedError("could not find covering node for insertion");
            }
            var coveringNode = nodeToReplaceOpt.get();

            // Parse existing node datum
            var existingDatum = parseLinkedListDatum(coveringNode);
            if (existingDatum == null) {
                return TransactionContext.typedError("could not parse covering node datum");
            }

            // Build whitelist mint script from context
            var whitelistMintScript = wlScriptBuilder.buildWhitelistMintScript(
                    context.getWhitelistInitTxInput(), managerAuthHash);

            // New node: key=targetCredential, next=existingDatum.next
            var newNodeDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(HexUtil.decodeHexString(targetCredential)),
                    BytesPlutusData.of(HexUtil.decodeHexString(existingDatum.second()))
            );

            // Updated covering node: key=existingDatum.key, next=targetCredential
            var updatedCoveringDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(HexUtil.decodeHexString(existingDatum.first())),
                    BytesPlutusData.of(HexUtil.decodeHexString(targetCredential))
            );

            var newNodeNft = Asset.builder()
                    .name("0x" + targetCredential)
                    .value(ONE)
                    .build();

            Value newNodeValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(MultiAsset.builder()
                            .policyId(whitelistPolicyId)
                            .assets(List.of(newNodeNft))
                            .build()))
                    .build();

            // Reconstruct covering node value
            var coveringNodeValue = coveringNode.toValue();

            // Insert redeemer (constr 1 = Insert)
            var mintRedeemer = ConstrPlutusData.of(1,
                    BytesPlutusData.of(HexUtil.decodeHexString(targetCredential))
            );

            // Manager auth proof (ManagerAuthProof redeemer for manager_auth withdrawal)
            // Find manager's node in manager list to prove authorization
            var managerListSpendScript = wlScriptBuilder.buildManagerListSpendScript(managerListPolicyId);
            var managerListAddress = AddressProvider.getEntAddress(managerListSpendScript, network.getCardanoNetwork());
            var managerListUtxos = utxoProvider.findUtxos(managerListAddress.getAddress());

            var managerAddress = new Address(request.adminAddress());
            var managerPkh = managerAddress.getPaymentCredentialHash()
                    .map(HexUtil::encodeHexString)
                    .orElseThrow(() -> new RuntimeException("no payment credential"));

            var managerNodeOpt = findWhitelistMembershipNode(managerListUtxos, managerPkh);
            if (managerNodeOpt.isEmpty()) {
                return TransactionContext.typedError("manager not found in manager list: " + managerPkh);
            }
            var managerNode = managerNodeOpt.get();

            var tx = new Tx()
                    .collectFrom(managerUtxos)
                    .collectFrom(coveringNode, ConstrPlutusData.of(0))
                    .withdraw(managerAuthAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                    .mintAsset(whitelistMintScript, newNodeNft, mintRedeemer)
                    .payToContract(whitelistAddress.getAddress(), ValueUtil.toAmountList(coveringNodeValue), updatedCoveringDatum)
                    .payToContract(whitelistAddress.getAddress(), ValueUtil.toAmountList(newNodeValue), newNodeDatum)
                    .readFrom(TransactionInput.builder()
                            .transactionId(managerNode.getTxHash())
                            .index(managerNode.getOutputIndex())
                            .build())
                    .attachSpendingValidator(whitelistSpendScript)
                    .attachRewardValidator(managerAuthScript)
                    .withChangeAddress(request.adminAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(managerAddress.getPaymentCredentialHash().get())
                    .feePayer(request.adminAddress())
                    .mergeOutputs(false)
                    .build();

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.error("error building add to whitelist tx", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    @Override
    public TransactionContext<Void> buildRemoveFromWhitelistTransaction(
            RemoveFromWhitelistRequest request,
            ProtocolBootstrapParams protocolParams) {

        try {
            var whitelistPolicyId = context.getWhitelistPolicyId();
            var managerAuthHash = context.getManagerAuthHash();

            var managerUtxos = accountService.findAdaOnlyUtxo(request.adminAddress(), 10_000_000L);

            var whitelistSpendScript = wlScriptBuilder.buildWhitelistSpendScript(whitelistPolicyId);
            var whitelistAddress = AddressProvider.getEntAddress(whitelistSpendScript, network.getCardanoNetwork());
            var whitelistUtxos = utxoProvider.findUtxos(whitelistAddress.getAddress());

            var managerListPolicyId = context.getManagerListPolicyId();
            var managerAuthScript = wlScriptBuilder.buildManagerAuthScript(managerListPolicyId);
            var managerAuthAddress = AddressProvider.getRewardAddress(managerAuthScript, network.getCardanoNetwork());

            var targetCredential = request.targetCredential();

            // Find the node to remove (key == targetCredential)
            var nodeToRemoveOpt = findWhitelistMembershipNode(whitelistUtxos, targetCredential);
            if (nodeToRemoveOpt.isEmpty()) {
                return TransactionContext.typedError("target not found in whitelist: " + targetCredential);
            }
            var nodeToRemove = nodeToRemoveOpt.get();
            var removedDatum = parseLinkedListDatum(nodeToRemove);

            // Find the predecessor node (node.next == targetCredential)
            var predecessorOpt = findPredecessorNode(whitelistUtxos, targetCredential);
            if (predecessorOpt.isEmpty()) {
                return TransactionContext.typedError("predecessor node not found for: " + targetCredential);
            }
            var predecessorNode = predecessorOpt.get();
            var predecessorDatum = parseLinkedListDatum(predecessorNode);

            // Updated predecessor: key stays same, next = removed node's next
            var updatedPredecessorDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(HexUtil.decodeHexString(predecessorDatum.first())),
                    BytesPlutusData.of(HexUtil.decodeHexString(removedDatum.second()))
            );

            var whitelistMintScript = wlScriptBuilder.buildWhitelistMintScript(
                    context.getWhitelistInitTxInput(), managerAuthHash);

            // Burn the removed node's NFT
            var burnNft = Asset.builder()
                    .name("0x" + targetCredential)
                    .value(ONE.negate())
                    .build();

            // Remove redeemer (constr 2 = Remove)
            var mintRedeemer = ConstrPlutusData.of(2,
                    BytesPlutusData.of(HexUtil.decodeHexString(targetCredential))
            );

            var predecessorNodeValue = predecessorNode.toValue();

            // Manager auth proof
            var managerListSpendScript = wlScriptBuilder.buildManagerListSpendScript(managerListPolicyId);
            var managerListAddress = AddressProvider.getEntAddress(managerListSpendScript, network.getCardanoNetwork());
            var managerListUtxos = utxoProvider.findUtxos(managerListAddress.getAddress());

            var managerAddress = new Address(request.adminAddress());
            var managerPkh = managerAddress.getPaymentCredentialHash()
                    .map(HexUtil::encodeHexString)
                    .orElseThrow(() -> new RuntimeException("no payment credential"));

            var managerNodeOpt = findWhitelistMembershipNode(managerListUtxos, managerPkh);
            if (managerNodeOpt.isEmpty()) {
                return TransactionContext.typedError("manager not found in manager list: " + managerPkh);
            }
            var managerNode = managerNodeOpt.get();

            var tx = new Tx()
                    .collectFrom(managerUtxos)
                    .collectFrom(predecessorNode, ConstrPlutusData.of(0))
                    .collectFrom(nodeToRemove, ConstrPlutusData.of(0))
                    .withdraw(managerAuthAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                    .mintAsset(whitelistMintScript, burnNft, mintRedeemer)
                    .payToContract(whitelistAddress.getAddress(), ValueUtil.toAmountList(predecessorNodeValue), updatedPredecessorDatum)
                    .readFrom(TransactionInput.builder()
                            .transactionId(managerNode.getTxHash())
                            .index(managerNode.getOutputIndex())
                            .build())
                    .attachSpendingValidator(whitelistSpendScript)
                    .attachRewardValidator(managerAuthScript)
                    .withChangeAddress(request.adminAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(managerAddress.getPaymentCredentialHash().get())
                    .feePayer(request.adminAddress())
                    .mergeOutputs(false)
                    .build();

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.error("error building remove from whitelist tx", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    // ========== SubstandardGovernance Implementation ==========

    @Override
    public TransactionContext<GovernanceInitResult> buildGovernanceInitTransaction(
            GovernanceInitRequest request,
            ProtocolBootstrapParams params) {

        try {
            var adminAddress = new Address(request.adminAddress());
            var utilityUtxos = accountService.findAdaOnlyUtxo(request.adminAddress());

            // Use first 2 UTxOs as seeds for manager_sigs and manager_list
            if (utilityUtxos.size() < 2) {
                return TransactionContext.typedError("need at least 2 UTxOs for governance init");
            }

            var managerSigsSeedUtxo = utilityUtxos.get(0);
            var managerListSeedUtxo = utilityUtxos.get(1);

            var managerSigsSeedInput = TransactionInput.builder()
                    .transactionId(managerSigsSeedUtxo.getTxHash())
                    .index(managerSigsSeedUtxo.getOutputIndex())
                    .build();

            var managerListSeedInput = TransactionInput.builder()
                    .transactionId(managerListSeedUtxo.getTxHash())
                    .index(managerListSeedUtxo.getOutputIndex())
                    .build();

            // Build manager_signatures mint
            var managerSigsMintScript = wlScriptBuilder.buildManagerSignaturesMintScript(managerSigsSeedInput);
            var managerSigsHash = HexUtil.encodeHexString(managerSigsMintScript.getScriptHash());

            // Build manager_list_mint
            var managerListMintScript = wlScriptBuilder.buildManagerListMintScript(managerListSeedInput, managerSigsHash);
            var managerListCs = managerListMintScript.getPolicyId();

            // Build manager_list_spend
            var managerListSpendScript = wlScriptBuilder.buildManagerListSpendScript(managerListCs);
            var managerListSpendAddress = AddressProvider.getEntAddress(managerListSpendScript, network.getCardanoNetwork());

            // Manager signatures withdraw (for stake address registration)
            var managerSigsWithdrawScript = wlScriptBuilder.buildManagerSignaturesWithdrawScript(managerSigsSeedInput);
            var managerSigsWithdrawAddress = AddressProvider.getRewardAddress(managerSigsWithdrawScript, network.getCardanoNetwork());

            // Manager auth (for stake address registration)
            var managerAuthScript = wlScriptBuilder.buildManagerAuthScript(managerListCs);
            var managerAuthAddress = AddressProvider.getRewardAddress(managerAuthScript, network.getCardanoNetwork());

            // Init datums: head node with key="" and next="ff...ff"
            var managerListInitDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(""),
                    BytesPlutusData.of(HexUtil.decodeHexString("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"))
            );

            // Manager signatures config NFT (head node for manager config)
            var managerSigsNft = Asset.builder().name("ManagerConfig").value(ONE).build();
            var managerListNft = Asset.builder().name("0x").value(ONE).build();

            Value managerListValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(MultiAsset.builder()
                            .policyId(managerListCs)
                            .assets(List.of(managerListNft))
                            .build()))
                    .build();

            // Register stake addresses
            var requiredStakeAddresses = List.of(
                    managerSigsWithdrawAddress.getAddress(),
                    managerAuthAddress.getAddress()
            );

            var stakeAddressesToRegister = requiredStakeAddresses.stream()
                    .filter(stakeAddress -> stakeRegistrationRepository.findRegistrationsByStakeAddress(stakeAddress)
                            .map(reg -> !reg.getType().equals(CertificateType.STAKE_REGISTRATION)).orElse(true))
                    .toList();

            var managersRedeemer = ConstrPlutusData.of(0,
                    ListPlutusData.of(BytesPlutusData.of(adminAddress.getPaymentCredentialHash().get()))
            );


            var tx = new Tx()
                    .collectFrom(utilityUtxos)
                    .mintAsset(managerSigsMintScript, managerSigsNft, managersRedeemer)
                    .mintAsset(managerListMintScript, managerListNft, ConstrPlutusData.of(0))
                    .payToAddress(request.adminAddress(), Amount.ada(40L))
                    .payToContract(managerListSpendAddress.getAddress(), ValueUtil.toAmountList(managerListValue), managerListInitDatum)
                    .withChangeAddress(request.adminAddress());

            stakeAddressesToRegister.forEach(tx::registerStakeAddress);

            var transaction = quickTxBuilder.compose(tx)
                    .feePayer(request.adminAddress())
                    .withRequiredSigners(adminAddress)
                    .ignoreScriptCostEvaluationError(false)
                    .mergeOutputs(false)
                    .build();

            var adminPkh = adminAddress.getPaymentCredentialHash()
                    .map(HexUtil::encodeHexString)
                    .orElseThrow(() -> new RuntimeException("no payment credential"));

            // Persist
            managerSignaturesInitRepository.save(ManagerSignaturesInitEntity.builder()
                    .managerSigsPolicyId(managerSigsMintScript.getPolicyId())
                    .adminPkh(adminPkh)
                    .txHash(managerSigsSeedUtxo.getTxHash())
                    .outputIndex(managerSigsSeedUtxo.getOutputIndex())
                    .build());

            managerListInitRepository.save(ManagerListInitEntity.builder()
                    .managerListPolicyId(managerListCs)
                    .managerSigsInit(managerSignaturesInitRepository.findByManagerSigsPolicyId(managerSigsMintScript.getPolicyId()).get())
                    .txHash(managerListSeedUtxo.getTxHash())
                    .outputIndex(managerListSeedUtxo.getOutputIndex())
                    .build());

            var managerAuthHash = HexUtil.encodeHexString(managerAuthScript.getScriptHash());
            return TransactionContext.ok(transaction.serializeToHex(),
                    new GovernanceInitResult(
                            managerSigsMintScript.getPolicyId(),
                            managerListCs,
                            managerAuthHash,
                            null,
                            transaction.serializeToHex()));

        } catch (Exception e) {
            log.error("error building governance init tx", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    @Override
    public TransactionContext<Void> buildAddAdminTransaction(
            AddAdminRequest request,
            ProtocolBootstrapParams params) {

        try {
            var managerListPolicyId = context.getManagerListPolicyId();
            var managerSigsPolicyId = context.getManagerSigsPolicyId();

            var adminUtxos = accountService.findAdaOnlyUtxo(request.adminAddress(), 10_000_000L);

            var managerListSpendScript = wlScriptBuilder.buildManagerListSpendScript(managerListPolicyId);
            var managerListAddress = AddressProvider.getEntAddress(managerListSpendScript, network.getCardanoNetwork());
            var managerListUtxos = utxoProvider.findUtxos(managerListAddress.getAddress());

            var managerSigsWithdrawScript = wlScriptBuilder.buildManagerSignaturesWithdrawScript(
                    context.getManagerSigsInitTxInput());
            var managerSigsWithdrawAddress = AddressProvider.getRewardAddress(managerSigsWithdrawScript, network.getCardanoNetwork());

            var targetCredential = request.targetCredential();

            // Find covering node for insertion
            var coveringNodeOpt = findCoveringNode(managerListUtxos, targetCredential);
            if (coveringNodeOpt.isEmpty()) {
                return TransactionContext.typedError("could not find covering node for manager insertion");
            }
            var coveringNode = coveringNodeOpt.get();
            var existingDatum = parseLinkedListDatum(coveringNode);

            var managerListMintScript = wlScriptBuilder.buildManagerListMintScript(
                    context.getManagerListInitTxInput(),
                    HexUtil.encodeHexString(managerSigsWithdrawScript.getScriptHash()));

            // New node
            var newNodeDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(HexUtil.decodeHexString(targetCredential)),
                    BytesPlutusData.of(HexUtil.decodeHexString(existingDatum.second()))
            );

            var updatedCoveringDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(HexUtil.decodeHexString(existingDatum.first())),
                    BytesPlutusData.of(HexUtil.decodeHexString(targetCredential))
            );

            var newNodeNft = Asset.builder()
                    .name("0x" + targetCredential)
                    .value(ONE)
                    .build();

            Value newNodeValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(MultiAsset.builder()
                            .policyId(managerListPolicyId)
                            .assets(List.of(newNodeNft))
                            .build()))
                    .build();

            var mintRedeemer = ConstrPlutusData.of(1,
                    BytesPlutusData.of(HexUtil.decodeHexString(targetCredential))
            );

            var coveringNodeValue = coveringNode.toValue();

            var adminAddress = new Address(request.adminAddress());

            var tx = new Tx()
                    .collectFrom(adminUtxos)
                    .collectFrom(coveringNode, ConstrPlutusData.of(0))
                    .withdraw(managerSigsWithdrawAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                    .mintAsset(managerListMintScript, newNodeNft, mintRedeemer)
                    .payToContract(managerListAddress.getAddress(), ValueUtil.toAmountList(coveringNodeValue), updatedCoveringDatum)
                    .payToContract(managerListAddress.getAddress(), ValueUtil.toAmountList(newNodeValue), newNodeDatum)
                    .attachSpendingValidator(managerListSpendScript)
                    .attachRewardValidator(managerSigsWithdrawScript)
                    .withChangeAddress(request.adminAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(adminAddress.getPaymentCredentialHash().get())
                    .feePayer(request.adminAddress())
                    .mergeOutputs(false)
                    .build();

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.error("error building add admin tx", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    @Override
    public TransactionContext<Void> buildRemoveAdminTransaction(
            RemoveAdminRequest request,
            ProtocolBootstrapParams params) {

        try {
            var managerListPolicyId = context.getManagerListPolicyId();

            var adminUtxos = accountService.findAdaOnlyUtxo(request.adminAddress(), 10_000_000L);

            var managerListSpendScript = wlScriptBuilder.buildManagerListSpendScript(managerListPolicyId);
            var managerListAddress = AddressProvider.getEntAddress(managerListSpendScript, network.getCardanoNetwork());
            var managerListUtxos = utxoProvider.findUtxos(managerListAddress.getAddress());

            var managerSigsWithdrawScript = wlScriptBuilder.buildManagerSignaturesWithdrawScript(
                    context.getManagerSigsInitTxInput());
            var managerSigsWithdrawAddress = AddressProvider.getRewardAddress(managerSigsWithdrawScript, network.getCardanoNetwork());

            var targetCredential = request.targetCredential();

            // Find node to remove
            var nodeToRemoveOpt = findWhitelistMembershipNode(managerListUtxos, targetCredential);
            if (nodeToRemoveOpt.isEmpty()) {
                return TransactionContext.typedError("manager not found: " + targetCredential);
            }
            var nodeToRemove = nodeToRemoveOpt.get();
            var removedDatum = parseLinkedListDatum(nodeToRemove);

            // Find predecessor
            var predecessorOpt = findPredecessorNode(managerListUtxos, targetCredential);
            if (predecessorOpt.isEmpty()) {
                return TransactionContext.typedError("predecessor node not found for: " + targetCredential);
            }
            var predecessorNode = predecessorOpt.get();
            var predecessorDatum = parseLinkedListDatum(predecessorNode);

            var updatedPredecessorDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(HexUtil.decodeHexString(predecessorDatum.first())),
                    BytesPlutusData.of(HexUtil.decodeHexString(removedDatum.second()))
            );

            var managerListMintScript = wlScriptBuilder.buildManagerListMintScript(
                    context.getManagerListInitTxInput(),
                    HexUtil.encodeHexString(managerSigsWithdrawScript.getScriptHash()));

            var burnNft = Asset.builder()
                    .name("0x" + targetCredential)
                    .value(ONE.negate())
                    .build();

            var mintRedeemer = ConstrPlutusData.of(2,
                    BytesPlutusData.of(HexUtil.decodeHexString(targetCredential))
            );

            var predecessorNodeValue = predecessorNode.toValue();

            var adminAddress = new Address(request.adminAddress());

            var tx = new Tx()
                    .collectFrom(adminUtxos)
                    .collectFrom(predecessorNode, ConstrPlutusData.of(0))
                    .collectFrom(nodeToRemove, ConstrPlutusData.of(0))
                    .withdraw(managerSigsWithdrawAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                    .mintAsset(managerListMintScript, burnNft, mintRedeemer)
                    .payToContract(managerListAddress.getAddress(), ValueUtil.toAmountList(predecessorNodeValue), updatedPredecessorDatum)
                    .attachSpendingValidator(managerListSpendScript)
                    .attachRewardValidator(managerSigsWithdrawScript)
                    .withChangeAddress(request.adminAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(adminAddress.getPaymentCredentialHash().get())
                    .feePayer(request.adminAddress())
                    .mergeOutputs(false)
                    .build();

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.error("error building remove admin tx", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    // ========== Private Helpers ==========

    /**
     * Build issuer admin script (same pattern as FES — uses admin PKH for withdraw-0 trick).
     * Uses the FES issuer_admin_contract since it's shared across substandards.
     */
    private com.bloxbean.cardano.client.plutus.spec.PlutusScript buildIssuerAdminScript(Credential adminPkh) {
        // Reuse the FES issuer admin contract for minting/burning authorization
        var contract = substandardService.getSubstandardValidator("freeze-and-seize", "example_transfer_logic.issuer_admin_contract.withdraw")
                .orElseThrow(() -> new IllegalStateException("issuer_admin_contract not found"));

        var params = ListPlutusData.of(
                com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData.of(
                        adminPkh.getType() == CredentialType.Key ? 0 : 1,
                        BytesPlutusData.of(adminPkh.getBytes())
                )
        );

        try {
            var parameterizedCode = com.bloxbean.cardano.aiken.AikenScriptUtil.applyParamToScript(params, contract.scriptBytes());
            return com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    parameterizedCode, com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion.v3);
        } catch (Exception e) {
            throw new RuntimeException("Failed to build issuer admin script", e);
        }
    }

    /**
     * Find a whitelist membership node where node.key == credential.
     */
    private Optional<Utxo> findWhitelistMembershipNode(List<Utxo> whitelistUtxos, String credential) {
        return whitelistUtxos.stream()
                .filter(utxo -> {
                    var datum = parseLinkedListDatum(utxo);
                    return datum != null && datum.first().equals(credential);
                })
                .findFirst();
    }

    /**
     * Find the covering node where node.key < credential < node.next (for insertion).
     */
    private Optional<Utxo> findCoveringNode(List<Utxo> utxos, String credential) {
        return utxos.stream()
                .filter(utxo -> {
                    var datum = parseLinkedListDatum(utxo);
                    return datum != null && datum.first().compareTo(credential) < 0 && datum.second().compareTo(credential) > 0;
                })
                .findFirst();
    }

    /**
     * Find the predecessor node where node.next == credential (for removal).
     */
    private Optional<Utxo> findPredecessorNode(List<Utxo> utxos, String credential) {
        return utxos.stream()
                .filter(utxo -> {
                    var datum = parseLinkedListDatum(utxo);
                    return datum != null && datum.second().equals(credential);
                })
                .findFirst();
    }

    /**
     * Parse a linked list node datum into (key, next) pair.
     * Expected format: ConstrPlutusData(0, [BytesPlutusData(key), BytesPlutusData(next)])
     */
    private Pair<String, String> parseLinkedListDatum(Utxo utxo) {
        try {
            var inlineDatum = utxo.getInlineDatum();
            if (inlineDatum == null) return null;

            PlutusData plutusData = PlutusData.deserialize(HexUtil.decodeHexString(inlineDatum));

            if (plutusData instanceof ConstrPlutusData constr) {
                var items = constr.getData().getPlutusDataList();
                if (items.size() >= 2) {
                    var key = HexUtil.encodeHexString(((BytesPlutusData) items.get(0)).getValue());
                    var next = HexUtil.encodeHexString(((BytesPlutusData) items.get(1)).getValue());
                    return new Pair<>(key, next);
                }
            }
            return null;
        } catch (Exception e) {
            log.debug("Failed to parse linked list datum", e);
            return null;
        }
    }
}
