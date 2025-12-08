package org.cardanofoundation.cip113.service.substandard;

import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BigIntPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.plutus.spec.PlutusScript;
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
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.model.MintTokenRequest;
import org.cardanofoundation.cip113.model.RegisterTokenRequest;
import org.cardanofoundation.cip113.model.TransactionContext;
import org.cardanofoundation.cip113.model.TransferTokenRequest;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.service.ProtocolScriptBuilderService;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;

import java.math.BigInteger;
import java.util.Collection;
import java.util.List;
import java.util.Set;

/**
 * Handler for the "dummy" programmable token substandard.
 * This is a simple reference implementation with basic issue and transfer validators.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class DummySubstandardHandler implements SubstandardHandler {

    private final ObjectMapper objectMapper;

    private final AppConfig.Network network;

    private final UtxoRepository utxoRepository;

    private final RegistryNodeParser registryNodeParser;

    private final SubstandardService substandardService;

    private final ProtocolScriptBuilderService protocolScriptBuilderService;

    private final QuickTxBuilder quickTxBuilder;

    @Override
    public String getSubstandardId() {
        return "dummy";
    }

    @Override
    public TransactionContext buildRegistrationTransaction(
            RegisterTokenRequest request,
            ProtocolBootstrapParams protocolParams,
            ProtocolScriptBuilderService protocolScriptBuilder) {
        // TODO: Migrate registration logic from IssueTokenController.register()
        // This will involve:
        // 1. Getting directory mint/spend scripts from protocolScriptBuilder
        // 2. Getting issue/transfer validators from getParameterizedIssueValidator/getParameterizedTransferValidator
        // 3. Building issuance mint script with protocolScriptBuilder.getParameterizedIssuanceMintScript()
        // 4. Constructing the transaction with registry node creation
        // 5. Returning TransactionContext with unsigned CBOR tx
        throw new UnsupportedOperationException("Registration transaction building not yet implemented - to be migrated from IssueTokenController");
    }

    @Override
    public TransactionContext buildMintTransaction(
            MintTokenRequest request,
            ProtocolBootstrapParams protocolParams,
            ProtocolScriptBuilderService protocolScriptBuilder
    ) {
        // TODO: Migrate minting logic from IssueTokenController.mint()
        // This will involve:
        // 1. Finding registry entry for the policy ID
        // 2. Getting parameterized scripts
        // 3. Building mint transaction with proper redeemers
        // 4. Returning TransactionContext with unsigned CBOR tx
        throw new UnsupportedOperationException("Mint transaction building not yet implemented - to be migrated from IssueTokenController");
    }

    @Override
    public TransactionContext buildTransferTransaction(
            TransferTokenRequest transferTokenRequest,
            ProtocolBootstrapParams protocolBootstrapParams,
            ProtocolScriptBuilderService protocolScriptBuilder) {

        var assetType = AssetType.fromUnit(transferTokenRequest.unit());

        try {

            var bootstrapTxHash = protocolBootstrapParams.txHash();

            var progToken = AssetType.fromUnit(transferTokenRequest.unit());

            // Directory SPEND parameterization
            var directorySpendContract = protocolScriptBuilderService.getParameterizedDirectorySpendScript(protocolBootstrapParams);
            log.info("directorySpendContract: {}", HexUtil.encodeHexString(directorySpendContract.getScriptHash()));

            var registryEntries = utxoRepository.findUnspentByOwnerPaymentCredential(directorySpendContract.getPolicyId(), Pageable.unpaged());

            var progTokenRegistryOpt = registryEntries.stream()
                    .flatMap(Collection::stream)
                    .filter(addressUtxoEntity -> {
                        var registryDatumOpt = registryNodeParser.parse(addressUtxoEntity.getInlineDatum());
                        return registryDatumOpt.map(registryDatum -> registryDatum.key().equals(assetType.policyId())).orElse(false);
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

            var senderProgTokensValue = senderProgTokensUtxos.getFirst().toValue();

            var progTokenAmount = senderProgTokensValue.amountOf(assetType.policyId(), "0x" + assetType.assetName());

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
            var returningValue = senderProgTokensValue.subtract(assetType.policyId(), "0x" + assetType.assetName(), new BigInteger(transferTokenRequest.quantity()));

            var tokenAsset2 = Asset.builder()
                    .name("0x" + assetType.assetName())
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

            var tx = new ScriptTx()
                    .collectFrom(senderUtxos)
                    .collectFrom(senderProgTokensUtxos.getFirst(), ConstrPlutusData.of(0))
                    // must be first Provide proofs
                    .withdraw(substandardTransferAddress.getAddress(), BigInteger.ZERO, BigIntPlutusData.of(200))
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

    @Override
    public Set<String> getRequiredValidators() {
        // Dummy substandard has 2 validators: issue and transfer
        return Set.of("issue_validator", "transfer_validator");
    }

    @Override
    public PlutusScript getParameterizedIssueValidator(String contractName, Object... params) {
        // Dummy validators are NOT parameterized - they are simple reference implementations
        var validatorOpt = substandardService.getSubstandardValidator(getSubstandardId(), contractName);

        if (validatorOpt.isEmpty()) {
            throw new IllegalArgumentException("Validator not found: " + contractName);
        }

        var validator = validatorOpt.get();
        var script = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                validator.scriptBytes(),
                PlutusVersion.v3
        );

        try {
            log.debug("Retrieved dummy issue validator '{}' with script hash: {}", contractName, script.getPolicyId());
        } catch (Exception e) {
            log.debug("Retrieved dummy issue validator '{}' (could not compute policy ID)", contractName);
        }
        return script;
    }

    @Override
    public PlutusScript getParameterizedTransferValidator(String contractName, Object... params) {
        // Dummy validators are NOT parameterized - they are simple reference implementations
        var validatorOpt = substandardService.getSubstandardValidator(getSubstandardId(), contractName);

        if (validatorOpt.isEmpty()) {
            throw new IllegalArgumentException("Validator not found: " + contractName);
        }

        var validator = validatorOpt.get();
        var script = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                validator.scriptBytes(),
                PlutusVersion.v3
        );

        try {
            log.debug("Retrieved dummy transfer validator '{}' with script hash: {}", contractName, script.getPolicyId());
        } catch (Exception e) {
            log.debug("Retrieved dummy transfer validator '{}' (could not compute policy ID)", contractName);
        }
        return script;
    }

    @Override
    public PlutusScript getParameterizedThirdPartyValidator(String contractName, Object... params) {
        // Dummy substandard doesn't have third-party validators
        throw new UnsupportedOperationException("Dummy substandard does not have third-party validators");
    }
}
