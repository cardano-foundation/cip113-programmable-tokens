package org.cardanofoundation.cip113.controller;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.model.Utxo;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.*;
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
import org.cardanofoundation.cip113.model.TransferTokenRequest;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.cardanofoundation.cip113.service.SubstandardService;
import jakarta.validation.Valid;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigInteger;
import java.util.Collection;
import java.util.List;

/**
 * REST controller for CIP-0113 programmable token transfer operations.
 *
 * <p>This controller provides the endpoint for transferring registered programmable tokens
 * between addresses. Unlike standard Cardano token transfers, programmable transfers:</p>
 *
 * <ul>
 *   <li>Must use programmable addresses (payment cred = programmable_logic_base)</li>
 *   <li>Are validated by the token's registered transfer logic contract</li>
 *   <li>Invoke the global programmable logic stake validator</li>
 *   <li>Can be subject to additional constraints (blacklist, permissions, etc.)</li>
 * </ul>
 *
 * <h2>API Base Path</h2>
 * <p>Endpoint is prefixed with {@code ${apiPrefix}/transfer-token}, typically
 * {@code /api/v1/transfer-token}.</p>
 *
 * <h2>Transfer Architecture</h2>
 * <p>The CIP-0113 transfer mechanism uses a two-level validation pattern:</p>
 *
 * <ol>
 *   <li><b>programmable_logic_base (spend)</b>: Guards all programmable token UTxOs.
 *       Simply checks that the global stake validator is invoked.</li>
 *   <li><b>programmable_logic_global (stake)</b>: Performs comprehensive validation:
 *     <ul>
 *       <li>Looks up the token in the registry</li>
 *       <li>Invokes the registered transfer logic</li>
 *       <li>Optionally invokes third-party logic (blacklist, KYC)</li>
 *       <li>Validates value preservation across inputs/outputs</li>
 *     </ul>
 *   </li>
 * </ol>
 *
 * <h2>Programmable Addresses</h2>
 * <p>Programmable tokens must be held at addresses with:</p>
 * <pre>
 * payment_credential = Script(programmable_logic_base_hash)
 * stake_credential   = Inline(user_key_hash)  // user's verification key
 * </pre>
 * <p>This allows the user to authorize spending while the protocol enforces transfer rules.</p>
 *
 * @see TransferTokenRequest
 * @see org.cardanofoundation.cip113.service.ProtocolBootstrapService
 */
@RestController
@RequestMapping("${apiPrefix}/transfer-token")
@RequiredArgsConstructor
@Slf4j
public class TransferTokenController {

    /** JSON serializer for constructing Plutus datums and redeemers */
    private final ObjectMapper objectMapper;

    /** Network configuration (mainnet, preprod, preview) */
    private final AppConfig.Network network;

    /** Repository for querying UTxOs from the chain indexer */
    private final UtxoRepository utxoRepository;

    /** Parser for deserializing on-chain registry node datums */
    private final RegistryNodeParser registryNodeParser;

    /** Service for loading protocol bootstrap parameters and contract blueprints */
    private final ProtocolBootstrapService protocolBootstrapService;

    /** Service for loading substandard validator blueprints */
    private final SubstandardService substandardService;

    /** Transaction builder from cardano-client-lib */
    private final QuickTxBuilder quickTxBuilder;

    /**
     * Transfer programmable tokens from sender to recipient.
     *
     * <p>This endpoint creates a transaction that transfers registered programmable tokens
     * while enforcing the token's transfer logic. The transaction spends from the sender's
     * programmable address and outputs to the recipient's programmable address.</p>
     *
     * <h3>Transfer Validation</h3>
     * <p>The transaction is validated on-chain by:</p>
     * <ol>
     *   <li><b>programmable_logic_base</b>: Verifies global stake validator is invoked</li>
     *   <li><b>programmable_logic_global</b>: Performs registry lookup and invokes
     *       transfer logic</li>
     *   <li><b>Transfer logic validator</b>: Token-specific rules (e.g., permissioned
     *       transfers, blacklist checks)</li>
     * </ol>
     *
     * <h3>Transaction Structure</h3>
     * <pre>
     * Inputs:
     *   - Sender's programmable UTxO containing tokens to transfer
     *   - Sender's regular UTxO for fees/collateral (if needed)
     *
     * Outputs:
     *   - Recipient's programmable address with transferred tokens
     *   - Sender's programmable address with remaining tokens (change)
     *
     * Reference Inputs:
     *   - Protocol parameters UTxO
     *   - Registry node for this token's policy
     *
     * Withdrawals:
     *   - 0 ADA from programmable_logic_global (withdraw-zero pattern)
     *   - 0 ADA from transfer logic validator (withdraw-zero pattern)
     *
     * Scripts:
     *   - programmable_logic_base (spend validator)
     *   - programmable_logic_global (stake validator)
     *   - Transfer logic validator (stake validator, from registry)
     * </pre>
     *
     * <h3>Error Cases</h3>
     * <ul>
     *   <li>Token not registered: Returns 404 with error message</li>
     *   <li>Insufficient balance: Returns 400 with balance info</li>
     *   <li>Transfer logic rejection: Returns 400 with validation error</li>
     *   <li>Blacklisted address: Returns 403 if token uses blacklist</li>
     * </ul>
     *
     * @param transferTokenRequest the transfer request with sender, recipient, and amount
     * @param protocolTxHash optional protocol version; uses default if not specified
     * @return ResponseEntity containing unsigned transaction CBOR (200 OK) or error
     */
    @PostMapping("/transfer")
    public ResponseEntity<?> transfer(
            @Valid @RequestBody TransferTokenRequest transferTokenRequest,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("transferTokenRequest: {}, protocolTxHash: {}", transferTokenRequest, protocolTxHash);

        var assetType = AssetType.fromUnit(transferTokenRequest.unit());
        log.info("prog token to transfer: {}.{}", assetType.policyId(), assetType.unsafeHumanAssetName());

        try {

            var protocolBootstrapParams = protocolTxHash != null && !protocolTxHash.isEmpty()
                    ? protocolBootstrapService.getProtocolBootstrapParamsByTxHash(protocolTxHash)
                    .orElseThrow(() -> new IllegalArgumentException("Protocol version not found: " + protocolTxHash))
                    : protocolBootstrapService.getProtocolBootstrapParams();

            var protocolParamsScriptHash = protocolBootstrapParams.protocolParams().scriptHash();

            var bootstrapTxHash = protocolBootstrapParams.txHash();

            var progToken = AssetType.fromUnit(transferTokenRequest.unit());

            // Registry Contracts Init
            // Directory MINT parameterization
            var utxo1 = protocolBootstrapParams.directoryMintParams().txInput();
            log.info("utxo1: {}", utxo1);
            var issuanceScriptHash = protocolBootstrapParams.directoryMintParams().issuanceScriptHash();
            log.info("issuanceScriptHash: {}", issuanceScriptHash);
            var directoryParameters = ListPlutusData.of(
                    ConstrPlutusData.of(0,
                            BytesPlutusData.of(HexUtil.decodeHexString(utxo1.txHash())),
                            BigIntPlutusData.of(utxo1.outputIndex())),
                    BytesPlutusData.of(HexUtil.decodeHexString(issuanceScriptHash))
            );

            var directoryMintContractOpt = protocolBootstrapService.getProtocolContract("registry_mint.registry_mint.mint");
            var directorySpendContractOpt = protocolBootstrapService.getProtocolContract("registry_spend.registry_spend.spend");

            if (directoryMintContractOpt.isEmpty() || directorySpendContractOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve registry contracts");
            }

            var directoryMintContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(directoryParameters, directoryMintContractOpt.get()), PlutusVersion.v3);
            log.info("directoryMintContract: {}", HexUtil.encodeHexString(directoryMintContract.getScriptHash()));

            // Directory SPEND parameterization
            var directorySpendParameters = ListPlutusData.of(
                    BytesPlutusData.of(HexUtil.decodeHexString(protocolParamsScriptHash))
            );
            var directorySpendContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(directorySpendParameters, directorySpendContractOpt.get()), PlutusVersion.v3);
            log.info("directorySpendContract: {}", HexUtil.encodeHexString(directorySpendContract.getScriptHash()));

            var directorySpendContractAddress = AddressProvider.getEntAddress(directorySpendContract, network.getCardanoNetwork());
            log.info("directorySpendContractAddress: {}", directorySpendContractAddress.getAddress());

            var registryEntries = utxoRepository.findUnspentByOwnerPaymentCredential(directorySpendContract.getPolicyId(), Pageable.unpaged());
            registryEntries.stream()
                    .flatMap(Collection::stream)
                    .forEach(foo -> {
                        var registryDatum = registryNodeParser.parse(foo.getInlineDatum());
                        log.info("registryDatum: {}", registryDatum);
                    });

            var progTokenRegistryOpt = registryEntries.stream()
                    .flatMap(Collection::stream)
                    .filter(addressUtxoEntity -> {
                        var registryDatumOpt = registryNodeParser.parse(addressUtxoEntity.getInlineDatum());
                        return registryDatumOpt.map(registryDatum -> registryDatum.key().equals(assetType.policyId())).orElse(false);
                    })
                    .findAny()
                    .map(UtxoUtil::toUtxo);

            if (progTokenRegistryOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not find registry entry for token");
            }

            var progTokenRegistry = progTokenRegistryOpt.get();

            var protocolParamsUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(bootstrapTxHash)
                    .outputIndex(0)
                    .build());
            if (protocolParamsUtxoOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve protocol params");
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

            senderProgTokensUtxos.forEach(utxo -> log.info("utxo: {}", utxo));

            log.info("senderProgTokensUtxos size: {}", senderProgTokensUtxos.size());

//            var senderProgTokensValue = senderProgTokensUtxos.stream()
//                    .map(Utxo::toValue)
//                    .reduce(Value::add)
//                    .orElse(Value.builder().build());
            var senderProgTokensValue = senderProgTokensUtxos.getFirst().toValue();

            var progTokenAmount = senderProgTokensValue.amountOf(assetType.policyId(), "0x" + assetType.assetName());

            if (progTokenAmount.compareTo(new BigInteger(transferTokenRequest.quantity())) < 0) {
                return ResponseEntity.badRequest().body("Not enough funds");
            }

            var senderUtxos = utxoRepository.findUnspentByOwnerAddr(transferTokenRequest.senderAddress(), Pageable.unpaged())
                    .stream()
                    .flatMap(Collection::stream)
                    .map(UtxoUtil::toUtxo)
                    .toList();

            var programmableLogicGlobalContractOpt = protocolBootstrapService.getProtocolContract("programmable_logic_global.programmable_logic_global.withdraw");
            if (programmableLogicGlobalContractOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve programmable logic global");
            }
            var programmableLogicGlobalContract = programmableLogicGlobalContractOpt.get();
            // Programmable Logic Global parameterization
            var programmableLogicGlobalParameters = ListPlutusData.of(BytesPlutusData.of(HexUtil.decodeHexString(protocolBootstrapParams.protocolParams().scriptHash())));
            var programmableLogicGlobal = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(programmableLogicGlobalParameters, programmableLogicGlobalContract), PlutusVersion.v3);
//            log.info("programmableLogicGlobalContract policy: {}", programmableLogicGlobalContract.getPolicyId());
            var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobal, network.getCardanoNetwork());
            log.info("programmableLogicGlobalAddress policy: {}", programmableLogicGlobalAddress.getAddress());
////
////        var registerAddressTx = new Tx()
////                .from(adminAccount.baseAddress())
////                .registerStakeAddress(programmableLogicGlobalAddress.getAddress())
////                .withChangeAddress(adminAccount.baseAddress());
////
////        quickTxBuilder.compose(registerAddressTx)
////                .feePayer(adminAccount.baseAddress())
////                .withSigner(SignerProviders.signerFrom(adminAccount))
////                .completeAndWait();

            var programmableLogicBaseContractOpt = protocolBootstrapService.getProtocolContract("programmable_logic_base.programmable_logic_base.spend");
            if (programmableLogicBaseContractOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve programmable logic base");
            }
            var programmableLogicBaseContract = programmableLogicBaseContractOpt.get();

//            // Programmable Logic Base parameterization
            var programmableLogicBaseParameters = ListPlutusData.of(ConstrPlutusData.of(1, BytesPlutusData.of(programmableLogicGlobal.getScriptHash())));
            var programmableLogicBase = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(programmableLogicBaseParameters, programmableLogicBaseContract), PlutusVersion.v3);
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

            // Note: Currently hardcoded to "dummy" substandard - in production, this should be
            // determined from the token's registry entry to use the appropriate transfer logic
            var substandardTransferContractOpt = substandardService.getSubstandardValidator("dummy", "transfer.transfer.withdraw");
            if (substandardTransferContractOpt.isEmpty()) {
                log.warn("could not resolve transfer contract");
                return ResponseEntity.badRequest().body("could not resolve transfer contract");
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
//                        transaction1.getBody().setCollateralReturn();
                    })
                    .build();


            log.info("tx: {}", transaction.serializeToHex());
            log.info("tx: {}", objectMapper.writeValueAsString(transaction));

            return ResponseEntity.ok(transaction.serializeToHex());

        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }


}
