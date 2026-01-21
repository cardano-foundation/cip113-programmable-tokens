package org.cardanofoundation.cip113.service.substandard;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.aiken.AikenTransactionEvaluator;
import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
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
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.repository.UtxoRepository;
import com.easy1staking.cardano.model.AssetType;
import com.easy1staking.util.Pair;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.entity.BlacklistInitEntity;
import org.cardanofoundation.cip113.entity.FreezeAndSeizeTokenRegistrationEntity;
import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.TransactionContext.MintingResult;
import org.cardanofoundation.cip113.model.TransactionContext.RegistrationResult;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.model.bootstrap.TxInput;
import org.cardanofoundation.cip113.model.onchain.RegistryNode;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.*;
import org.cardanofoundation.cip113.repository.BlacklistInitRepository;
import org.cardanofoundation.cip113.repository.FreezeAndSeizeTokenRegistrationRepository;
import org.cardanofoundation.cip113.service.*;
import org.cardanofoundation.cip113.service.substandard.capabilities.BasicOperations;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable;
import org.cardanofoundation.cip113.service.substandard.context.FreezeAndSeizeContext;
import org.cardanofoundation.cip113.util.PlutusSerializationHelper;
import org.springframework.context.annotation.Scope;
import org.springframework.stereotype.Component;

import java.math.BigInteger;
import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

import static java.math.BigInteger.ONE;
import static java.math.BigInteger.ZERO;
import static org.cardanofoundation.cip113.util.PlutusSerializationHelper.serialize;

/**
 * Handler for the "freeze-and-seize" programmable token substandard.
 *
 * <p>This handler supports regulated stablecoins with compliance features:</p>
 * <ul>
 *   <li><b>BasicOperations</b> - Register, mint, burn, transfer programmable tokens</li>
 *   <li><b>BlacklistManageable</b> - Freeze/unfreeze addresses via blacklist</li>
 *   <li><b>Seizeable</b> - Seize assets from blacklisted/sanctioned addresses</li>
 * </ul>
 *
 * <p>This handler requires a {@link FreezeAndSeizeContext} to be set before use,
 * as there can be multiple stablecoin deployments, each with their own configuration.</p>
 *
 * <p>Use {@link SubstandardHandlerFactory#getHandler(String, org.cardanofoundation.cip113.service.substandard.context.SubstandardContext)}
 * to get a properly configured instance.</p>
 */
@Component
@Scope("prototype") // New instance each time for context isolation
@RequiredArgsConstructor
@Slf4j
public class FreezeAndSeizeHandler implements SubstandardHandler, BasicOperations<FreezeAndSeizeRegisterRequest>, BlacklistManageable, Seizeable {

    private static final String SUBSTANDARD_ID = "freeze-and-seize";

    private final ObjectMapper objectMapper;
    private final AppConfig.Network network;
    private final UtxoRepository utxoRepository;
    private final BlacklistNodeParser blacklistNodeParser;
    private final RegistryNodeParser registryNodeParser;
    private final AccountService accountService;
    private final SubstandardService substandardService;
    private final ProtocolScriptBuilderService protocolScriptBuilderService;
    private final LinkedListService linkedListService;
    private final QuickTxBuilder quickTxBuilder;

    private final FreezeAndSeizeTokenRegistrationRepository freezeAndSeizeTokenRegistrationRepository;

    private final BlacklistInitRepository blacklistInitRepository;

    private final UtxoProvider utxoProvider;

    private final BFBackendService bfBackendService;

    /**
     * Context for this handler instance.
     * Must be set before performing any operations.
     */
    @Setter
    private FreezeAndSeizeContext context;

    @Override
    public String getSubstandardId() {
        return SUBSTANDARD_ID;
    }

    // ========== BasicOperations Implementation ==========

    @Override
    public TransactionContext<RegistrationResult> buildRegistrationTransaction(
            FreezeAndSeizeRegisterRequest request,
            ProtocolBootstrapParams protocolParams) {

        try {
            var adminPkh = Credential.fromKey(request.getAdminPubKeyHash());
            var blacklistNodePolicyId = request.getBlacklistNodePolicyId();

            var feePayerUtxos = accountService.findAdaOnlyUtxo(request.getFeePayerAddress(), 10_000_000L);

            var bootstrapTxHash = protocolParams.txHash();

            var directorySpendContract = protocolScriptBuilderService.getParameterizedDirectorySpendScript(protocolParams);

            var protocolParamsUtxoOpt = utxoProvider.findUtxo(bootstrapTxHash, 0);
            if (protocolParamsUtxoOpt.isEmpty()) {
                TransactionContext.error("could not resolve protocol params");
            }

            var protocolParamsUtxo = protocolParamsUtxoOpt.get();

            var directorySpendContractAddress = AddressProvider.getEntAddress(directorySpendContract, network.getCardanoNetwork());
            log.info("directorySpendContractAddress: {}", directorySpendContractAddress.getAddress());

            var issuanceUtxoOpt = utxoProvider.findUtxo(bootstrapTxHash, 2);
            if (issuanceUtxoOpt.isEmpty()) {
                TransactionContext.error("could not resolve issuance params");
            }
            var issuanceUtxo = issuanceUtxoOpt.get();
            log.info("issuanceUtxo: {}", issuanceUtxo);

            /// Getting Substandard Contracts and parameterize
            // Issuer to be used for minting/burning/sieze
            var issuerContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "example_transfer_logic.issuer_admin_contract.withdraw");
            var issuerContract = issuerContractOpt.get();

            var issuerAdminContractInitParams = ListPlutusData.of(serialize(adminPkh));

            var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(issuerAdminContractInitParams, issuerContract.scriptBytes()),
                    PlutusVersion.v3
            );

            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());


            var accountInfo = bfBackendService.getAccountService().getAccountInformation(substandardIssueAddress.getAddress());
            if (!accountInfo.isSuccessful()) {
                return TransactionContext.typedError("could no check status script account");
            }
//            else if (!accountInfo.getValue().getActive()) {
//                return TransactionContext.typedError("script not registered");
//            }
//            log.info("is {} registered: {}", substandardIssueAddress.getAddress(), accountInfo.getValue().getActive());


            var transferContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "example_transfer_logic.transfer.withdraw");
            var transferContract = transferContractOpt.get();

            var transferContractInitParams = ListPlutusData.of(serialize(Credential.fromScript(protocolParams.programmableLogicBaseParams().scriptHash())),
                    BytesPlutusData.of(HexUtil.decodeHexString(blacklistNodePolicyId))
            );

            var substandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(transferContractInitParams, transferContract.scriptBytes()),
                    PlutusVersion.v3
            );
            var substandardTransferAddress = AddressProvider.getRewardAddress(substandardTransferContract, network.getCardanoNetwork());
            log.info("substandardTransferAddress: {}", substandardTransferAddress.getAddress());


            var issuanceContract = protocolScriptBuilderService.getParameterizedIssuanceMintScript(protocolParams, substandardIssueContract);
            final var progTokenPolicyId = issuanceContract.getPolicyId();

            var registryAddress = AddressProvider.getEntAddress(directorySpendContract, network.getCardanoNetwork());

            var registryEntries = utxoProvider.findUtxos(registryAddress.getAddress());
            log.info("found {}, registry entries", registryEntries.size());

            var nodeAlreadyPresent = linkedListService.nodeAlreadyPresent(progTokenPolicyId, registryEntries, utxo -> registryNodeParser.parse(utxo.getInlineDatum())
                    .map(RegistryNode::key));

            if (nodeAlreadyPresent) {
                log.warn("registry node already present");
                TransactionContext.error("registry node already present");
            }

            var nodeToReplaceOpt = linkedListService.findNodeToReplace(progTokenPolicyId, registryEntries, utxo -> registryNodeParser.parse(utxo.getInlineDatum())
                    .map(node -> new LinkedListNode(node.key(), node.next())));

            if (nodeToReplaceOpt.isEmpty()) {
                log.warn("could not find node to replace");
                TransactionContext.error("could not find node to replace");
            }

            var directoryUtxo = nodeToReplaceOpt.get();
            log.info("directoryUtxo: {}", directoryUtxo);
            var existingRegistryNodeDatumOpt = registryNodeParser.parse(directoryUtxo.getInlineDatum());

            if (existingRegistryNodeDatumOpt.isEmpty()) {
                TransactionContext.error("could not parse current registry node");
            }

            var existingRegistryNodeDatum = existingRegistryNodeDatumOpt.get();

            // Directory MINT - NFT, address, datum and value
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
                TransactionContext.error("could not find amount for directory mint");
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
                    HexUtil.encodeHexString(substandardIssueContract.getScriptHash()),
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
                    .name("0x" + request.getAssetName())
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

            log.info("request.getRecipientAddress(): {}", request.getRecipientAddress());
            var payeeAddress = new Address(request.getRecipientAddress());

            var targetAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolParams.programmableLogicBaseParams().scriptHash()),
                    payeeAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

//        if (registerWithdrawScriptsAddresses) {
//
//            var registerAddressTx = new Tx()
//                    .from(issuerAccount.baseAddress())
//                    .registerStakeAddress(substandardIssueAddress.getAddress())
//                    .registerStakeAddress(substandardTransferAddress.getAddress())
//                    .withChangeAddress(issuerAccount.baseAddress());
//
//            quickTxBuilder.compose(registerAddressTx)
//                    .feePayer(issuerAccount.baseAddress())
//                    .withSigner(SignerProviders.signerFrom(issuerAccount))
//                    .completeAndWait();
//
//        }

            var tx = new ScriptTx()
                    .collectFrom(feePayerUtxos)
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
                    .withChangeAddress(request.getFeePayerAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(adminPkh.getBytes())
                    .feePayer(request.getFeePayerAddress())
//                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                    .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                    .preBalanceTx((txBuilderContext, transaction1) -> {
                        var outputs = transaction1.getBody().getOutputs();
                        if (outputs.getFirst().getAddress().equals(request.getFeePayerAddress())) {
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

            var blacklistInitOpt = blacklistInitRepository.findByBlacklistNodePolicyId(blacklistNodePolicyId);

            if (blacklistInitOpt.isEmpty()) {
                return TransactionContext.typedError("blacklist init could not be found");
            }

            freezeAndSeizeTokenRegistrationRepository.save(FreezeAndSeizeTokenRegistrationEntity.builder()
                    .programmableTokenPolicyId(progTokenPolicyId)
                    .issuerAdminPkh(HexUtil.encodeHexString(adminPkh.getBytes()))
                    .blacklistInit(blacklistInitOpt.get())
                    .build());

            return TransactionContext.ok(transaction.serializeToHex(), new RegistrationResult(progTokenPolicyId));

        } catch (Exception e) {
            log.error("error", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    @Override
    public TransactionContext<Void> buildMintTransaction(
            MintTokenRequest request,
            ProtocolBootstrapParams protocolParams) {
        // TODO: Implement minting for freeze-and-seize
        log.warn("buildMintTransaction not yet implemented for freeze-and-seize");
        return TransactionContext.typedError("Not yet implemented");
    }

    @Override
    public TransactionContext<Void> buildTransferTransaction(
            TransferTokenRequest request,
            ProtocolBootstrapParams protocolParams) {
        // TODO: Implement transfer for freeze-and-seize
        // Must check blacklist during transfer validation
        log.warn("buildTransferTransaction not yet implemented for freeze-and-seize");
        return TransactionContext.typedError("Not yet implemented");
    }

    // ========== BlacklistManageable Implementation ==========

    @Override
    public TransactionContext<MintingResult> buildBlacklistInitTransaction(BlacklistInitRequest request, ProtocolBootstrapParams protocolParams) {

        try {

            log.info("blacklistInitRequest: {}", request);

            var adminAddress = new Address(request.adminAddress());

            var utilityUtxos = accountService.findAdaOnlyUtxo(request.feePayerAddress(), 10_000_000L);
            log.info("admin utxos size: {}", utilityUtxos.size());

            var utilityAdaBalance = utilityUtxos.stream()
                    .flatMap(utxo -> utxo.getAmount().stream())
                    .map(Amount::getQuantity)
                    .reduce(BigInteger::add)
                    .orElse(ZERO);

            log.info("utility ada balance: {}", utilityAdaBalance);

            var bootstrapUtxo = utilityUtxos.getFirst();
            log.info("bootstrapUtxo: {}", bootstrapUtxo);

            var bootstrapUtxoOpt = utxoProvider.findUtxo(bootstrapUtxo.getTxHash(), bootstrapUtxo.getOutputIndex());

            if (bootstrapUtxoOpt.isEmpty()) {
                return TransactionContext.typedError("no utxo found");
            }

            var blackListMintValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "blacklist_mint.blacklist_mint.mint");
            var blackListMintValidator = blackListMintValidatorOpt.get();

            var serialisedTxInput = PlutusSerializationHelper.serialize(TransactionInput.builder()
                    .transactionId(bootstrapUtxo.getTxHash())
                    .index(bootstrapUtxo.getOutputIndex())
                    .build());

            var adminPkhBytes = adminAddress.getPaymentCredentialHash().get();
            var adminPks = HexUtil.encodeHexString(adminPkhBytes);
            var blacklistMintInitParams = ListPlutusData.of(serialisedTxInput,
                    BytesPlutusData.of(adminPkhBytes)
            );

            var parameterisedBlacklistMintingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(blacklistMintInitParams, blackListMintValidator.scriptBytes()),
                    PlutusVersion.v3
            );

            var blacklistSpendValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "blacklist_spend.blacklist_spend.spend");
            var blacklistSpendValidator = blacklistSpendValidatorOpt.get();

            var blacklistSpendInitParams = ListPlutusData.of(BytesPlutusData.of(HexUtil.decodeHexString(parameterisedBlacklistMintingScript.getPolicyId())));
            var parameterisedBlacklistSpendingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(blacklistSpendInitParams, blacklistSpendValidator.scriptBytes()),
                    PlutusVersion.v3
            );
            var blacklistSpendAddress = AddressProvider.getEntAddress(parameterisedBlacklistSpendingScript, network.getCardanoNetwork());

            var blacklistInitDatum = BlacklistNode.builder()
                    .key("")
                    .next("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
                    .build();

            var blacklistAsset = Asset.builder().name("0x").value(ONE).build();

            var blacklistNft = Asset.builder()
                    .name("0x")
                    .value(BigInteger.ONE)
                    .build();

            Value blacklistValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(
                            MultiAsset.builder()
                                    .policyId(parameterisedBlacklistMintingScript.getPolicyId())
                                    .assets(List.of(blacklistNft))
                                    .build()
                    ))
                    .build();

            var tx = new ScriptTx()
                    .collectFrom(utilityUtxos)
                    .mintAsset(parameterisedBlacklistMintingScript, blacklistAsset, ConstrPlutusData.of(0))
                    .payToContract(blacklistSpendAddress.getAddress(), ValueUtil.toAmountList(blacklistValue), blacklistInitDatum.toPlutusData())
                    .withChangeAddress(request.feePayerAddress());


            var transaction = quickTxBuilder.compose(tx)
                    .feePayer(request.feePayerAddress())
                    .mergeOutputs(false)
                    .build();

            log.info("transaction: {}", transaction.serializeToHex());
            log.info("transaction: {}", objectMapper.writeValueAsString(transaction));

            var mintBootstrap = new BlacklistMintBootstrap(TxInput.from(bootstrapUtxo), adminPks, parameterisedBlacklistMintingScript.getPolicyId());
            var spendBootstrap = new BlacklistSpendBootstrap(parameterisedBlacklistMintingScript.getPolicyId(), parameterisedBlacklistSpendingScript.getPolicyId());
            var bootstrap = new BlacklistBootstrap(mintBootstrap, spendBootstrap);

            var stringBoostrap = objectMapper.writeValueAsString(bootstrap);
            log.info("bootstrap: {}", stringBoostrap);

            blacklistInitRepository.save(BlacklistInitEntity.builder()
                    .blacklistNodePolicyId(parameterisedBlacklistMintingScript.getPolicyId())
                    .adminPkh(adminPks)
                    .txHash(bootstrapUtxo.getTxHash())
                    .outputIndex(bootstrapUtxo.getOutputIndex())
                    .build());

            return TransactionContext.ok(transaction.serializeToHex(), new MintingResult(parameterisedBlacklistMintingScript.getPolicyId(), ""));

        } catch (Exception e) {
            return TransactionContext.typedError(String.format("could not build transaction: %s", e.getMessage()));
        }

    }

    @Override
    public TransactionContext<Void> buildAddToBlacklistTransaction(AddToBlacklistRequest request, ProtocolBootstrapParams protocolParams) {

        try {
            log.info("addToBlacklistRequest: {}", request);

            var blacklistedAddress = new Address(request.targetAddress());

            var adminUtxos = accountService.findAdaOnlyUtxoByPaymentPubKeyHash(context.getBlacklistManagerPkh(), 10_000_000L);
            log.info("admin utxos size: {}", adminUtxos.size());
            var adminAdaBalance = adminUtxos.stream()
                    .flatMap(utxo -> utxo.getAmount().stream())
                    .map(Amount::getQuantity)
                    .reduce(BigInteger::add)
                    .orElse(ZERO);
            log.info("admin ada balance: {}", adminAdaBalance);

            var blackListMintValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "blacklist_mint.blacklist_mint.mint");
            var blackListMintValidator = blackListMintValidatorOpt.get();

            var serialisedTxInput = PlutusSerializationHelper.serialize(TransactionInput.builder()
                    .transactionId(context.getBlacklistInitTxInput().getTransactionId())
                    .index(context.getBlacklistInitTxInput().getIndex())
                    .build());

            var blacklistMintInitParams = ListPlutusData.of(serialisedTxInput,
                    BytesPlutusData.of(HexUtil.decodeHexString(context.getIssuerAdminPkh()))
            );

            var parameterisedBlacklistMintingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(blacklistMintInitParams, blackListMintValidator.scriptBytes()),
                    PlutusVersion.v3
            );

            var blacklistSpendValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "blacklist_spend.blacklist_spend.spend");
            var blacklistSpendValidator = blacklistSpendValidatorOpt.get();

            var blacklistSpendInitParams = ListPlutusData.of(BytesPlutusData.of(HexUtil.decodeHexString(parameterisedBlacklistMintingScript.getPolicyId())));
            var parameterisedBlacklistSpendingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(blacklistSpendInitParams, blacklistSpendValidator.scriptBytes()),
                    PlutusVersion.v3
            );
            log.info("parameterisedBlacklistSpendingScript: {}", parameterisedBlacklistSpendingScript.getPolicyId());

            var blacklistSpendAddress = AddressProvider.getEntAddress(parameterisedBlacklistSpendingScript, network.getCardanoNetwork());
            log.info("blacklistSpend: {}", blacklistSpendAddress.getAddress());

            var blacklistUtxos = utxoProvider.findUtxos(blacklistSpendAddress.getAddress());
            log.info("blacklistUtxos: {}", blacklistUtxos.size());
            blacklistUtxos.forEach(utxo -> log.info("bl utxo: {}", utxo));

            var aliceStakingPkh = blacklistedAddress.getDelegationCredentialHash().map(HexUtil::encodeHexString).get();
            var blocklistNodeToReplaceOpt = blacklistUtxos.stream()
                    .flatMap(utxo -> blacklistNodeParser.parse(utxo.getInlineDatum())
                            .stream()
                            .flatMap(blacklistNode -> Stream.of(new Pair<>(utxo, blacklistNode))))
                    .filter(utxoBlacklistNodePair -> {
                        var datum = utxoBlacklistNodePair.second();
                        return datum.key().compareTo(aliceStakingPkh) < 0 && aliceStakingPkh.compareTo(datum.next()) < 0;
                    })
                    .findAny();

            if (blocklistNodeToReplaceOpt.isEmpty()) {
                return TransactionContext.error("could not find blocklist node to replace");
            }

            var blocklistNodeToReplace = blocklistNodeToReplaceOpt.get();
            log.info("blocklistNodeToReplace: {}", blocklistNodeToReplace);

            var preexistingNode = blocklistNodeToReplace.second();

            var beforeNode = preexistingNode.toBuilder().next(aliceStakingPkh).build();
            var afterNode = preexistingNode.toBuilder().key(aliceStakingPkh).build();

            var mintRedeemer = ConstrPlutusData.of(1, BytesPlutusData.of(HexUtil.decodeHexString(aliceStakingPkh)));

            // Before/Updated
            var preExistingAmount = blocklistNodeToReplace.first().getAmount();
            // Next/minted
            var mintedAmount = Value.from(parameterisedBlacklistMintingScript.getPolicyId(), "0x" + aliceStakingPkh, ONE);

            var tx = new ScriptTx()
                    .collectFrom(adminUtxos)
                    .collectFrom(blocklistNodeToReplace.first(), ConstrPlutusData.of(0))
                    .mintAsset(parameterisedBlacklistMintingScript, Asset.builder().name("0x" + aliceStakingPkh).value(ONE).build(), mintRedeemer)
                    // Replaced
                    .payToContract(blacklistSpendAddress.getAddress(), preExistingAmount, beforeNode.toPlutusData())
                    .payToContract(blacklistSpendAddress.getAddress(), ValueUtil.toAmountList(mintedAmount), afterNode.toPlutusData())
                    .attachSpendingValidator(parameterisedBlacklistSpendingScript)
                    .withChangeAddress(request.feePayerAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(HexUtil.decodeHexString(context.getBlacklistManagerPkh()))
                    .feePayer(request.feePayerAddress())
//                    .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                    .mergeOutputs(false)
                    .build();

            log.info("transaction: {}", transaction.serializeToHex());
            log.info("transaction: {}", objectMapper.writeValueAsString(transaction));

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            return TransactionContext.error(String.format("error: %s", e.getMessage()));

        }

    }

    @Override
    public TransactionContext<Void> buildRemoveFromBlacklistTransaction(
            RemoveFromBlacklistRequest request,
            ProtocolBootstrapParams protocolParams) {

        try {

            var targetAddress = new Address(request.targetAddress());

            var adminUtxos = accountService.findAdaOnlyUtxoByPaymentPubKeyHash(context.getBlacklistManagerPkh(), 10_000_000L);
            log.info("admin utxos size: {}", adminUtxos.size());
            var adminAdaBalance = adminUtxos.stream()
                    .flatMap(utxo -> utxo.getAmount().stream())
                    .map(Amount::getQuantity)
                    .reduce(BigInteger::add)
                    .orElse(ZERO);
            log.info("admin ada balance: {}", adminAdaBalance);

            var blackListMintValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "blacklist_mint.blacklist_mint.mint");
            var blackListMintValidator = blackListMintValidatorOpt.get();

            var serialisedTxInput = PlutusSerializationHelper.serialize(TransactionInput.builder()
                    .transactionId(context.getBlacklistInitTxInput().getTransactionId())
                    .index(context.getBlacklistInitTxInput().getIndex())
                    .build());

            var blacklistMintInitParams = ListPlutusData.of(serialisedTxInput,
                    BytesPlutusData.of(HexUtil.decodeHexString(context.getIssuerAdminPkh()))
            );

            var parameterisedBlacklistMintingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(blacklistMintInitParams, blackListMintValidator.scriptBytes()),
                    PlutusVersion.v3
            );

            var blacklistSpendValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID, "blacklist_spend.blacklist_spend.spend");
            var blacklistSpendValidator = blacklistSpendValidatorOpt.get();

            var blacklistSpendInitParams = ListPlutusData.of(BytesPlutusData.of(HexUtil.decodeHexString(parameterisedBlacklistMintingScript.getPolicyId())));
            var parameterisedBlacklistSpendingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                    AikenScriptUtil.applyParamToScript(blacklistSpendInitParams, blacklistSpendValidator.scriptBytes()),
                    PlutusVersion.v3
            );
            log.info("parameterisedBlacklistSpendingScript: {}", parameterisedBlacklistSpendingScript.getPolicyId());

            var blacklistSpendAddress = AddressProvider.getEntAddress(parameterisedBlacklistSpendingScript, network.getCardanoNetwork());
            log.info("blacklistSpend: {}", blacklistSpendAddress.getAddress());

            var blacklistUtxos = utxoProvider.findUtxos(blacklistSpendAddress.getAddress());
            log.info("blacklistUtxos: {}", blacklistUtxos.size());
            blacklistUtxos.forEach(utxo -> log.info("bl utxo: {}", utxo));

            var credentialsToRemove = targetAddress.getDelegationCredentialHash().map(HexUtil::encodeHexString).get();

            var blocklistNodeToRemoveOpt = blacklistUtxos.stream()
                    .flatMap(utxo -> blacklistNodeParser.parse(utxo.getInlineDatum())
                            .stream()
                            .flatMap(blacklistNode -> Stream.of(new Pair<>(utxo, blacklistNode))))
                    .filter(utxoBlacklistNodePair -> {
                        var datum = utxoBlacklistNodePair.second();
                        return datum.key().equals(credentialsToRemove);
                    })
                    .findAny();

            var blocklistNodeToUpdateOpt = blacklistUtxos.stream()
                    .flatMap(utxo -> blacklistNodeParser.parse(utxo.getInlineDatum())
                            .stream()
                            .flatMap(blacklistNode -> Stream.of(new Pair<>(utxo, blacklistNode))))
                    .filter(utxoBlacklistNodePair -> {
                        var datum = utxoBlacklistNodePair.second();
                        return datum.next().equals(credentialsToRemove);
                    })
                    .findAny();

            if (blocklistNodeToRemoveOpt.isEmpty() || blocklistNodeToUpdateOpt.isEmpty()) {
                return TransactionContext.typedError("could not resolve relevant blacklist nodes");
            }

            var blocklistNodeToRemove = blocklistNodeToRemoveOpt.get();
            log.info("blocklistNodeToRemove: {}", blocklistNodeToRemove);

            var blocklistNodeToUpdate = blocklistNodeToUpdateOpt.get();
            log.info("blocklistNodeToUpdate: {}", blocklistNodeToUpdate);

            var newNext = blocklistNodeToRemove.second().next();
            var updatedNode = blocklistNodeToUpdate.second().toBuilder().next(newNext).build();

            var mintRedeemer = ConstrPlutusData.of(2, BytesPlutusData.of(HexUtil.decodeHexString(credentialsToRemove)));

            // Before/Updated
            var preExistingAmount = blocklistNodeToUpdate.first().getAmount();

            var tx = new ScriptTx()
                    .collectFrom(adminUtxos)
                    .collectFrom(blocklistNodeToRemove.first(), ConstrPlutusData.of(0))
                    .collectFrom(blocklistNodeToUpdate.first(), ConstrPlutusData.of(0))
                    .mintAsset(parameterisedBlacklistMintingScript, Asset.builder().name("0x" + credentialsToRemove).value(ONE.negate()).build(), mintRedeemer)
                    // Replaced
                    .payToContract(blacklistSpendAddress.getAddress(), preExistingAmount, updatedNode.toPlutusData())
                    .attachSpendingValidator(parameterisedBlacklistSpendingScript)
                    .withChangeAddress(request.feePayerAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(HexUtil.decodeHexString(context.getBlacklistManagerPkh()))
                    .feePayer(request.feePayerAddress())
//                    .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                    .mergeOutputs(false)
                    .build();

            log.info("transaction: {}", transaction.serializeToHex());
            log.info("transaction: {}", objectMapper.writeValueAsString(transaction));

            return TransactionContext.ok(transaction.serializeToHex());
            
        } catch (Exception e) {
            return TransactionContext.error(String.format("error: %s", e.getMessage()));

        }

    }

    // ========== Seizeable Implementation ==========

    @Override
    public TransactionContext<Void> buildSeizeTransaction(
            SeizeRequest request,
            ProtocolBootstrapParams protocolParams) {
        // TODO: Implement seize
        // 1. Verify target is on blacklist (via reference input)
        // 2. Spend the target UTxO using ThirdPartyAct redeemer
        // 3. Send seized assets to destination
        log.warn("buildSeizeTransaction not yet implemented");
        return TransactionContext.typedError("Not yet implemented");
    }

    @Override
    public TransactionContext<Void> buildMultiSeizeTransaction(
            MultiSeizeRequest request,
            ProtocolBootstrapParams protocolParams) {
        // TODO: Implement multi-seize for efficiency
        // Similar to single seize but processes multiple UTxOs
        log.warn("buildMultiSeizeTransaction not yet implemented");
        return TransactionContext.typedError("Not yet implemented");
    }

}
