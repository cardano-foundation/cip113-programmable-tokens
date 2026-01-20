package org.cardanofoundation.cip113.service.substandard;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.util.ValueUtil;
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
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.entity.BlacklistInitEntity;
import org.cardanofoundation.cip113.model.MintTokenRequest;
import org.cardanofoundation.cip113.model.RegisterTokenRequest;
import org.cardanofoundation.cip113.model.TransactionContext;
import org.cardanofoundation.cip113.model.TransactionContext.MintingResult;
import org.cardanofoundation.cip113.model.TransactionContext.RegistrationResult;
import org.cardanofoundation.cip113.model.TransferTokenRequest;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.model.bootstrap.TxInput;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistBootstrap;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistMintBootstrap;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistNode;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistSpendBootstrap;
import org.cardanofoundation.cip113.repository.BlacklistInitRepository;
import org.cardanofoundation.cip113.service.AccountService;
import org.cardanofoundation.cip113.service.ProtocolScriptBuilderService;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.cardanofoundation.cip113.service.UtxoProvider;
import org.cardanofoundation.cip113.service.substandard.capabilities.BasicOperations;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable;
import org.cardanofoundation.cip113.service.substandard.context.FreezeAndSeizeContext;
import org.cardanofoundation.cip113.util.PlutusSerializationHelper;
import org.springframework.context.annotation.Scope;
import org.springframework.stereotype.Component;

import java.math.BigInteger;
import java.util.List;

import static java.math.BigInteger.ONE;
import static java.math.BigInteger.ZERO;

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
public class FreezeAndSeizeHandler implements SubstandardHandler, BasicOperations, BlacklistManageable, Seizeable {

    private static final String SUBSTANDARD_ID = "freeze-and-seize";

    private final ObjectMapper objectMapper;
    private final AppConfig.Network network;
    private final UtxoRepository utxoRepository;
    private final RegistryNodeParser registryNodeParser;
    private final AccountService accountService;
    private final SubstandardService substandardService;
    private final ProtocolScriptBuilderService protocolScriptBuilderService;
    private final QuickTxBuilder quickTxBuilder;

    private final BlacklistInitRepository blacklistInitRepository;

    private final UtxoProvider utxoProvider;

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
            RegisterTokenRequest request,
            ProtocolBootstrapParams protocolParams) {
        // TODO: Implement registration for freeze-and-seize
        // Similar to dummy but with freeze-and-seize validators
        log.warn("buildRegistrationTransaction not yet implemented for freeze-and-seize");
        return TransactionContext.typedError("Not yet implemented");
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
    public TransactionContext<Void> buildAddToBlacklistTransaction(
            AddToBlacklistRequest request,
            ProtocolBootstrapParams protocolParams) {
        // TODO: Implement add to blacklist (freeze)
        // 1. Find the covering node in the blacklist linked list
        // 2. Insert new node with target credential
        // 3. Update covering node's 'next' pointer
        log.warn("buildAddToBlacklistTransaction not yet implemented");
        return TransactionContext.typedError("Not yet implemented");
    }

    @Override
    public TransactionContext<Void> buildRemoveFromBlacklistTransaction(
            RemoveFromBlacklistRequest request,
            ProtocolBootstrapParams protocolParams) {
        // TODO: Implement remove from blacklist (unfreeze)
        // 1. Find the node to remove
        // 2. Find the previous node
        // 3. Update previous node's 'next' to skip removed node
        // 4. Burn the removed node's NFT
        log.warn("buildRemoveFromBlacklistTransaction not yet implemented");
        return TransactionContext.typedError("Not yet implemented");
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
