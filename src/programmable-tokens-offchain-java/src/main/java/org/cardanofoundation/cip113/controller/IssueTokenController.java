package org.cardanofoundation.cip113.controller;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
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
import com.easy1staking.cardano.util.UtxoUtil;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.onchain.RegistryNode;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import jakarta.validation.Valid;

import java.math.BigInteger;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

/**
 * REST controller for CIP-0113 programmable token issuance operations.
 *
 * <p>This controller provides endpoints for registering new programmable token policies
 * and minting tokens under registered policies. It handles the complex transaction
 * construction required by the CIP-0113 protocol, including:</p>
 *
 * <ul>
 *   <li>Registry operations (inserting new token policies into the sorted linked list)</li>
 *   <li>Script parameterization (applying protocol parameters to validator scripts)</li>
 *   <li>UTxO selection and management</li>
 *   <li>Witness construction (script references, redeemers, datums)</li>
 * </ul>
 *
 * <h2>API Base Path</h2>
 * <p>All endpoints are prefixed with {@code ${apiPrefix}/issue-token}, typically
 * {@code /api/v1/issue-token}.</p>
 *
 * <h2>Multi-Protocol Version Support</h2>
 * <p>All endpoints accept an optional {@code protocolTxHash} query parameter to specify
 * which protocol version to use. If not provided, the default version is used.</p>
 *
 * <h2>Response Format</h2>
 * <p>Successful responses return unsigned transaction CBOR as plain text. The client
 * is responsible for signing with a wallet (e.g., Mesh SDK) and submitting to the network.</p>
 *
 * <h2>Error Handling</h2>
 * <p>Errors are handled by {@link org.cardanofoundation.cip113.exception.GlobalExceptionHandler}
 * and return structured JSON responses with status codes:</p>
 * <ul>
 *   <li>400 Bad Request - Invalid input (validation errors)</li>
 *   <li>404 Not Found - Token or protocol version not found</li>
 *   <li>500 Internal Server Error - Transaction construction failed</li>
 * </ul>
 *
 * @see RegisterTokenRequest
 * @see MintTokenRequest
 * @see org.cardanofoundation.cip113.service.ProtocolBootstrapService
 */
@RestController
@RequestMapping("${apiPrefix}/issue-token")
@RequiredArgsConstructor
@Slf4j
public class IssueTokenController {

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
     * Register a new programmable token policy in the on-chain registry.
     *
     * <p>This endpoint creates a transaction that:</p>
     * <ol>
     *   <li>Mints a registry NFT with the new policy ID as the token name</li>
     *   <li>Creates a registry node UTxO with the validator triple (issue/transfer/third-party)</li>
     *   <li>Inserts the node into the sorted linked list between appropriate neighbors</li>
     *   <li>Optionally mints initial tokens to the registrar's programmable address</li>
     * </ol>
     *
     * <h3>Registry Insertion Algorithm</h3>
     * <p>The registry is a sorted linked list. To insert a new node with key K:</p>
     * <ol>
     *   <li>Find node N where N.key &lt; K &lt; N.next</li>
     *   <li>Update N.next to K</li>
     *   <li>Set new node's next to N's old next value</li>
     * </ol>
     *
     * <h3>Transaction Structure</h3>
     * <pre>
     * Inputs:
     *   - Predecessor registry node (for linked list update)
     *   - User's UTxO (for fees and collateral)
     *
     * Outputs:
     *   - Updated predecessor node (with next pointing to new node)
     *   - New registry node (with validator triple)
     *   - Programmable UTxO with initial tokens (if quantity > 0)
     *
     * Mints:
     *   - 1 registry NFT (token name = policy ID)
     *   - Initial tokens (if quantity > 0)
     *
     * Reference Inputs:
     *   - Protocol parameters UTxO
     *
     * Scripts:
     *   - Registry mint validator
     *   - Registry spend validator
     *   - Programmable token minting policy
     *   - Issue logic validator
     * </pre>
     *
     * @param registerTokenRequest the registration request containing validator selection
     *                             and initial minting parameters
     * @param protocolTxHash optional protocol version; uses default if not specified
     * @return ResponseEntity containing unsigned transaction CBOR (200 OK) or error
     */
    @PostMapping("/register")
    public ResponseEntity<?> register(
            @Valid @RequestBody RegisterTokenRequest registerTokenRequest,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("registerTokenRequest: {}, protocolTxHash: {}", registerTokenRequest, protocolTxHash);

        try {

            var protocolBootstrapParams = protocolTxHash != null && !protocolTxHash.isEmpty()
                    ? protocolBootstrapService.getProtocolBootstrapParamsByTxHash(protocolTxHash)
                            .orElseThrow(() -> new IllegalArgumentException("Protocol version not found: " + protocolTxHash))
                    : protocolBootstrapService.getProtocolBootstrapParams();

            var protocolParamsScriptHash = protocolBootstrapParams.protocolParams().scriptHash();

            var bootstrapTxHash = protocolBootstrapParams.txHash();

            var protocolParamsUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(bootstrapTxHash)
                    .outputIndex(0)
                    .build());
            if (protocolParamsUtxoOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve protocol params");
            }

            var protocolParamsUtxo = protocolParamsUtxoOpt.get();
            log.info("protocolParamsUtxo: {}", protocolParamsUtxo);
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


            var issuanceUtxoOpt = utxoRepository.findById(UtxoId.builder().txHash(bootstrapTxHash).outputIndex(2).build());
            if (issuanceUtxoOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve issuance params");
            }
            var issuanceUtxo = issuanceUtxoOpt.get();
            log.info("issuanceUtxo: {}", issuanceUtxo);

            var issuanceDatum = issuanceUtxo.getInlineDatum();
            var issuanceData = PlutusData.deserialize(HexUtil.decodeHexString(issuanceDatum));
            var issuance = objectMapper.writeValueAsString(issuanceData);
            log.info("issuance: {}", issuance);

            var programmableLogicBaseScriptHash = protocolBootstrapParams.programmableLogicBaseParams().scriptHash();

            var rigistrarUtxosOpt = utxoRepository.findUnspentByOwnerAddr(registerTokenRequest.registrarAddress(), Pageable.unpaged());
            if (rigistrarUtxosOpt.isEmpty()) {
                return ResponseEntity.badRequest().body("issuer wallet is empty");
            }
            var registrarUtxos = rigistrarUtxosOpt.get().stream().map(UtxoUtil::toUtxo).toList();

            var substandardIssuanceContractOpt = substandardService.getSubstandardValidator(registerTokenRequest.substandardName(), registerTokenRequest.substandardIssueContractName());
            var substandardTransferContractOpt = substandardService.getSubstandardValidator(registerTokenRequest.substandardName(), registerTokenRequest.substandardTransferContractName());

            var thirdPartyScriptHash = Optional.ofNullable(registerTokenRequest.substandardName())
                    .flatMap(substandardName -> substandardService.getSubstandardValidator(registerTokenRequest.substandardName(), substandardName))
                    .map(SubstandardValidator::scriptHash)
                    .orElse("");

            if (substandardIssuanceContractOpt.isEmpty() || substandardTransferContractOpt.isEmpty()) {
                log.warn("substandard issuance or transfer contract are empty");
                return ResponseEntity.badRequest().body("substandard issuance or transfer contract are empty");
            }

            var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardIssuanceContractOpt.get().scriptBytes(), PlutusVersion.v3);
            log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

            var substandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardTransferContractOpt.get().scriptBytes(), PlutusVersion.v3);


            // Issuance Parameterization
            var issuanceParameters = ListPlutusData.of(
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(HexUtil.decodeHexString(programmableLogicBaseScriptHash))
                    ),
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(substandardIssueContract.getScriptHash())
                    )
            );

            var issuanceMintOpt = protocolBootstrapService.getProtocolContract("issuance_mint.issuance_mint.mint");
            if (issuanceMintOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not find issuance mint contract");
            }

            var issuanceContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(issuanceParameters, issuanceMintOpt.get()), PlutusVersion.v3);
            final var progTokenPolicyId = issuanceContract.getPolicyId();
            log.info("issuanceContract: {}", progTokenPolicyId);

            var registryEntries = utxoRepository.findUnspentByOwnerPaymentCredential(directorySpendContract.getPolicyId(), Pageable.unpaged());
            registryEntries.stream()
                    .flatMap(Collection::stream)
                    .forEach(addressUtxoEntity -> {
                        var registryDatum = registryNodeParser.parse(addressUtxoEntity.getInlineDatum());
                        log.info("registryDatum: {}", registryDatum);
                    });

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
                    return ResponseEntity.internalServerError().body("could not find node to replace");
                }

                var directoryUtxo = UtxoUtil.toUtxo(nodeToReplaceOpt.get());
                log.info("directoryUtxo: {}", directoryUtxo);
                var existingRegistryNodeDatumOpt = registryNodeParser.parse(directoryUtxo.getInlineDatum());

                if (existingRegistryNodeDatumOpt.isEmpty()) {
                    return ResponseEntity.internalServerError().body("could not parse current registry node");
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

                var directorySpendNft = Asset.builder()
                        .name("0x")
                        .value(BigInteger.ONE)
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
                        .name("0x" + registerTokenRequest.assetName())
                        .value(new BigInteger(registerTokenRequest.quantity()))
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

                var payee = registerTokenRequest.recipientAddress() == null || registerTokenRequest.recipientAddress().isBlank() ? registerTokenRequest.registrarAddress() : registerTokenRequest.recipientAddress();
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
                        .withChangeAddress(registerTokenRequest.registrarAddress());

                var transaction = quickTxBuilder.compose(tx)
//                    .withSigner(SignerProviders.signerFrom(adminAccount))
//                    .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                        .feePayer(registerTokenRequest.registrarAddress())
                        .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                        .preBalanceTx((txBuilderContext, transaction1) -> {
                            var outputs = transaction1.getBody().getOutputs();
                            if (outputs.getFirst().getAddress().equals(registerTokenRequest.registrarAddress())) {
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


                return ResponseEntity.ok(new RegisterTokenResponse(progTokenPolicyId, transaction.serializeToHex()));
            } else {

                return ResponseEntity.badRequest().body(String.format("Token policy %s already registered", progTokenPolicyId));
            }


        } catch (Exception e) {
            log.warn("error", e);
            return ResponseEntity.internalServerError().build();
        }
    }


    /**
     * Mint additional tokens for an already-registered programmable token policy.
     *
     * <p>This endpoint creates a transaction that mints new tokens under an existing
     * registered policy. Unlike registration, this does not modify the registry - it
     * only mints tokens according to the policy's registered issuance logic.</p>
     *
     * <h3>Prerequisites</h3>
     * <ul>
     *   <li>The token policy must already be registered via {@link #register}</li>
     *   <li>The issuer must satisfy the issuance logic requirements (e.g., be the
     *       registered owner for permissioned tokens)</li>
     * </ul>
     *
     * <h3>Transaction Structure</h3>
     * <pre>
     * Inputs:
     *   - Issuer's UTxOs (for fees and collateral)
     *
     * Outputs:
     *   - Programmable UTxO at recipient's programmable address with minted tokens
     *   - Change output to issuer
     *
     * Mints:
     *   - Requested quantity of tokens under the registered policy
     *
     * Reference Inputs:
     *   - Protocol parameters UTxO
     *   - Registry node for this policy (to verify registration and get issue logic)
     *
     * Scripts:
     *   - Programmable token minting policy (parameterized)
     *   - Issue logic validator (from substandard, invoked via stake credential)
     * </pre>
     *
     * <h3>Issuance Logic</h3>
     * <p>The transaction invokes the registered issuance logic validator via the
     * withdraw-zero pattern. The validator receives:</p>
     * <ul>
     *   <li>The minting context (policy ID, asset name, quantity)</li>
     *   <li>The issuer's credentials</li>
     *   <li>The registry entry for verification</li>
     * </ul>
     *
     * @param mintTokenRequest the mint request containing token and quantity details
     * @param protocolTxHash optional protocol version; uses default if not specified
     * @return ResponseEntity containing unsigned transaction CBOR (200 OK) or error
     */
    @PostMapping("/mint")
    public ResponseEntity<?> mint(
            @Valid @RequestBody MintTokenRequest mintTokenRequest,
            @RequestParam(required = false) String protocolTxHash) {

        try {

            var protocolBootstrapParams = protocolTxHash != null && !protocolTxHash.isEmpty()
                    ? protocolBootstrapService.getProtocolBootstrapParamsByTxHash(protocolTxHash)
                            .orElseThrow(() -> new IllegalArgumentException("Protocol version not found: " + protocolTxHash))
                    : protocolBootstrapService.getProtocolBootstrapParams();

            var bootstrapTxHash = protocolBootstrapParams.txHash();

            // Protocol params UTxO is at output index 0 of the bootstrap transaction
            // This contains the ProgrammableLogicGlobalParams datum
            var protocolParamsUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(bootstrapTxHash)
                    .outputIndex(0)
                    .build());
            if (protocolParamsUtxoOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve protocol params");
            }

            var protocolParamsUtxo = protocolParamsUtxoOpt.get();
            log.info("protocolParamsUtxo: {}", protocolParamsUtxo);

            var issuanceUtxoOpt = utxoRepository.findById(UtxoId.builder().txHash(bootstrapTxHash).outputIndex(2).build());
            if (issuanceUtxoOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve issuance params");
            }
            var issuanceUtxo = issuanceUtxoOpt.get();
            log.info("issuanceUtxo: {}", issuanceUtxo);

            var issuanceDatum = issuanceUtxo.getInlineDatum();
            var issuanceData = PlutusData.deserialize(HexUtil.decodeHexString(issuanceDatum));
            var issuance = objectMapper.writeValueAsString(issuanceData);
            log.info("issuance: {}", issuance);

            var programmableLogicBaseScriptHash = protocolBootstrapParams.programmableLogicBaseParams().scriptHash();

            var issuerUtxosOpt = utxoRepository.findUnspentByOwnerAddr(mintTokenRequest.issuerBaseAddress(), Pageable.unpaged());
            if (issuerUtxosOpt.isEmpty()) {
                return ResponseEntity.badRequest().body("issuer wallet is empty");
            }
            var issuerUtxos = issuerUtxosOpt.get().stream().map(UtxoUtil::toUtxo).toList();

            var substandardIssuanceContractOpt = substandardService.getSubstandardValidator(mintTokenRequest.substandardName(), mintTokenRequest.substandardIssueContractName());

            var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardIssuanceContractOpt.get().scriptBytes(), PlutusVersion.v3);
            log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

            // Issuance Parameterization
            var issuanceParameters = ListPlutusData.of(
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(HexUtil.decodeHexString(programmableLogicBaseScriptHash))
                    ),
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(substandardIssueContract.getScriptHash())
                    )
            );

            var issuanceMintOpt = protocolBootstrapService.getProtocolContract("issuance_mint.issuance_mint.mint");
            if (issuanceMintOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not find issuance mint contract");
            }

            var issuanceContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(issuanceParameters, issuanceMintOpt.get()), PlutusVersion.v3);
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
                    .orElse(mintTokenRequest.issuerBaseAddress());

            var recipientAddress = new Address(recipient);

            var targetAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                    recipientAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            var tx = new ScriptTx()
                    .collectFrom(issuerUtxos)
                    .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, BigIntPlutusData.of(100))
                    // Redeemer is DirectoryInit (constr(0))
                    .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                    .payToContract(targetAddress.getAddress(), ValueUtil.toAmountList(progammableTokenValue), ConstrPlutusData.of(0))
                    .attachRewardValidator(substandardIssueContract)
                    .withChangeAddress(mintTokenRequest.issuerBaseAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .feePayer(mintTokenRequest.issuerBaseAddress())
                    .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                    .preBalanceTx((txBuilderContext, transaction1) -> {
                        var outputs = transaction1.getBody().getOutputs();
                        if (outputs.getFirst().getAddress().equals(mintTokenRequest.issuerBaseAddress())) {
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

            return ResponseEntity.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.warn("error", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }


}
