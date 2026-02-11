package org.cardanofoundation.cip113.service.substandard;

import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.model.Utxo;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.client.plutus.spec.BigIntPlutusData;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.quicktx.Tx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.bloxbean.cardano.yaci.core.model.certs.CertificateType;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.repository.UtxoRepository;
import com.easy1staking.cardano.comparator.TransactionInputComparator;
import com.easy1staking.cardano.comparator.UtxoComparator;
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
import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.TransactionContext.MintingResult;
import org.cardanofoundation.cip113.model.TransactionContext.RegistrationResult;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.model.bootstrap.TxInput;
import org.cardanofoundation.cip113.model.onchain.RegistryNode;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.*;
import org.cardanofoundation.cip113.repository.BlacklistInitRepository;
import org.cardanofoundation.cip113.repository.CustomStakeRegistrationRepository;
import org.cardanofoundation.cip113.repository.FreezeAndSeizeTokenRegistrationRepository;
import org.cardanofoundation.cip113.repository.ProgrammableTokenRegistryRepository;
import org.cardanofoundation.cip113.service.*;
import org.cardanofoundation.cip113.service.substandard.capabilities.BasicOperations;
import org.cardanofoundation.cip113.service.substandard.capabilities.BlacklistManageable;
import org.cardanofoundation.cip113.service.substandard.capabilities.Seizeable;
import org.cardanofoundation.cip113.service.substandard.context.FreezeAndSeizeContext;
import org.springframework.context.annotation.Scope;
import org.springframework.stereotype.Component;

import java.math.BigInteger;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

import static java.math.BigInteger.ONE;
import static java.math.BigInteger.ZERO;

/**
 * Handler for the "freeze-and-seize" programmable token substandard.
 *
 * <p>
 * This handler supports regulated stablecoins with compliance features:
 * </p>
 * <ul>
 * <li><b>BasicOperations</b> - Register, mint, burn, transfer programmable
 * tokens</li>
 * <li><b>BlacklistManageable</b> - Freeze/unfreeze addresses via blacklist</li>
 * <li><b>Seizeable</b> - Seize assets from blacklisted/sanctioned
 * addresses</li>
 * </ul>
 *
 * <p>
 * This handler requires a {@link FreezeAndSeizeContext} to be set before use,
 * as there can be multiple stablecoin deployments, each with their own
 * configuration.
 * </p>
 *
 * <p>
 * Use
 * {@link SubstandardHandlerFactory#getHandler(String, org.cardanofoundation.cip113.service.substandard.context.SubstandardContext)}
 * to get a properly configured instance.
 * </p>
 */
@Component
@Scope("prototype") // New instance each time for context isolation
/**
 * Handler for freeze-and-seize substandard token operations.
 * 
 * **IMPORTANT FOR MAINNET DEPLOYMENT:**
 * 
 * This handler implements the multi-token registration fix that prevents policy
 * ID collisions
 * when the same admin registers multiple tokens. The fix involves:
 * 
 * 1. **Validator Parameterization**: The `issuer_admin_contract` validator is
 * now parameterized
 * with both `adminPkh` AND `asset_name` (previously only `adminPkh`).
 * 
 * 2. **Policy ID Uniqueness**: Each token gets a unique policy ID because:
 * - Script hash = hash(adminPkh, asset_name)
 * - Policy ID = hash(programmable_logic_base, script_hash)
 * - Different asset names → different script hashes → different policy IDs
 * 
 * 3. **Asset Name Validation**: The validator enforces that minted tokens match
 * the expected
 * asset name, preventing contract reuse. Seize operations bypass this check (no
 * minting).
 * 
 * 4. **Backward Compatibility**: Existing tokens deployed with the old
 * validator (1 parameter)
 * will continue to work. New tokens use the new validator (2 parameters).
 * 
 * **Usage Notes:**
 * - Asset names must be hex-encoded (without "0x" prefix) when passed to this
 * handler
 * - The handler automatically decodes hex strings before parameterizing
 * contracts
 * - All 4 operations (pre-registration, registration, mint, seize) use the same
 * parameterization
 * 
 * **Testing**: This fix allows testing multiple tokens from the same admin
 * wallet without
 * policy ID collisions, which was previously a limitation.
 */
@RequiredArgsConstructor
@Slf4j
public class FreezeAndSeizeHandler implements SubstandardHandler, BasicOperations<FreezeAndSeizeRegisterRequest>,
                BlacklistManageable, Seizeable {

        private static final String SUBSTANDARD_ID = "freeze-and-seize";

<<<<<<< HEAD
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
=======
    private final ObjectMapper objectMapper;
    private final AppConfig.Network network;
    private final UtxoRepository utxoRepository;
    private final BlacklistNodeParser blacklistNodeParser;
    private final RegistryNodeParser registryNodeParser;
    private final AccountService accountService;
    private final SubstandardService substandardService;
    private final ProtocolScriptBuilderService protocolScriptBuilderService;
    private final FreezeAndSeizeScriptBuilderService fesScriptBuilder;
    private final LinkedListService linkedListService;
    private final QuickTxBuilder quickTxBuilder;
>>>>>>> upstream/main

        private final FreezeAndSeizeTokenRegistrationRepository freezeAndSeizeTokenRegistrationRepository;

        private final BlacklistInitRepository blacklistInitRepository;

        private final ProgrammableTokenRegistryRepository programmableTokenRegistryRepository;

        private final CustomStakeRegistrationRepository stakeRegistrationRepository;

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

        /**
         * Extract issuance prefix and postfix from the issuance UTxO datum.
         * The datum is a ConstrPlutusData with 2 fields: [prefix_bytes, postfix_bytes]
         * 
         * @param issuanceUtxo The issuance UTxO containing the prefix/postfix datum
         /**
          * @return Pair of (prefix, postfix) as byte arrays, or empty if parsing fails
          */
         private Optional<Pair<byte[], byte[]>> extractIssuancePrefixPostfix(Utxo issuanceUtxo) {
             try {
                 if (issuanceUtxo == null || issuanceUtxo.getInlineDatum() == null) {
                     log.warn("Issuance UTxO or datum is null");
                     return Optional.empty();
                 }
                        }

                        var datumHex = issuanceUtxo.getInlineDatum();
                        var datum = com.bloxbean.cardano.client.plutus.spec.PlutusData.deserialize(
                                        HexUtil.decodeHexString(datumHex));

<<<<<<< HEAD
                        if (!(datum instanceof ConstrPlutusData constrDatum)) {
                                log.warn("Issuance datum is not a ConstrPlutusData");
                                return Optional.empty();
                        }

                        // Use ObjectMapper to parse JSON structure (same approach as BlacklistNodeParser)
                        var jsonData = objectMapper.readTree(objectMapper.writeValueAsString(constrDatum));
                        var fields = jsonData.path("fields");
                        if (!fields.isArray() || fields.size() < 2) {
                                log.warn("Issuance datum does not have 2 fields");
                                return Optional.empty();
                        }

                        var prefixHex = fields.get(0).path("bytes").asText();
                        var postfixHex = fields.get(1).path("bytes").asText();

                        var prefixBytes = HexUtil.decodeHexString(prefixHex);
                        var postfixBytes = HexUtil.decodeHexString(postfixHex);

                        return Optional.of(Pair.of(prefixBytes, postfixBytes));
                }catch(

        Exception e)
        {
                log.error("Failed to extract issuance prefix/postfix from UTxO", e);
                return Optional.empty();
        }
        }

        // ========== BasicOperations Implementation ==========

        @Override
        public TransactionContext<List<String>> buildPreRegistrationTransaction(
                        FreezeAndSeizeRegisterRequest request,
                        ProtocolBootstrapParams protocolParams) {

                try {
                        var adminPkh = Credential.fromKey(request.getAdminPubKeyHash());
                        var blacklistNodePolicyId = request.getBlacklistNodePolicyId();
=======
        try {
            var adminPkh = request.getAdminPubKeyHash();
            var blacklistNodePolicyId = request.getBlacklistNodePolicyId();

            /// Getting Substandard Contracts and parameterize
            // Issuer to be used for minting/burning/sieze
            var substandardIssueContract = fesScriptBuilder.buildIssuerAdminScript(Credential.fromKey(adminPkh));
            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

            // Transfer contract
            var substandardTransferContract = fesScriptBuilder.buildTransferScript(
                    protocolParams.programmableLogicBaseParams().scriptHash(),
                    blacklistNodePolicyId
            );
            var substandardTransferAddress = AddressProvider.getRewardAddress(substandardTransferContract, network.getCardanoNetwork());
            log.info("substandardTransferAddress: {}", substandardTransferAddress.getAddress());
>>>>>>> upstream/main

                        var feePayerUtxos = accountService.findAdaOnlyUtxo(request.getFeePayerAddress(), 10_000_000L);

                        /// Getting Substandard Contracts and parameterize
                        // Issuer to be used for minting/burning/sieze
                        // NOTE: Parameterized with adminPkh, asset_name, issuance_prefix,
                        /// issuance_postfix, and programmable_base_hash
                        // This allows the same admin to register multiple tokens with unique policy IDs
                        var issuerContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "example_transfer_logic.issuer_admin_contract.withdraw");
                        if (issuerContractOpt.isEmpty()) {
                                return TransactionContext.typedError("could not find issuer contract validator");
                        }
                        var issuerContract = issuerContractOpt.get();

                        // Extract issuance prefix/postfix from issuance UTxO
                        var issuanceTxHash = protocolParams.issuanceParams().txInput().txHash();
                        var issuanceOutputIndex = protocolParams.issuanceParams().txInput().outputIndex();
                        var issuanceUtxoOpt = utxoProvider.findUtxo(issuanceTxHash, issuanceOutputIndex);
                        if (issuanceUtxoOpt.isEmpty()) {
                                return TransactionContext
                                                .typedError("could not find issuance UTxO to extract prefix/postfix");
                        }
                        var prefixPostfixOpt = extractIssuancePrefixPostfix(issuanceUtxoOpt.get());
                        if (prefixPostfixOpt.isEmpty()) {
                                return TransactionContext.typedError(
                                                "could not extract issuance prefix/postfix from UTxO datum");
                        }
                        var prefixPostfix = prefixPostfixOpt.get();
                        var issuancePrefix = prefixPostfix.first();
                        var issuancePostfix = prefixPostfix.second();

                        // Build parameter list: [permitted_cred, asset_name, issuance_prefix,
                        // _issuance_postfix, programmable_base_hash]
                        var assetNameBytes = HexUtil.decodeHexString(request.getAssetName());
                        var programmableBaseHash = HexUtil.decodeHexString(
                                        protocolParams.programmableLogicBaseParams().scriptHash());
                        var issuerAdminContractInitParams = ListPlutusData.of(
                                        serialize(adminPkh),
                                        BytesPlutusData.of(assetNameBytes),
                                        BytesPlutusData.of(issuancePrefix),
                                        BytesPlutusData.of(issuancePostfix),
                                        BytesPlutusData.of(programmableBaseHash));

                        var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(issuerAdminContractInitParams,
                                                        issuerContract.scriptBytes()),
                                        PlutusVersion.v3);

                        var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract,
                                        network.getCardanoNetwork());
                        log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

                        var transferContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "example_transfer_logic.transfer.withdraw");
                        var transferContract = transferContractOpt.get();

                        var transferContractInitParams = ListPlutusData.of(
                                        serialize(Credential.fromScript(
                                                        protocolParams.programmableLogicBaseParams().scriptHash())),
                                        BytesPlutusData.of(HexUtil.decodeHexString(blacklistNodePolicyId)));

                        var substandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(transferContractInitParams,
                                                        transferContract.scriptBytes()),
                                        PlutusVersion.v3);
                        var substandardTransferAddress = AddressProvider.getRewardAddress(substandardTransferContract,
                                        network.getCardanoNetwork());
                        log.info("substandardTransferAddress: {}", substandardTransferAddress.getAddress());

                        var requiredStakeAddresses = Stream.of(substandardIssueAddress, substandardTransferAddress)
                                        .map(Address::getAddress)
                                        .toList();
                        log.info("requiredStakeAddresses: {}", String.join(", ", requiredStakeAddresses));

                        // Check stake address registration - try database first, fallback to Blockfrost
                        var registeredStakeAddresses = requiredStakeAddresses.stream()
                                        .filter(stakeAddress -> {
                                                // First try database (if chain sync is running)
                                                var dbResult = stakeRegistrationRepository
                                                                .findRegistrationsByStakeAddress(stakeAddress)
                                                                .map(stakeRegistration -> stakeRegistration.getType()
                                                                                .equals(CertificateType.STAKE_REGISTRATION));

                                                if (dbResult.isPresent()) {
                                                        boolean isRegistered = dbResult.get();
                                                        log.debug("Stake address {} registration from DB: {}",
                                                                        stakeAddress, isRegistered);
                                                        return isRegistered;
                                                }

                                                // Fallback to Blockfrost API (when chain sync is not available)
                                                log.debug("Stake address {} not found in DB, checking Blockfrost...",
                                                                stakeAddress);
                                                try {
                                                        var accountInfo = bfBackendService.getAccountService()
                                                                        .getAccountInformation(stakeAddress);
                                                        if (accountInfo.isSuccessful()
                                                                        && accountInfo.getValue() != null) {
                                                                boolean isRegistered = accountInfo.getValue()
                                                                                .getActive();
                                                                log.info("Stake address {} registration from Blockfrost: {}",
                                                                                stakeAddress, isRegistered);
                                                                return isRegistered;
                                                        } else {
                                                                // If account info is not successful, it might mean the
                                                                // address doesn't exist yet (not registered)
                                                                // But also check if we got a 404 vs other error
                                                                log.warn("Failed to get account info from Blockfrost for {}: {}",
                                                                                stakeAddress,
                                                                                accountInfo.getResponse());
                                                                // If it's a 404, the address is definitely not
                                                                // registered
                                                                // If it's another error, we'll assume not registered to
                                                                // be safe
                                                                return false;
                                                        }
                                                } catch (Exception e) {
                                                        log.error("Error checking stake address registration via Blockfrost for {}: {}",
                                                                        stakeAddress, e.getMessage());
                                                        // On error, assume not registered to avoid double registration
                                                        return false;
                                                }
                                        })
                                        .toList();
                        log.info("registeredStakeAddresses: {}", String.join(", ", registeredStakeAddresses));

                        var stakeAddressesToRegister = requiredStakeAddresses.stream()
                                        .filter(stakeAddress -> !registeredStakeAddresses.contains(stakeAddress))
                                        .toList();
                        log.info("stakeAddressesToRegister: {}", String.join(", ", stakeAddressesToRegister));

                        if (stakeAddressesToRegister.isEmpty()) {
                                return TransactionContext.ok(null, registeredStakeAddresses);
                        } else {

                                var registerAddressTx = new Tx()
                                                .from(request.getFeePayerAddress())
                                                .withChangeAddress(request.getFeePayerAddress());

                                stakeAddressesToRegister.forEach(registerAddressTx::registerStakeAddress);

                                var transaction = quickTxBuilder.compose(registerAddressTx)
                                                .feePayer(request.getFeePayerAddress())
                                                .build();

                                return TransactionContext.ok(transaction.serializeToHex(), registeredStakeAddresses);
                        }

                } catch (Exception e) {
                        log.error("error", e);
                        return TransactionContext.typedError("error: " + e.getMessage());
                }
        }

        @Override
        public TransactionContext<RegistrationResult> buildRegistrationTransaction(
                        FreezeAndSeizeRegisterRequest request,
                        ProtocolBootstrapParams protocolParams) {

                try {
                        // Validate required fields
                        if (request.getFeePayerAddress() == null || request.getFeePayerAddress().isEmpty()) {
                                log.error("feePayerAddress is null or empty in request");
                                return TransactionContext.typedError(
                                                "feePayerAddress is required but was not provided in the request");
                        }

                        if (request.getAdminPubKeyHash() == null || request.getAdminPubKeyHash().isEmpty()) {
                                log.error("adminPubKeyHash is null or empty in request");
                                return TransactionContext.typedError(
                                                "adminPubKeyHash is required but was not provided in the request");
                        }

                        if (request.getBlacklistNodePolicyId() == null
                                        || request.getBlacklistNodePolicyId().isEmpty()) {
                                log.error("blacklistNodePolicyId is null or empty in request");
                                return TransactionContext.typedError(
                                                "blacklistNodePolicyId is required but was not provided in the request");
                        }

                        var adminPkh = Credential.fromKey(request.getAdminPubKeyHash());
                        var blacklistNodePolicyId = request.getBlacklistNodePolicyId();

                        log.info("Fetching UTXOs for feePayerAddress: {}", request.getFeePayerAddress());
                        // Fetch all potential UTXOs (min 5 ADA to satisfy collateral requirement)
                        var allFeePayerUtxos = accountService.findAdaOnlyUtxo(request.getFeePayerAddress(), 5_000_000L);

<<<<<<< HEAD
                        if (allFeePayerUtxos.isEmpty()) {
                                log.error("No fees/collateral UTXOs found for address: {}",
                                                request.getFeePayerAddress());
                                return TransactionContext.typedError(
                                                "No UTXOs found for fee payer address. Please ensure the address has sufficient ADA.");
                        }
=======
        } catch (Exception e) {
            log.error("error", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
    }

    @Override
    public TransactionContext<RegistrationResult> buildRegistrationTransaction(
            FreezeAndSeizeRegisterRequest request,
            ProtocolBootstrapParams protocolParams) {
>>>>>>> upstream/main

                        // Select Collateral: Reserve one UTXO > 5 ADA (only if we have multiple UTXOs)
                        Utxo collateralUtxo = null;
                        List<Utxo> feePayerUtxos = new ArrayList<>();
                        TransactionInput collateralInput = null;

                        // Only separate collateral if we have more than one UTXO
                        // If we have only one UTXO, QuickTxBuilder will use it for both collateral and
                        // fees
                        if (allFeePayerUtxos.size() > 1) {
                                for (Utxo utxo : allFeePayerUtxos) {
                                        // Check if UTXO has >= 5 ADA (5,000,000 lovelace)
                                        boolean hasEnoughAda = utxo.getAmount().stream()
                                                        .anyMatch(a -> "lovelace".equals(a.getUnit()) &&
                                                                        a.getQuantity().compareTo(
                                                                                        new java.math.BigInteger(
                                                                                                        "5000000")) >= 0);

                                        if (collateralUtxo == null && hasEnoughAda) {
                                                collateralUtxo = utxo;
                                        } else {
                                                feePayerUtxos.add(utxo);
                                        }
                                }

                                if (collateralUtxo == null) {
                                        log.error("No suitable collateral UTXO (> 5 ADA) found");
                                        return TransactionContext
                                                        .typedError("Insufficient collateral: No UTXO > 5 ADA found.");
                                }

                                collateralInput = TransactionInput.builder()
                                                .transactionId(collateralUtxo.getTxHash())
                                                .index(collateralUtxo.getOutputIndex())
                                                .build();

                                log.info("Reserved Collateral: {}#{}", collateralUtxo.getTxHash(),
                                                collateralUtxo.getOutputIndex());
                                log.info("Fee Payer Inputs: {}", feePayerUtxos.size());
                        } else {
                                // Single UTXO case: explicitly use it as collateral
                                log.warn("Only one UTXO available - Using it for both collateral and fees");
                                var utxo = allFeePayerUtxos.get(0);
                                feePayerUtxos.add(utxo);

                                collateralInput = TransactionInput.builder()
                                                .transactionId(utxo.getTxHash())
                                                .index(utxo.getOutputIndex())
                                                .build();

                                log.info("Using Single UTXO as Collateral: {}#{}", utxo.getTxHash(),
                                                utxo.getOutputIndex());
                        }

                        var bootstrapTxHash = protocolParams.txHash();

                        var directorySpendContract = protocolScriptBuilderService
                                        .getParameterizedDirectorySpendScript(protocolParams);

                        // Validate protocol params structure before accessing
                        if (protocolParams.protocolParams() == null
                                        || protocolParams.protocolParams().txInput() == null) {
                                log.error("Protocol params structure is invalid or missing txInput");
                                return TransactionContext.typedError(
                                                "could not resolve protocol params UTXO for reference input: protocol params structure is invalid");
                        }

                        // Use the actual protocol params UTxO transaction hash from bootstrap
                        // Note: This UTxO may be spent (used as reference input), so we construct the
                        // reference input directly
                        // from the bootstrap data without needing to fetch the UTXO
                        var protocolParamsTxHash = protocolParams.protocolParams().txInput().txHash();
                        var protocolParamsOutputIndex = protocolParams.protocolParams().txInput().outputIndex();

                        if (protocolParamsTxHash == null || protocolParamsTxHash.isEmpty()) {
                                log.error("Protocol params txHash is null or empty");
                                return TransactionContext.typedError(
                                                "could not resolve protocol params UTXO for reference input: txHash is missing");
                        }

                        log.info("Using protocol params reference input: txHash={}, outputIndex={}",
                                        protocolParamsTxHash, protocolParamsOutputIndex);

                        // For reference inputs, we don't need the full UTXO - we can construct
                        // TransactionInput directly
                        // Try to find UTXO for validation (optional), but don't fail if it's spent
                        Optional<Utxo> protocolParamsUtxoOpt = utxoProvider.findUtxo(protocolParamsTxHash,
                                        protocolParamsOutputIndex);
                        if (protocolParamsUtxoOpt.isEmpty()) {
                                log.info("Protocol params UTXO {}#{} not found (likely spent, used as reference input - this is OK)",
                                                protocolParamsTxHash, protocolParamsOutputIndex);
                        } else {
                                log.debug("Found protocol params UTXO {}#{}", protocolParamsTxHash,
                                                protocolParamsOutputIndex);
                        }

<<<<<<< HEAD
                        // Create a minimal UTXO-like object for compatibility, or use the bootstrap
                        // data directly
                        // We'll use the txHash and outputIndex from bootstrap for the reference input

                        var directorySpendContractAddress = AddressProvider.getEntAddress(directorySpendContract,
                                        network.getCardanoNetwork());
                        log.info("directorySpendContractAddress: {}", directorySpendContractAddress.getAddress());

                        // Validate issuance params structure before accessing
                        if (protocolParams.issuanceParams() == null
                                        || protocolParams.issuanceParams().txInput() == null) {
                                log.error("Issuance params structure is invalid or missing txInput");
                                return TransactionContext.typedError(
                                                "could not resolve issuance params UTXO for reference input: issuance params structure is invalid");
                        }

                        // Use the actual issuance params UTxO transaction hash from bootstrap
                        // Note: This UTxO may be spent (used as reference input), so we construct the
                        // reference input directly
                        // from the bootstrap data without needing to fetch the UTXO
                        var issuanceTxHash = protocolParams.issuanceParams().txInput().txHash();
                        var issuanceOutputIndex = protocolParams.issuanceParams().txInput().outputIndex();

                        if (issuanceTxHash == null || issuanceTxHash.isEmpty()) {
                                log.error("Issuance params txHash is null or empty");
                                return TransactionContext.typedError(
                                                "could not resolve issuance params UTXO for reference input: txHash is missing");
                        }

                        log.info("Using issuance params reference input: txHash={}, outputIndex={}", issuanceTxHash,
                                        issuanceOutputIndex);

                        // For reference inputs, we don't need the full UTXO - we can construct
                        // TransactionInput directly
                        // Try to find UTXO for validation (required for extracting prefix/postfix)
                        Optional<Utxo> issuanceUtxoOpt = utxoProvider.findUtxo(issuanceTxHash, issuanceOutputIndex);
                        if (issuanceUtxoOpt.isEmpty()) {
                                log.error("Issuance params UTXO {}#{} not found - required for extracting prefix/postfix",
                                                issuanceTxHash, issuanceOutputIndex);
                                return TransactionContext
                                                .typedError("could not find issuance UTxO to extract prefix/postfix");
                        }
                        log.debug("Found issuance params UTXO {}#{}", issuanceTxHash, issuanceOutputIndex);

                        // We'll use the txHash and outputIndex from bootstrap for the reference input

                        /// Getting Substandard Contracts and parameterize
                        // Issuer to be used for minting/burning/sieze
                        // NOTE: Parameterized with adminPkh, asset_name, issuance_prefix,
                        /// issuance_postfix, and programmable_base_hash
                        var issuerContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "example_transfer_logic.issuer_admin_contract.withdraw");
                        if (issuerContractOpt.isEmpty()) {
                                return TransactionContext.typedError("could not find issuer contract validator");
                        }
                        var issuerContract = issuerContractOpt.get();

                        // Extract issuance prefix/postfix from issuance UTxO
                        var prefixPostfixOpt = extractIssuancePrefixPostfix(issuanceUtxoOpt.get());
                        if (prefixPostfixOpt.isEmpty()) {
                                return TransactionContext.typedError(
                                                "could not extract issuance prefix/postfix from UTxO datum");
                        }
                        var prefixPostfix = prefixPostfixOpt.get();
                        var issuancePrefix = prefixPostfix.first();
                        var issuancePostfix = prefixPostfix.second();

                        // Build parameter list: [permitted_cred, asset_name, issuance_prefix,
                        // _issuance_postfix, programmable_base_hash]
                        var assetNameBytes = HexUtil.decodeHexString(request.getAssetName());
                        var programmableBaseHash = HexUtil.decodeHexString(
                                        protocolParams.programmableLogicBaseParams().scriptHash());
                        var issuerAdminContractInitParams = ListPlutusData.of(
                                        serialize(adminPkh),
                                        BytesPlutusData.of(assetNameBytes),
                                        BytesPlutusData.of(issuancePrefix),
                                        BytesPlutusData.of(issuancePostfix),
                                        BytesPlutusData.of(programmableBaseHash));

                        var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(issuerAdminContractInitParams,
                                                        issuerContract.scriptBytes()),
                                        PlutusVersion.v3);

                        var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract,
                                        network.getCardanoNetwork());
                        log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

                        var transferContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "example_transfer_logic.transfer.withdraw");
                        if (transferContractOpt.isEmpty()) {
                                return TransactionContext.typedError("could not find transfer contract validator");
                        }
                        var transferContract = transferContractOpt.get();

                        var transferContractInitParams = ListPlutusData.of(
                                        serialize(Credential.fromScript(
                                                        protocolParams.programmableLogicBaseParams().scriptHash())),
                                        BytesPlutusData.of(HexUtil.decodeHexString(blacklistNodePolicyId)));

                        var substandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(transferContractInitParams,
                                                        transferContract.scriptBytes()),
                                        PlutusVersion.v3);
                        var substandardTransferAddress = AddressProvider.getRewardAddress(substandardTransferContract,
                                        network.getCardanoNetwork());
                        log.info("substandardTransferAddress: {}", substandardTransferAddress.getAddress());

                        var issuanceContract = protocolScriptBuilderService
                                        .getParameterizedIssuanceMintScript(protocolParams, substandardIssueContract);
                        final var progTokenPolicyId = issuanceContract.getPolicyId();
                        log.info("Calculated token policy ID: {}", progTokenPolicyId);

                        var registryAddress = AddressProvider.getEntAddress(directorySpendContract,
                                        network.getCardanoNetwork());

                        // Retry logic for handling spent directory UTXOs
                        // This can happen when multiple registrations occur simultaneously
                        Utxo validatedDirectoryUtxo = null;
                        int maxRetries = 10; // Increased from 5 to 10 for better resilience
                        int retryDelayMs = 1000; // Increased from 500ms to 1000ms (1 second) between retries

                        for (int attempt = 0; attempt < maxRetries; attempt++) {
                                if (attempt > 0) {
                                        log.info("Retry attempt {} of {} for finding valid directory UTXO", attempt,
                                                        maxRetries);
                                        try {
                                                Thread.sleep(retryDelayMs);
                                        } catch (InterruptedException e) {
                                                Thread.currentThread().interrupt();
                                                return TransactionContext.typedError(
                                                                "Interrupted while retrying directory UTXO lookup");
                                        }
                                }

                                var registryEntries = utxoProvider.findUtxos(registryAddress.getAddress());
                                log.info("Attempt {}: found {} registry entries", attempt + 1, registryEntries.size());
=======
            /// Getting Substandard Contracts and parameterize
            // Issuer to be used for minting/burning/sieze
            var substandardIssueContract = fesScriptBuilder.buildIssuerAdminScript(Credential.fromKey(request.getAdminPubKeyHash()));
            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

            // Transfer contract
            var substandardTransferContract = fesScriptBuilder.buildTransferScript(
                    protocolParams.programmableLogicBaseParams().scriptHash(),
                    blacklistNodePolicyId
            );
            var substandardTransferAddress = AddressProvider.getRewardAddress(substandardTransferContract, network.getCardanoNetwork());
            log.info("substandardTransferAddress: {}", substandardTransferAddress.getAddress());
>>>>>>> upstream/main

                                // Also check on-chain registry for completeness
                                var nodeAlreadyPresent = linkedListService.nodeAlreadyPresent(progTokenPolicyId,
                                                registryEntries, utxo -> registryNodeParser.parse(utxo.getInlineDatum())
                                                                .map(RegistryNode::key));

<<<<<<< HEAD
                                if (nodeAlreadyPresent) {
                                        log.warn("Token already exists in on-chain registry: policyId={}",
                                                        progTokenPolicyId);
                                        return TransactionContext.typedError(
                                                        String.format("Token already exists in on-chain registry! Policy ID: %s. This token has already been registered. Please use a different token name or admin wallet.",
                                                                        progTokenPolicyId));
                                }
=======
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
                    .value(new BigInteger(request.getQuantity()))
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

            // Save to unified programmable token registry (policyId -> substandardId binding)
            programmableTokenRegistryRepository.save(ProgrammableTokenRegistryEntity.builder()
                    .policyId(progTokenPolicyId)
                    .substandardId(SUBSTANDARD_ID)
                    .assetName(request.getAssetName())
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

        try {

            var adminUtxos = accountService.findAdaOnlyUtxo(request.feePayerAddress(), 10_000_000L);

            var bootstrapTxHash = protocolParams.txHash();

            var issuanceUtxoOpt = utxoProvider.findUtxo(bootstrapTxHash, 2);
            if (issuanceUtxoOpt.isEmpty()) {
                return TransactionContext.typedError("could not resolve issuance params");
            }
            var issuanceUtxo = issuanceUtxoOpt.get();
            log.info("issuanceUtxo: {}", issuanceUtxo);

            /// Getting Substandard Contracts and parameterize
            // Issuer to be used for minting/burning/sieze
            var adminPkh = Credential.fromKey(context.getIssuerAdminPkh());
            var substandardIssueContract = fesScriptBuilder.buildIssuerAdminScript(Credential.fromKey(context.getIssuerAdminPkh()));
            log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());


            var issuanceContract = protocolScriptBuilderService.getParameterizedIssuanceMintScript(protocolParams, substandardIssueContract);
            log.info("issuanceContract: {}", issuanceContract.getPolicyId());

            var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));

            // Programmable Token Mint
            var programmableToken = Asset.builder()
                    .name("0x" + request.assetName())
                    .value(new BigInteger(request.quantity()))
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

            log.info("request.getRecipientAddress(): {}", request.recipientAddress());
            var payeeAddress = new Address(request.recipientAddress());

            var targetAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolParams.programmableLogicBaseParams().scriptHash()),
                    payeeAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());


            var tx = new ScriptTx()
                    .collectFrom(adminUtxos)
                    .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                    .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                    .payToContract(targetAddress.getAddress(), ValueUtil.toAmountList(programmableTokenValue), ConstrPlutusData.of(0))
                    .attachRewardValidator(substandardIssueContract)
                    .withChangeAddress(request.feePayerAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(adminPkh.getBytes())
                    .feePayer(request.feePayerAddress())
//                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                    .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                    .preBalanceTx((txBuilderContext, transaction1) -> {
                        var outputs = transaction1.getBody().getOutputs();
                        if (outputs.getFirst().getAddress().equals(request.feePayerAddress())) {
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
            log.error("error", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
>>>>>>> upstream/main

                                // Filter out spent UTXOs before finding node to replace
                                // This prevents selecting UTXOs that have already been spent
                                var validRegistryEntries = registryEntries.stream()
                                                .filter(utxo -> {
                                                        var exists = utxoProvider.findUtxo(utxo.getTxHash(),
                                                                        utxo.getOutputIndex());
                                                        if (exists.isEmpty()) {
                                                                log.debug("Filtering out spent UTXO: {}#{}",
                                                                                utxo.getTxHash(),
                                                                                utxo.getOutputIndex());
                                                        }
                                                        return exists.isPresent();
                                                })
                                                .toList();

                                log.info("Attempt {}: found {} registry entries, {} are unspent",
                                                attempt + 1, registryEntries.size(), validRegistryEntries.size());

                                if (validRegistryEntries.isEmpty()) {
                                        log.warn("Attempt {}: No unspent registry entries found", attempt + 1);
                                        if (attempt == maxRetries - 1) {
                                                return TransactionContext.typedError(
                                                                "No unspent registry entries found after " + maxRetries
                                                                                + " attempts. The registry may be experiencing high activity.");
                                        }
                                        continue; // Retry
                                }

                                var nodeToReplaceOpt = linkedListService.findNodeToReplace(progTokenPolicyId,
                                                validRegistryEntries,
                                                utxo -> registryNodeParser.parse(utxo.getInlineDatum())
                                                                .map(node -> new LinkedListNode(node.key(),
                                                                                node.next())));

                                if (nodeToReplaceOpt.isEmpty()) {
                                        log.warn("Attempt {}: could not find node to replace", attempt + 1);
                                        if (attempt == maxRetries - 1) {
                                                return TransactionContext
                                                                .typedError("could not find node to replace after "
                                                                                + maxRetries + " attempts");
                                        }
                                        continue; // Retry
                                }

<<<<<<< HEAD
                                var directoryUtxo = nodeToReplaceOpt.get();
                                log.info("Attempt {}: directoryUtxo: {}", attempt + 1, directoryUtxo);

                                // CRITICAL: Validate directory UTXO still exists before using it (double-check)
                                var validatedDirectoryUtxoOpt = utxoProvider.findUtxo(directoryUtxo.getTxHash(),
                                                directoryUtxo.getOutputIndex());
                                if (validatedDirectoryUtxoOpt.isEmpty()) {
                                        log.warn("Attempt {}: Directory UTXO no longer exists: txHash={}, outputIndex={}",
                                                        attempt + 1, directoryUtxo.getTxHash(),
                                                        directoryUtxo.getOutputIndex());
                                        if (attempt == maxRetries - 1) {
                                                return TransactionContext.typedError(
                                                                "Directory UTXO has been spent. The registry may have been updated. Please refresh and try again.");
                                        }
                                        continue; // Retry with fresh registry entries
                                }
=======
    @Override
    public TransactionContext<Void> buildBurnTransaction(BurnTokenRequest request, ProtocolBootstrapParams protocolParams) {

        log.info("request: {}", request);

        try {

            var assetTypeToBurn = new AssetType(request.tokenPolicyId(), request.assetName());
            log.info("assetTypeToBurn: {}", assetTypeToBurn);

            var amountToBurn = new BigInteger(request.quantity());
            log.info("amountToBurn: {}", amountToBurn);

            var adminUtxos = accountService.findAdaOnlyUtxo(request.feePayerAddress(), 10_000_000L);

            var utxoToBurnOpt = utxoProvider.findUtxo(request.utxoTxHash(), request.utxoOutputIndex());
            if (utxoToBurnOpt.isEmpty()) {
                return TransactionContext.error("utxo to burn could not be found");
            }

            var utxoToBurn = utxoToBurnOpt.get();
            log.info("utxoToBurn: {}", utxoToBurn);

            var utxoTokenAmount = utxoToBurn.toValue().amountOf(assetTypeToBurn.policyId(), "0x" + assetTypeToBurn.assetName());
            log.info("utxoTokenAmount: {}", utxoTokenAmount);
            log.info("amountToBurn.compareTo(utxoTokenAmount): {}", amountToBurn.compareTo(utxoTokenAmount));
            if (amountToBurn.compareTo(utxoTokenAmount) > 0) {
                return TransactionContext.error("not enough burn amount");
            }

            /// Getting Substandard Contracts and parameterize
            // Issuer to be used for minting/burning/sieze
            var adminPkh = Credential.fromKey(context.getIssuerAdminPkh());
            var substandardIssueContract = fesScriptBuilder.buildIssuerAdminScript(Credential.fromKey(context.getIssuerAdminPkh()));
            log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());


            var issuanceContract = protocolScriptBuilderService.getParameterizedIssuanceMintScript(protocolParams, substandardIssueContract);
            log.info("issuanceContract: {}", issuanceContract.getPolicyId());

            var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));

            // Programmable Token Mint
            var programmableToken = Asset.builder()
                    .name("0x" + assetTypeToBurn.assetName())
                    .value(amountToBurn.abs().negate())
                    .build();
            log.info("programmableToken: {}", programmableToken);

            var programmableLogicGlobal = protocolScriptBuilderService.getParameterizedProgrammableLogicGlobalScript(protocolParams);
            var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobal, network.getCardanoNetwork());

            // Directory SPEND parameterization
            var registrySpendContract = protocolScriptBuilderService.getParameterizedDirectorySpendScript(protocolParams);
            log.info("registrySpendContract: {}", HexUtil.encodeHexString(registrySpendContract.getScriptHash()));

            var registryAddress = AddressProvider.getEntAddress(registrySpendContract, network.getCardanoNetwork());
            log.info("registryAddress: {}", registryAddress.getAddress());

            var registryEntries = utxoProvider.findUtxos(registryAddress.getAddress());

            var progTokenRegistryOpt = registryEntries.stream()
                    .filter(utxo -> {
                        var registryDatumOpt = registryNodeParser.parse(utxo.getInlineDatum());
                        return registryDatumOpt.map(registryDatum -> registryDatum.key().equals(assetTypeToBurn.policyId())).orElse(false);
                    })
                    .findAny();

            if (progTokenRegistryOpt.isEmpty()) {
                return TransactionContext.typedError("could not find registry entry for token");
            }

            var progTokenRegistry = progTokenRegistryOpt.get();
            log.info("progTokenRegistry: {}", progTokenRegistry);

            var sortedInputUtxos = Stream.concat(adminUtxos.stream(), Stream.of(utxoToBurn))
                    .sorted(new UtxoComparator())
                    .toList();

            var bootstrapTxHash = protocolParams.txHash();

            var protocolParamsUtxoOpt = utxoProvider.findUtxo(bootstrapTxHash, 0);

            if (protocolParamsUtxoOpt.isEmpty()) {
                return TransactionContext.typedError("could not resolve protocol params");
            }

            var protocolParamsUtxo = protocolParamsUtxoOpt.get();
            log.info("protocolParamsUtxo: {}", protocolParamsUtxo);

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

            var seizeInputIndex = sortedInputUtxos.indexOf(utxoToBurn);
            log.info("seizeInputIndex: {}", seizeInputIndex);

            var programmableGlobalRedeemer = ConstrPlutusData.of(1,
                    BigIntPlutusData.of(registryRefInputInex),
                    ListPlutusData.of(BigIntPlutusData.of(seizeInputIndex)),
                    BigIntPlutusData.of(1), // Index of the first output
                    BigIntPlutusData.of(1)
            );

            var programmableLogicBase = protocolScriptBuilderService.getParameterizedProgrammableLogicBaseScript(protocolParams);
            log.info("programmableLogicBase policy: {}", programmableLogicBase.getPolicyId());

            var valueToBurn = Value.from(assetTypeToBurn.policyId(), "0x" + assetTypeToBurn.assetName(), amountToBurn);
            log.info("valueToBurn: {}", valueToBurn);
            var returningValue = utxoToBurn.toValue().subtract(valueToBurn);
            log.info("returningValue: {}", returningValue);

            var tx = new ScriptTx()
                    .collectFrom(adminUtxos)
                    .collectFrom(utxoToBurn, ConstrPlutusData.of(0))
                    .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                    .withdraw(programmableLogicGlobalAddress.getAddress(), BigInteger.ZERO, programmableGlobalRedeemer)
                    .payToContract(utxoToBurn.getAddress(), ValueUtil.toAmountList(returningValue), ConstrPlutusData.of(0))
                    .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                    .readFrom(sortedReferenceInputs.toArray(new TransactionInput[0]))
                    .attachSpendingValidator(programmableLogicBase) // base
                    .attachRewardValidator(programmableLogicGlobal) // global
                    .attachRewardValidator(substandardIssueContract)
                    .withChangeAddress(request.feePayerAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .withRequiredSigners(adminPkh.getBytes())
                    .feePayer(request.feePayerAddress())
//                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                    .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                    .build();

            log.info("tx: {}", transaction.serializeToHex());
            log.info("tx: {}", objectMapper.writeValueAsString(transaction));

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.error("error", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }


    }

    @Override
    public TransactionContext<Void> buildTransferTransaction(
            TransferTokenRequest request,
            ProtocolBootstrapParams protocolParams) {
>>>>>>> upstream/main

                                validatedDirectoryUtxo = validatedDirectoryUtxoOpt.get();
                                log.info("Attempt {}: Successfully validated directory UTXO", attempt + 1);
                                break; // Success - exit retry loop
                        }

                        if (validatedDirectoryUtxo == null) {
                                return TransactionContext.typedError(
                                                "Failed to find valid directory UTXO after " + maxRetries
                                                                + " attempts. The registry may be experiencing high activity.");
                        }

                        var existingRegistryNodeDatumOpt = registryNodeParser
                                        .parse(validatedDirectoryUtxo.getInlineDatum());

                        if (existingRegistryNodeDatumOpt.isEmpty()) {
                                return TransactionContext.typedError("could not parse current registry node");
                        }

                        var existingRegistryNodeDatum = existingRegistryNodeDatumOpt.get();

                        // Directory MINT - NFT, address, datum and value
                        var directoryMintContract = protocolScriptBuilderService
                                        .getParameterizedDirectoryMintScript(protocolParams);
                        var directoryMintPolicyId = directoryMintContract.getPolicyId();

<<<<<<< HEAD
                        var directoryMintRedeemer = ConstrPlutusData.of(1,
                                        BytesPlutusData.of(issuanceContract.getScriptHash()),
                                        BytesPlutusData.of(substandardIssueContract.getScriptHash()));
=======
            var amountToTransfer = new BigInteger(request.quantity());
>>>>>>> upstream/main

                        var directoryMintNft = Asset.builder()
                                        .name("0x" + issuanceContract.getPolicyId())
                                        .value(ONE)
                                        .build();

                        Optional<Amount> registrySpentNftOpt = validatedDirectoryUtxo.getAmount()
                                        .stream()
                                        .filter(amount -> amount.getQuantity().equals(ONE) && directoryMintPolicyId
                                                        .equals(AssetType.fromUnit(amount.getUnit()).policyId()))
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

                        var directoryMintDatum = new RegistryNode(
                                        HexUtil.encodeHexString(issuanceContract.getScriptHash()),
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
                                                                        .build()))
                                        .build();
                        log.info("directoryMintValue: {}", directoryMintValue);

                        Value directorySpendValue = Value.builder()
                                        .coin(Amount.ada(1).getQuantity())
                                        .multiAssets(List.of(
                                                        MultiAsset.builder()
                                                                        .policyId(directoryMintPolicyId)
                                                                        .assets(List.of(directorySpendNft))
                                                                        .build()))
                                        .build();
                        log.info("directorySpendValue: {}", directorySpendValue);

                        var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1,
                                        BytesPlutusData.of(substandardIssueContract.getScriptHash())));

                        // Programmable Token Mint
                        var programmableToken = Asset.builder()
                                        .name("0x" + request.getAssetName())
                                        .value(new BigInteger(request.getQuantity()))
                                        .build();

                        Value programmableTokenValue = Value.builder()
                                        .coin(Amount.ada(1).getQuantity())
                                        .multiAssets(List.of(
                                                        MultiAsset.builder()
                                                                        .policyId(issuanceContract.getPolicyId())
                                                                        .assets(List.of(programmableToken))
                                                                        .build()))
                                        .build();

                        log.info("request.getRecipientAddress(): {}", request.getRecipientAddress());
                        var payeeAddress = new Address(request.getRecipientAddress());

                        var targetAddress = AddressProvider.getBaseAddress(
                                        Credential.fromScript(
                                                        protocolParams.programmableLogicBaseParams().scriptHash()),
                                        payeeAddress.getDelegationCredential().get(),
                                        network.getCardanoNetwork());

                        var tx = new ScriptTx()
                                        .collectFrom(feePayerUtxos)
                                        .collectFrom(validatedDirectoryUtxo, ConstrPlutusData.of(0))
                                        // No redeemer for substandard
                                        .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO,
                                                        ConstrPlutusData.of(0))
                                        // Mint Token
                                        .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                                        // Redeemer is DirectoryInit (constr(0))
                                        .mintAsset(directoryMintContract, directoryMintNft, directoryMintRedeemer)
                                        .payToContract(targetAddress.getAddress(),
                                                        ValueUtil.toAmountList(programmableTokenValue),
                                                        ConstrPlutusData.of(0))
                                        // Directory Params
                                        .payToContract(directorySpendContractAddress.getAddress(),
                                                        ValueUtil.toAmountList(directorySpendValue),
                                                        directorySpendDatum.toPlutusData())
                                        // Directory Params
                                        .payToContract(directorySpendContractAddress.getAddress(),
                                                        ValueUtil.toAmountList(directoryMintValue),
                                                        directoryMintDatum.toPlutusData())
                                        .attachSpendingValidator(directorySpendContract)
                                        .attachRewardValidator(substandardIssueContract)
                                        .readFrom(TransactionInput.builder()
                                                        .transactionId(protocolParamsTxHash)
                                                        .index(protocolParamsOutputIndex)
                                                        .build(),
                                                        TransactionInput.builder()
                                                                        .transactionId(issuanceTxHash)
                                                                        .index(issuanceOutputIndex)
                                                                        .build())
                                        .withChangeAddress(request.getFeePayerAddress());

                        var txBuilder = quickTxBuilder.compose(tx);

                        // Only add explicit collateral if we separated it (multi-UTXO case)
                        // For single UTXO case, QuickTxBuilder will auto-select collateral
                        if (collateralInput != null) {
                                txBuilder = txBuilder.withCollateralInputs(collateralInput);
                        }

                        var transaction = txBuilder
                                        .withRequiredSigners(adminPkh.getBytes())
                                        .feePayer(request.getFeePayerAddress())
                                        // .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                                        .mergeOutputs(false) // <-- this is important! or directory tokens will go to
                                                             // same address

                                        .preBalanceTx((txBuilderContext, transaction1) -> {
                                                var outputs = transaction1.getBody().getOutputs();
                                                if (outputs.getFirst().getAddress()
                                                                .equals(request.getFeePayerAddress())) {
                                                        log.info("found dummy input, moving it...");
                                                        var first = outputs.removeFirst();
                                                        outputs.addLast(first);
                                                }
                                                try {
                                                        log.info("pre tx: {}",
                                                                        objectMapper.writeValueAsString(transaction1));
                                                } catch (JsonProcessingException e) {
                                                        throw new RuntimeException(e);
                                                }
                                        })
                                        .postBalanceTx((txBuilderContext, transaction1) -> {
                                                try {
                                                        // Apply a small fee buffer to account for potential
                                                        // underestimation
                                                        // when using manual reference inputs or complex script logic
                                                        var fees = transaction1.getBody().getFee();
                                                        var newFees = fees.add(BigInteger.valueOf(200_000L));
                                                        transaction1.getBody().setFee(newFees);

                                                        // Adjust change output to reflect the new fee
                                                        var outputs = transaction1.getBody().getOutputs();
                                                        for (var output : outputs) {
                                                                if (output.getAddress()
                                                                                .equals(request.getFeePayerAddress())) {
                                                                        var currentAmount = output.getValue().getCoin();
                                                                        output.getValue().setCoin(currentAmount
                                                                                        .subtract(BigInteger.valueOf(
                                                                                                        200_000L)));
                                                                        break;
                                                                }
                                                        }

                                                        log.info("post tx: {}",
                                                                        objectMapper.writeValueAsString(transaction1));
                                                } catch (JsonProcessingException e) {
                                                        throw new RuntimeException(e);
                                                }
                                        })
                                        .build();

                        log.info("tx: {}", transaction.serializeToHex());
                        log.info("tx: {}", objectMapper.writeValueAsString(transaction));

                        var blacklistInitOpt = blacklistInitRepository
                                        .findByBlacklistNodePolicyId(blacklistNodePolicyId);

                        if (blacklistInitOpt.isEmpty()) {
                                return TransactionContext.typedError("blacklist init could not be found");
                        }

                        freezeAndSeizeTokenRegistrationRepository.save(FreezeAndSeizeTokenRegistrationEntity.builder()
                                        .programmableTokenPolicyId(progTokenPolicyId)
                                        .issuerAdminPkh(HexUtil.encodeHexString(adminPkh.getBytes()))
                                        .blacklistInit(blacklistInitOpt.get())
                                        .build());

                        // Save to unified programmable token registry (policyId -> substandardId
                        // binding)
                        programmableTokenRegistryRepository.save(ProgrammableTokenRegistryEntity.builder()
                                        .policyId(progTokenPolicyId)
                                        .substandardId(SUBSTANDARD_ID)
                                        .assetName(request.getAssetName())
                                        .build());

                        log.info("Transaction built successfully, serializing...");
                        var serializedTx = transaction.serializeToHex();
                        log.info("Transaction serialized successfully, length: {}", serializedTx.length());
                        return TransactionContext.ok(serializedTx, new RegistrationResult(progTokenPolicyId));

                } catch (Exception e) {
                        log.error("Exception during transaction building", e);
                        log.error("Exception class: {}", e.getClass().getName());
                        log.error("Exception message: {}", e.getMessage());
                        if (e.getCause() != null) {
                                log.error("Caused by: {}", e.getCause().getMessage());
                        }
                        // Check if this is the UTXO lookup error
                        var errorMessage = e.getMessage();
                        if (errorMessage != null && (errorMessage.contains("protocol params")
                                        || errorMessage.contains("UTXO") || errorMessage.contains("UTxO"))) {
                                log.error("This appears to be a UTXO/protocol params error. Full stack trace:");
                                e.printStackTrace();
                        }
                        return TransactionContext.typedError("error: " + errorMessage);
                }
        }

        @Override
        public TransactionContext<Void> buildMintTransaction(
                        MintTokenRequest request,
                        ProtocolBootstrapParams protocolParams) {

                try {

                        var adminUtxos = accountService.findAdaOnlyUtxo(request.feePayerAddress(), 10_000_000L);

                        if (adminUtxos.isEmpty()) {
                                log.error("No admin UTXOs found for address: {}", request.feePayerAddress());
                                return TransactionContext.typedError(
                                                "No UTXOs found for admin address. Please ensure the address has sufficient ADA.");
                        }

                        // Select Collateral: Reserve one UTXO > 5 ADA (only if we have multiple UTXOs)
                        Utxo collateralUtxo = null;
                        List<Utxo> feePayerUtxos = new ArrayList<>();
                        TransactionInput collateralInput = null;

                        // Only separate collateral if we have more than one UTXO
                        // If we have only one UTXO, QuickTxBuilder will use it for both collateral and
                        // fees
                        if (adminUtxos.size() > 1) {
                                for (Utxo utxo : adminUtxos) {
                                        // Check if UTXO has >= 5 ADA (5,000,000 lovelace)
                                        boolean hasEnoughAda = utxo.getAmount().stream()
                                                        .anyMatch(a -> "lovelace".equals(a.getUnit()) &&
                                                                        a.getQuantity().compareTo(
                                                                                        new java.math.BigInteger(
                                                                                                        "5000000")) >= 0);

                                        if (collateralUtxo == null && hasEnoughAda) {
                                                collateralUtxo = utxo;
                                        } else {
                                                feePayerUtxos.add(utxo);
                                        }
                                }

                                if (collateralUtxo == null) {
                                        log.error("No suitable collateral UTXO (> 5 ADA) found");
                                        return TransactionContext
                                                        .typedError("Insufficient collateral: No UTXO > 5 ADA found.");
                                }

                                collateralInput = TransactionInput.builder()
                                                .transactionId(collateralUtxo.getTxHash())
                                                .index(collateralUtxo.getOutputIndex())
                                                .build();

                                log.info("Reserved Collateral: {}#{}", collateralUtxo.getTxHash(),
                                                collateralUtxo.getOutputIndex());
                                if (collateralUtxo.getTxHash().equals(
                                                "76884b2a51661740e4b962f4df22afc7193925f0c36aa170d820a7c2f55ad396")) {
                                        log.error("CRITICAL: Selected KNOWN BAD UTXO for collateral!");
                                }
                                log.info("Fee Payer Inputs: {}", feePayerUtxos.size());
                        } else {
                                // Single UTXO case: explicitly use it as collateral
                                log.warn("Only one UTXO available - Using it for both collateral and fees");
                                var utxo = adminUtxos.get(0);
                                feePayerUtxos.add(utxo);

                                collateralInput = TransactionInput.builder()
                                                .transactionId(utxo.getTxHash())
                                                .index(utxo.getOutputIndex())
                                                .build();

                                log.info("Using Single UTXO as Collateral: {}#{}", utxo.getTxHash(),
                                                utxo.getOutputIndex());
                        }

                        var bootstrapTxHash = protocolParams.txHash();

                        // Validate issuance params structure before accessing
                        if (protocolParams.issuanceParams() == null
                                        || protocolParams.issuanceParams().txInput() == null) {
                                log.error("Issuance params structure is invalid or missing txInput");
                                return TransactionContext.typedError(
                                                "could not resolve issuance params UTXO for reference input: issuance params structure is invalid");
                        }

<<<<<<< HEAD
                        // Use the actual issuance params UTxO transaction hash from bootstrap
                        // Note: This UTxO may be spent (used as reference input), so we construct the
                        // reference input directly
                        // from the bootstrap data without needing to fetch the UTXO
                        var issuanceTxHash = protocolParams.issuanceParams().txInput().txHash();
                        var issuanceOutputIndex = protocolParams.issuanceParams().txInput().outputIndex();

                        if (issuanceTxHash == null || issuanceTxHash.isEmpty()) {
                                log.error("Issuance params txHash is null or empty");
                                return TransactionContext.typedError(
                                                "could not resolve issuance params UTXO for reference input: txHash is missing");
                        }

                        log.info("Using issuance params reference input: txHash={}, outputIndex={}", issuanceTxHash,
                                        issuanceOutputIndex);

                        // For reference inputs, we don't need the full UTXO - we can construct
                        // TransactionInput directly
                        // Try to find UTXO for validation (required for extracting prefix/postfix)
                        Optional<Utxo> issuanceUtxoOpt = utxoProvider.findUtxo(issuanceTxHash, issuanceOutputIndex);
                        if (issuanceUtxoOpt.isEmpty()) {
                                log.error("Issuance params UTXO {}#{} not found - required for extracting prefix/postfix",
                                                issuanceTxHash, issuanceOutputIndex);
                                return TransactionContext
                                                .typedError("could not find issuance UTxO to extract prefix/postfix");
                        }
                        log.debug("Found issuance params UTXO {}#{}", issuanceTxHash, issuanceOutputIndex);

                        // We'll use the txHash and outputIndex from bootstrap for the reference input

                        /// Getting Substandard Contracts and parameterize
                        // Issuer to be used for minting/burning/sieze
                        // NOTE: Parameterized with adminPkh, asset_name, issuance_prefix,
                        /// issuance_postfix, and programmable_base_hash
                        var issuerContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "example_transfer_logic.issuer_admin_contract.withdraw");
                        if (issuerContractOpt.isEmpty()) {
                                return TransactionContext.typedError("could not find issuer contract validator");
                        }
                        var issuerContract = issuerContractOpt.get();

                        // Extract issuance prefix/postfix from issuance UTxO
                        var prefixPostfixOpt = extractIssuancePrefixPostfix(issuanceUtxoOpt.get());
                        if (prefixPostfixOpt.isEmpty()) {
                                return TransactionContext.typedError(
                                                "could not extract issuance prefix/postfix from UTxO datum");
                        }
                        var prefixPostfix = prefixPostfixOpt.get();
                        var issuancePrefix = prefixPostfix.first();
                        var issuancePostfix = prefixPostfix.second();

                        var adminPkh = Credential.fromKey(context.getIssuerAdminPkh());
                        // Build parameter list: [permitted_cred, asset_name, issuance_prefix,
                        // _issuance_postfix, programmable_base_hash]
                        var assetNameBytes = HexUtil.decodeHexString(request.assetName());
                        var programmableBaseHash = HexUtil.decodeHexString(
                                        protocolParams.programmableLogicBaseParams().scriptHash());
                        var issuerAdminContractInitParams = ListPlutusData.of(
                                        serialize(adminPkh),
                                        BytesPlutusData.of(assetNameBytes),
                                        BytesPlutusData.of(issuancePrefix),
                                        BytesPlutusData.of(issuancePostfix),
                                        BytesPlutusData.of(programmableBaseHash));

                        var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(issuerAdminContractInitParams,
                                                        issuerContract.scriptBytes()),
                                        PlutusVersion.v3);
                        log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

                        var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract,
                                        network.getCardanoNetwork());
                        log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

                        var issuanceContract = protocolScriptBuilderService
                                        .getParameterizedIssuanceMintScript(protocolParams, substandardIssueContract);
                        log.info("issuanceContract: {}", issuanceContract.getPolicyId());

                        var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1,
                                        BytesPlutusData.of(substandardIssueContract.getScriptHash())));

                        // Programmable Token Mint
                        var programmableToken = Asset.builder()
                                        .name("0x" + request.assetName())
                                        .value(new BigInteger(request.quantity()))
                                        .build();

                        Value programmableTokenValue = Value.builder()
                                        .coin(Amount.ada(1).getQuantity())
                                        .multiAssets(List.of(
                                                        MultiAsset.builder()
                                                                        .policyId(issuanceContract.getPolicyId())
                                                                        .assets(List.of(programmableToken))
                                                                        .build()))
                                        .build();

                        log.info("request.getRecipientAddress(): {}", request.recipientAddress());
                        var payeeAddress = new Address(request.recipientAddress());

                        var targetAddress = AddressProvider.getBaseAddress(
                                        Credential.fromScript(
                                                        protocolParams.programmableLogicBaseParams().scriptHash()),
                                        payeeAddress.getDelegationCredential().get(),
                                        network.getCardanoNetwork());

                        var tx = new ScriptTx()
                                        .collectFrom(feePayerUtxos)
                                        .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO,
                                                        ConstrPlutusData.of(0))
                                        .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                                        .payToContract(targetAddress.getAddress(),
                                                        ValueUtil.toAmountList(programmableTokenValue),
                                                        ConstrPlutusData.of(0))
                                        .attachRewardValidator(substandardIssueContract)
                                        .readFrom(TransactionInput.builder()
                                                        .transactionId(issuanceTxHash)
                                                        .index(issuanceOutputIndex)
                                                        .build())
                                        .withChangeAddress(request.feePayerAddress());

                        var txBuilder = quickTxBuilder.compose(tx);

                        // For single UTXO case, QuickTxBuilder will auto-select collateral
                        if (collateralInput != null) {
                                txBuilder = txBuilder.withCollateralInputs(collateralInput);
                        }

                        var transaction = txBuilder
                                        .withRequiredSigners(adminPkh.getBytes())
                                        .feePayer(request.feePayerAddress())
                                        // .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                                        .mergeOutputs(false) // <-- this is important! or directory tokens will go to
                                                             // same address
                                        .preBalanceTx((txBuilderContext, transaction1) -> {
                                                var outputs = transaction1.getBody().getOutputs();
                                                if (outputs.getFirst().getAddress().equals(request.feePayerAddress())) {
                                                        log.info("found dummy input, moving it...");
                                                        var first = outputs.removeFirst();
                                                        outputs.addLast(first);
                                                }
                                                try {
                                                        log.info("pre tx: {}",
                                                                        objectMapper.writeValueAsString(transaction1));
                                                } catch (JsonProcessingException e) {
                                                        throw new RuntimeException(e);
                                                }
                                        })
                                        .postBalanceTx((txBuilderContext, transaction1) -> {
                                                try {
                                                        // Apply a small fee buffer to account for potential
                                                        // underestimation
                                                        // when using manual reference inputs or complex script logic
                                                        var fees = transaction1.getBody().getFee();
                                                        var newFees = fees.add(BigInteger.valueOf(200_000L));
                                                        transaction1.getBody().setFee(newFees);

                                                        // Adjust change output to reflect the new fee
                                                        var outputs = transaction1.getBody().getOutputs();
                                                        for (var output : outputs) {
                                                                if (output.getAddress()
                                                                                .equals(request.feePayerAddress())) {
                                                                        var currentAmount = output.getValue().getCoin();
                                                                        output.getValue().setCoin(currentAmount
                                                                                        .subtract(BigInteger.valueOf(
                                                                                                        200_000L)));
                                                                        break;
                                                                }
                                                        }

                                                        log.info("post tx: {}",
                                                                        objectMapper.writeValueAsString(transaction1));
                                                } catch (JsonProcessingException e) {
                                                        throw new RuntimeException(e);
                                                }
                                        })
                                        .build();

                        log.info("tx: {}", transaction.serializeToHex());
                        log.info("tx: {}", objectMapper.writeValueAsString(transaction));

                        return TransactionContext.ok(transaction.serializeToHex());

                } catch (Exception e) {
                        log.error("error", e);
                        return TransactionContext.typedError("error: " + e.getMessage());
                }
=======
            // FIXME:
            var parameterisedSubstandardTransferContract = fesScriptBuilder.buildTransferScript(
                    protocolParams.programmableLogicBaseParams().scriptHash(),
                    blacklistNodePolicyId
            );
>>>>>>> upstream/main

        }

        @Override
        public TransactionContext<Void> buildTransferTransaction(
                        TransferTokenRequest request,
                        ProtocolBootstrapParams protocolParams) {

<<<<<<< HEAD
                try {
=======
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
                return TransactionContext.typedError("Not enough funds");
            }

            var parameterisedBlacklistSpendingScript = fesScriptBuilder.buildBlacklistSpendScript(blacklistNodePolicyId);
            var blacklistAddress = AddressProvider.getEntAddress(parameterisedBlacklistSpendingScript, network.getCardanoNetwork());

            var blacklistUtxos = utxoProvider.findUtxos(blacklistAddress.getAddress());

            var sortedInputUtxos = Stream.concat(adminUtxos.stream(), inputUtxos.stream())
                    .sorted(new UtxoComparator())
                    .toList();

            var proofs = new ArrayList<Pair<Utxo, Utxo>>();
            var progTokenBaseScriptHash = protocolParams.programmableLogicBaseParams().scriptHash();
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
                        return TransactionContext.typedError("could not resolve blacklist exemption");
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

            log.info("substandardTransferAddress.getAddress(): {}", substandardTransferAddress.getAddress());
            log.info("programmableLogicGlobalAddress.getAddress(): {}", programmableLogicGlobalAddress.getAddress());

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
                    .additionalSignersCount(1)
                    .feePayer(senderAddress.getAddress())
                    .mergeOutputs(false)
//                    .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                    .build();


            log.info("tx: {}", transaction.serializeToHex());
            log.info("tx: {}", objectMapper.writeValueAsString(transaction));

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.warn("error", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
>>>>>>> upstream/main

                        var senderAddress = new Address(request.senderAddress());
                        var receiverAddress = new Address(request.recipientAddress());
                        var blacklistNodePolicyId = context.getBlacklistNodePolicyId();

                        var adminUtxos = accountService.findAdaOnlyUtxo(senderAddress.getAddress(), 10_000_000L);

                        if (adminUtxos.isEmpty()) {
                                log.error("No admin UTXOs found");
                                return TransactionContext.typedError(
                                                "No UTXOs found for admin address. Please ensure the address has sufficient ADA.");
                        }

                        var progToken = AssetType.fromUnit(request.unit());
                        log.info("policy id: {}, asset name: {}", progToken.policyId(),
                                        progToken.unsafeHumanAssetName());

                        var amountToTransfer = BigInteger.valueOf(10_000_000L);

                        // Directory SPEND parameterization
                        var registrySpendContract = protocolScriptBuilderService
                                        .getParameterizedDirectorySpendScript(protocolParams);
                        log.info("registrySpendContract: {}",
                                        HexUtil.encodeHexString(registrySpendContract.getScriptHash()));

                        var registryAddress = AddressProvider.getEntAddress(registrySpendContract,
                                        network.getCardanoNetwork());
                        log.info("registryAddress: {}", registryAddress.getAddress());

                        var registryEntries = utxoProvider.findUtxos(registryAddress.getAddress());

                        var progTokenRegistryOpt = registryEntries.stream()
                                        .filter(utxo -> {
                                                var registryDatumOpt = registryNodeParser.parse(utxo.getInlineDatum());
                                                return registryDatumOpt
                                                                .map(registryDatum -> registryDatum.key()
                                                                                .equals(progToken.policyId()))
                                                                .orElse(false);
                                        })
                                        .findAny();

                        if (progTokenRegistryOpt.isEmpty()) {
                                return TransactionContext.typedError("could not find registry entry for token");
                        }

                        var progTokenRegistry = progTokenRegistryOpt.get();
                        log.info("progTokenRegistry: {}", progTokenRegistry);

                        var bootstrapTxHash = protocolParams.txHash();

                        // Use the actual protocol params UTxO transaction hash from bootstrap
                        // Note: This UTxO may be spent (used as reference input), so we construct
                        // TransactionInput directly
                        var protocolParamsTxHash = protocolParams.protocolParams().txInput().txHash();
                        var protocolParamsOutputIndex = protocolParams.protocolParams().txInput().outputIndex();
                        log.info("Using protocol params reference input: txHash={}, outputIndex={}",
                                        protocolParamsTxHash, protocolParamsOutputIndex);
                        var protocolParamsUtxo = TransactionInput.builder()
                                        .transactionId(protocolParamsTxHash)
                                        .index(protocolParamsOutputIndex)
                                        .build();

                        var senderProgrammableTokenAddress = AddressProvider.getBaseAddress(
                                        Credential.fromScript(
                                                        protocolParams.programmableLogicBaseParams().scriptHash()),
                                        senderAddress.getDelegationCredential().get(),
                                        network.getCardanoNetwork());

                        var recipientProgrammableTokenAddress = AddressProvider.getBaseAddress(
                                        Credential.fromScript(
                                                        protocolParams.programmableLogicBaseParams().scriptHash()),
                                        receiverAddress.getDelegationCredential().get(),
                                        network.getCardanoNetwork());

                        var senderProgTokensUtxos = utxoProvider.findUtxos(senderProgrammableTokenAddress.getAddress());

                        // // Programmable Logic Global parameterization
                        var programmableLogicGlobal = protocolScriptBuilderService
                                        .getParameterizedProgrammableLogicGlobalScript(protocolParams);
                        var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobal,
                                        network.getCardanoNetwork());
                        log.info("programmableLogicGlobalAddress policy: {}",
                                        programmableLogicGlobalAddress.getAddress());
                        log.info("protocolBootstrapParams.programmableLogicGlobalPrams().scriptHash(): {}",
                                        protocolParams.programmableLogicGlobalPrams().scriptHash());
                        //
                        //// // Programmable Logic Base parameterization
                        var programmableLogicBase = protocolScriptBuilderService
                                        .getParameterizedProgrammableLogicBaseScript(protocolParams);
                        log.info("programmableLogicBase policy: {}", programmableLogicBase.getPolicyId());

                        // FIXME:
                        var substandardTransferContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "example_transfer_logic.transfer.withdraw");
                        if (substandardTransferContractOpt.isEmpty()) {
                                log.warn("could not resolve transfer contract");
                                return TransactionContext.typedError("could not resolve transfer contract");
                        }

                        var substandardTransferContract1 = substandardTransferContractOpt.get();

                        var transferContractInitParams = ListPlutusData.of(
                                        serialize(Credential.fromScript(
                                                        protocolParams.programmableLogicBaseParams().scriptHash())),
                                        BytesPlutusData.of(HexUtil.decodeHexString(blacklistNodePolicyId)));

                        var parameterisedSubstandardTransferContract = PlutusBlueprintUtil
                                        .getPlutusScriptFromCompiledCode(
                                                        AikenScriptUtil.applyParamToScript(transferContractInitParams,
                                                                        substandardTransferContract1.scriptBytes()),
                                                        PlutusVersion.v3);

                        var substandardTransferAddress = AddressProvider.getRewardAddress(
                                        parameterisedSubstandardTransferContract, network.getCardanoNetwork());
                        log.info("substandardTransferAddress: {}", substandardTransferAddress.getAddress());

                        var valueToSend = Value.from(progToken.policyId(), "0x" + progToken.assetName(),
                                        amountToTransfer);

                        var inputUtxos = senderProgTokensUtxos.stream()
                                        .reduce(new Pair<List<Utxo>, Value>(List.of(), Value.builder().build()),
                                                        (listValuePair, utxo) -> {
                                                                if (listValuePair.second().subtract(valueToSend)
                                                                                .isPositive()) {
                                                                        return listValuePair;
                                                                } else {
                                                                        if (utxo.toValue().amountOf(
                                                                                        progToken.policyId(),
                                                                                        "0x" + progToken.assetName())
                                                                                        .compareTo(BigInteger.ONE) > 0) {
                                                                                var newUtxos = Stream.concat(
                                                                                                Stream.of(utxo),
                                                                                                listValuePair.first()
                                                                                                                .stream());
                                                                                return new Pair<>(newUtxos.toList(),
                                                                                                listValuePair.second()
                                                                                                                .add(utxo.toValue()));
                                                                        } else {
                                                                                return listValuePair;
                                                                        }
                                                                }
                                                        }, (listValuePair, listValuePair2) -> {
                                                                var newUtxos = Stream.concat(
                                                                                listValuePair.first().stream(),
                                                                                listValuePair.first().stream());
                                                                return new Pair<>(newUtxos.toList(), listValuePair
                                                                                .second().add(listValuePair2.second()));
                                                        })
                                        .first();

                        var senderProgTokensValue = inputUtxos.stream()
                                        .map(Utxo::toValue)
                                        .filter(value -> value
                                                        .amountOf(progToken.policyId(), "0x" + progToken.assetName())
                                                        .compareTo(BigInteger.ZERO) > 0)
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
                                                                        .build()))
                                        .build();

                        var progTokenAmount = senderProgTokensValue.amountOf(progToken.policyId(),
                                        "0x" + progToken.assetName());
                        log.info("progTokenAmount: {}", progTokenAmount);

                        if (progTokenAmount.compareTo(amountToTransfer) < 0) {
                                return TransactionContext.typedError("Not enough funds");
                        }

                        var blacklistSpendValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "blacklist_spend.blacklist_spend.spend");
                        var blacklistSpendValidator = blacklistSpendValidatorOpt.get();

                        var blacklistSpendInitParams = ListPlutusData
                                        .of(BytesPlutusData.of(HexUtil.decodeHexString(blacklistNodePolicyId)));
                        var parameterisedBlacklistSpendingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(blacklistSpendInitParams,
                                                        blacklistSpendValidator.scriptBytes()),
                                        PlutusVersion.v3);
                        var blacklistAddress = AddressProvider.getEntAddress(parameterisedBlacklistSpendingScript,
                                        network.getCardanoNetwork());

                        var blacklistUtxos = utxoProvider.findUtxos(blacklistAddress.getAddress());

                        var sortedInputUtxos = Stream.concat(adminUtxos.stream(), inputUtxos.stream())
                                        .sorted(new UtxoComparator())
                                        .toList();

                        var proofs = new ArrayList<Pair<Utxo, Utxo>>();
                        var progTokenBaseScriptHash = protocolParams.programmableLogicBaseParams().scriptHash();
                        for (Utxo utxo : sortedInputUtxos) {
                                var address = new Address(utxo.getAddress());
                                var addressPkh = address.getPaymentCredentialHash().map(HexUtil::encodeHexString).get();
                                if (progTokenBaseScriptHash.equals(addressPkh)) {
                                        var stakingPkh = address.getDelegationCredentialHash()
                                                        .map(HexUtil::encodeHexString).get();
                                        var relevantBlacklistNodeOpt = blacklistUtxos.stream()
                                                        .filter(blackListUtxo -> blacklistNodeParser
                                                                        .parse(blackListUtxo.getInlineDatum())
                                                                        .map(blacklistNode -> blacklistNode.key()
                                                                                        .compareTo(stakingPkh) < 0
                                                                                        && blacklistNode.next()
                                                                                                        .compareTo(stakingPkh) > 0)
                                                                        .orElse(false))
                                                        .findAny();
                                        if (relevantBlacklistNodeOpt.isEmpty()) {
                                                return TransactionContext
                                                                .typedError("could not resolve blacklist exemption");
                                        }
                                        proofs.add(new Pair<>(utxo, relevantBlacklistNodeOpt.get()));
                                }
                        }

<<<<<<< HEAD
                        var registryRefInput = TransactionInput.builder()
                                        .transactionId(progTokenRegistry.getTxHash())
                                        .index(progTokenRegistry.getOutputIndex())
                                        .build();
                        var allRefInputs = new java.util.ArrayList<TransactionInput>();
                        proofs.stream().map(Pair::second).forEach(utxo -> {
                                allRefInputs.add(TransactionInput.builder()
                                                .transactionId(utxo.getTxHash())
                                                .index(utxo.getOutputIndex())
                                                .build());
                        });
                        allRefInputs.add(protocolParamsUtxo);
                        allRefInputs.add(registryRefInput);
                        var sortedReferenceInputs = allRefInputs.stream()
                                        .sorted(new TransactionInputComparator())
                                        .toList();

                        var proofList = proofs.stream().map(pair -> {
                                log.info("first: {}, second: {}", pair.first(), pair.second());
                                var index = sortedReferenceInputs.indexOf(
                                                TransactionInput.builder().transactionId(pair.second().getTxHash())
                                                                .index(pair.second().getOutputIndex()).build());
                                log.info("adding index: {} as a blacklist non-belonging proof", index);
                                return (ConstrPlutusData) ConstrPlutusData.of(0, BigIntPlutusData.of(index));
                        }).toList();
                        var freezeAndSeizeRedeemer = ListPlutusData.of();
                        for (ConstrPlutusData proof : proofList) {
                                freezeAndSeizeRedeemer.add(proof);
                        }

                        var registryIndex = sortedReferenceInputs
                                        .indexOf(TransactionInput.builder().transactionId(progTokenRegistry.getTxHash())
                                                        .index(progTokenRegistry.getOutputIndex()).build());

                        var programmableGlobalRedeemer = ConstrPlutusData.of(0,
                                        // only one prop and it's a list
                                        ListPlutusData.of(ConstrPlutusData.of(0, BigIntPlutusData.of(registryIndex))));

                        var tx = new ScriptTx()
                                        .collectFrom(adminUtxos);

                        inputUtxos.forEach(utxo -> {
                                tx.collectFrom(utxo, ConstrPlutusData.of(0));
                        });

                        log.info("substandardTransferAddress.getAddress(): {}",
                                        substandardTransferAddress.getAddress());
                        log.info("programmableLogicGlobalAddress.getAddress(): {}",
                                        programmableLogicGlobalAddress.getAddress());

                        // // must be first Provide proofs
                        tx.withdraw(substandardTransferAddress.getAddress(), BigInteger.ZERO, freezeAndSeizeRedeemer)
                                        .withdraw(programmableLogicGlobalAddress.getAddress(), BigInteger.ZERO,
                                                        programmableGlobalRedeemer)
                                        .payToContract(senderProgrammableTokenAddress.getAddress(),
                                                        ValueUtil.toAmountList(returningValue), ConstrPlutusData.of(0))
                                        .payToContract(recipientProgrammableTokenAddress.getAddress(),
                                                        ValueUtil.toAmountList(tokenValue2), ConstrPlutusData.of(0));

                        sortedReferenceInputs.forEach(tx::readFrom);

                        tx.attachRewardValidator(programmableLogicGlobal) // global
                                        .attachRewardValidator(parameterisedSubstandardTransferContract)
                                        .attachSpendingValidator(programmableLogicBase) // base
                                        .withChangeAddress(senderAddress.getAddress());

                        var transaction = quickTxBuilder.compose(tx)
                                        .withRequiredSigners(senderAddress.getDelegationCredentialHash().get())
                                        .additionalSignersCount(1)
                                        .feePayer(senderAddress.getAddress())
                                        .mergeOutputs(false)
                                        // .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                                        .build();

                        log.info("tx: {}", transaction.serializeToHex());
                        log.info("tx: {}", objectMapper.writeValueAsString(transaction));

                        return TransactionContext.ok(transaction.serializeToHex());

                } catch (Exception e) {
                        log.warn("error", e);
                        return TransactionContext.typedError("error: " + e.getMessage());
                }

        }

        // ========== BlacklistManageable Implementation ==========

        @Override
        public TransactionContext<MintingResult> buildBlacklistInitTransaction(BlacklistInitRequest request,
                        ProtocolBootstrapParams protocolParams) {

                try {
=======
            var bootstrapTxInput = TransactionInput.builder()
                    .transactionId(bootstrapUtxo.getTxHash())
                    .index(bootstrapUtxo.getOutputIndex())
                    .build();

            var adminPkhBytes = adminAddress.getPaymentCredentialHash().get();
            var adminPks = HexUtil.encodeHexString(adminPkhBytes);

            // Build both blacklist scripts at once
            var blacklistScripts = fesScriptBuilder.buildBlacklistScripts(bootstrapTxInput, adminPks);
            var parameterisedBlacklistMintingScript = blacklistScripts.first();
            var parameterisedBlacklistSpendingScript = blacklistScripts.second();

            var blacklistSpendAddress = AddressProvider.getEntAddress(parameterisedBlacklistSpendingScript, network.getCardanoNetwork());
>>>>>>> upstream/main

                        log.info("blacklistInitRequest: {}", request);

                        var adminAddress = new Address(request.adminAddress());

                        var utilityUtxos = accountService.findAdaOnlyUtxo(request.feePayerAddress(), 2_000_000L);
                        log.info("admin utxos size: {}", utilityUtxos.size());

                        if (utilityUtxos.isEmpty()) {
                                log.error("No UTxOs found for address: {}. Address needs at least 10 ADA in UTxOs with only ADA (no other assets).",
                                                request.feePayerAddress());
                                return TransactionContext.typedError(
                                                "No UTxOs found for address. Please ensure the address has at least 10 ADA in UTxOs containing only ADA (no other assets).");
                        }

                        var utilityAdaBalance = utilityUtxos.stream()
                                        .flatMap(utxo -> utxo.getAmount().stream())
                                        .map(Amount::getQuantity)
                                        .reduce(BigInteger::add)
                                        .orElse(ZERO);

                        log.info("utility ada balance: {}", utilityAdaBalance);

                        var bootstrapUtxo = utilityUtxos.getFirst();
                        log.info("bootstrapUtxo: {}", bootstrapUtxo);

                        // var bootstrapUtxoOpt = utxoProvider.findUtxo(bootstrapUtxo.getTxHash(),
                        // bootstrapUtxo.getOutputIndex());

                        // if (bootstrapUtxoOpt.isEmpty()) {
                        // log.error("UTxO not found when queried: txHash={}, outputIndex={}",
                        // bootstrapUtxo.getTxHash(), bootstrapUtxo.getOutputIndex());
                        // return TransactionContext.typedError("UTxO not found. The UTxO may have been
                        // spent. Please try again.");
                        // }
                        // Use the UTxO we already have - no need to query it again
                        // The UTxO from findAdaOnlyUtxo is already valid and contains all needed
                        // information

                        var blackListMintValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "blacklist_mint.blacklist_mint.mint");
                        var blackListMintValidator = blackListMintValidatorOpt.get();

                        var serialisedTxInput = PlutusSerializationHelper.serialize(TransactionInput.builder()
                                        .transactionId(bootstrapUtxo.getTxHash())
                                        .index(bootstrapUtxo.getOutputIndex())
                                        .build());

                        var adminPkhBytes = adminAddress.getPaymentCredentialHash().get();
                        var adminPks = HexUtil.encodeHexString(adminPkhBytes);
                        var blacklistMintInitParams = ListPlutusData.of(serialisedTxInput,
                                        BytesPlutusData.of(adminPkhBytes));

                        var parameterisedBlacklistMintingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(blacklistMintInitParams,
                                                        blackListMintValidator.scriptBytes()),
                                        PlutusVersion.v3);

                        var blacklistSpendValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "blacklist_spend.blacklist_spend.spend");
                        var blacklistSpendValidator = blacklistSpendValidatorOpt.get();

                        var blacklistSpendInitParams = ListPlutusData.of(BytesPlutusData.of(
                                        HexUtil.decodeHexString(parameterisedBlacklistMintingScript.getPolicyId())));
                        var parameterisedBlacklistSpendingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(blacklistSpendInitParams,
                                                        blacklistSpendValidator.scriptBytes()),
                                        PlutusVersion.v3);
                        var blacklistSpendAddress = AddressProvider.getEntAddress(parameterisedBlacklistSpendingScript,
                                        network.getCardanoNetwork());

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
                                                                        .policyId(parameterisedBlacklistMintingScript
                                                                                        .getPolicyId())
                                                                        .assets(List.of(blacklistNft))
                                                                        .build()))
                                        .build();

                        var tx = new ScriptTx()
                                        .collectFrom(utilityUtxos)
                                        .mintAsset(parameterisedBlacklistMintingScript, blacklistAsset,
                                                        ConstrPlutusData.of(0))
                                        .payToContract(blacklistSpendAddress.getAddress(),
                                                        ValueUtil.toAmountList(blacklistValue),
                                                        blacklistInitDatum.toPlutusData())
                                        .withChangeAddress(request.feePayerAddress());

                        var transaction = quickTxBuilder.compose(tx)
                                        .feePayer(request.feePayerAddress())
                                        .mergeOutputs(false)
                                        .build();

                        log.info("transaction: {}", transaction.serializeToHex());
                        log.info("transaction: {}", objectMapper.writeValueAsString(transaction));

                        var mintBootstrap = new BlacklistMintBootstrap(TxInput.from(bootstrapUtxo), adminPks,
                                        parameterisedBlacklistMintingScript.getPolicyId());
                        var spendBootstrap = new BlacklistSpendBootstrap(
                                        parameterisedBlacklistMintingScript.getPolicyId(),
                                        parameterisedBlacklistSpendingScript.getPolicyId());
                        var bootstrap = new BlacklistBootstrap(mintBootstrap, spendBootstrap);

                        var stringBoostrap = objectMapper.writeValueAsString(bootstrap);
                        log.info("bootstrap: {}", stringBoostrap);

                        blacklistInitRepository.save(BlacklistInitEntity.builder()
                                        .blacklistNodePolicyId(parameterisedBlacklistMintingScript.getPolicyId())
                                        .adminPkh(adminPks)
                                        .txHash(bootstrapUtxo.getTxHash())
                                        .outputIndex(bootstrapUtxo.getOutputIndex())
                                        .build());

                        return TransactionContext.ok(transaction.serializeToHex(),
                                        new MintingResult(parameterisedBlacklistMintingScript.getPolicyId(), ""));

                } catch (Exception e) {
                        return TransactionContext
                                        .typedError(String.format("could not build transaction: %s", e.getMessage()));
                }

        }

        @Override
        public TransactionContext<Void> buildAddToBlacklistTransaction(AddToBlacklistRequest request,
                        ProtocolBootstrapParams protocolParams) {

                try {
                        log.info("addToBlacklistRequest: {}", request);

                        var blacklistedAddress = new Address(request.targetAddress());
                        var feePayerAddr = request.feePayerAddress();
                        log.info("Checking UTXOs for fee payer address: {}", feePayerAddr);

                        // Validate that fee payer is the blacklist manager
                        // The blacklist spend validator requires the blacklist manager's signature
                        var feePayerAddressObj = new Address(feePayerAddr);
                        var feePayerPkhOpt = feePayerAddressObj.getPaymentCredentialHash()
                                        .map(HexUtil::encodeHexString);

                        if (feePayerPkhOpt.isEmpty()) {
                                return TransactionContext.typedError(
                                                "Could not extract payment key hash from fee payer address. Please ensure you're using a valid payment address.");
                        }

<<<<<<< HEAD
                        var feePayerPkh = feePayerPkhOpt.get();
                        var blacklistManagerPkh = context.getBlacklistManagerPkh();

                        if (!feePayerPkh.equalsIgnoreCase(blacklistManagerPkh)) {
                                log.error("Fee payer {} does not match blacklist manager {}", feePayerPkh,
                                                blacklistManagerPkh);
                                return TransactionContext.typedError(
                                                String.format("The connected wallet (fee payer) is not the blacklist manager for this token. "
                                                                +
                                                                "Blacklist manager PKH: %s, Fee payer PKH: %s. " +
                                                                "Please connect with the wallet that initialized the blacklist for this token.",
                                                                blacklistManagerPkh, feePayerPkh));
                        }
=======
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

            // Build both blacklist scripts at once
            var blacklistScripts = fesScriptBuilder.buildBlacklistScripts(
                    context.getBlacklistInitTxInput(),
                    context.getIssuerAdminPkh()
            );
            var parameterisedBlacklistMintingScript = blacklistScripts.first();
            var parameterisedBlacklistSpendingScript = blacklistScripts.second();
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
>>>>>>> upstream/main

                        log.info("Fee payer {} matches blacklist manager, proceeding with transaction", feePayerPkh);

<<<<<<< HEAD
                        // For blacklist operations, use ADA-only UTXOs from the fee payer address.
                        // This ensures we only use UTXOs the wallet can definitely sign for.
                        // We need at least 2 ADA for fees and transaction costs.
                        var allAdminUtxos = accountService.findAdaOnlyUtxo(feePayerAddr, 2_000_000L);
=======
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

            // Build both blacklist scripts at once
            var blacklistScripts = fesScriptBuilder.buildBlacklistScripts(
                    context.getBlacklistInitTxInput(),
                    context.getIssuerAdminPkh()
            );
            var parameterisedBlacklistMintingScript = blacklistScripts.first();
            var parameterisedBlacklistSpendingScript = blacklistScripts.second();
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
>>>>>>> upstream/main

                        if (allAdminUtxos.isEmpty()) {
                                log.error("No ADA-only UTXOs found for address: {} on network: {}", feePayerAddr,
                                                network);
                                return TransactionContext.typedError(
                                                String.format("No ADA-only UTXOs found for admin address %s on %s network. Please ensure: 1) Your wallet is connected to the %s network, 2) The address has been funded with at least 2 ADA in UTXOs containing only ADA (no other assets), 3) Wait a few seconds after funding for the UTXO to be indexed.",
                                                                feePayerAddr, network, network));
                        }

                        // Filter to ensure ALL UTXOs are from the exact fee payer address
                        // This is critical - UTXOs from different addresses (even with same payment
                        // key)
                        // might require different signatures that the wallet can't provide
                        var adminUtxos = allAdminUtxos.stream()
                                        .filter(utxo -> {
                                                var utxoAddr = utxo.getAddress();
                                                var matches = feePayerAddr.equals(utxoAddr);
                                                if (!matches) {
                                                        log.warn("Filtering UTXO from different address: {} (expected: {})",
                                                                        utxoAddr, feePayerAddr);
                                                }
                                                return matches;
                                        })
                                        .toList();

                        if (adminUtxos.isEmpty()) {
                                log.error("No UTXOs found matching exact fee payer address: {}", feePayerAddr);
                                return TransactionContext.typedError(
                                                String.format("No UTXOs found matching exact fee payer address %s. This may indicate an address mismatch. Please ensure you're using the correct wallet address.",
                                                                feePayerAddr));
                        }

                        log.info("admin utxos size: {} (filtered from {} total, all from address: {})",
                                        adminUtxos.size(), allAdminUtxos.size(), feePayerAddr);

                        // Log UTXO addresses for debugging and select collateral
                        Utxo collateralUtxo = null;
                        List<Utxo> feePayerUtxos = new ArrayList<>();

                        for (Utxo utxo : adminUtxos) {
                                log.debug("Using UTXO: {} from address: {}",
                                                utxo.getTxHash() + "#" + utxo.getOutputIndex(),
                                                utxo.getAddress());

                                // Check if UTXO has >= 5 ADA (5,000,000 lovelace)
                                boolean hasEnoughAda = utxo.getAmount().stream()
                                                .anyMatch(a -> "lovelace".equals(a.getUnit()) &&
                                                                a.getQuantity().compareTo(new java.math.BigInteger(
                                                                                "5000000")) >= 0);

                                if (collateralUtxo == null && hasEnoughAda) {
                                        collateralUtxo = utxo;
                                } else {
                                        feePayerUtxos.add(utxo);
                                }
                        }

                        if (collateralUtxo == null) {
                                log.error("No suitable collateral UTXO (> 5 ADA) found");
                                return TransactionContext.typedError("Insufficient collateral: No UTXO > 5 ADA found.");
                        }

                        var collateralInput = TransactionInput.builder()
                                        .transactionId(collateralUtxo.getTxHash())
                                        .index(collateralUtxo.getOutputIndex())
                                        .build();
                        var adminAdaBalance = feePayerUtxos.stream()
                                        .flatMap(utxo -> utxo.getAmount().stream())
                                        .map(Amount::getQuantity)
                                        .reduce(BigInteger::add)
                                        .orElse(ZERO);
                        log.info("admin ada balance: {}", adminAdaBalance);

                        var blackListMintValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "blacklist_mint.blacklist_mint.mint");
                        var blackListMintValidator = blackListMintValidatorOpt.get();

                        var serialisedTxInput = PlutusSerializationHelper.serialize(TransactionInput.builder()
                                        .transactionId(context.getBlacklistInitTxInput().getTransactionId())
                                        .index(context.getBlacklistInitTxInput().getIndex())
                                        .build());

                        var blacklistMintInitParams = ListPlutusData.of(serialisedTxInput,
                                        BytesPlutusData.of(HexUtil.decodeHexString(context.getIssuerAdminPkh())));

                        var parameterisedBlacklistMintingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(blacklistMintInitParams,
                                                        blackListMintValidator.scriptBytes()),
                                        PlutusVersion.v3);

                        var blacklistSpendValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "blacklist_spend.blacklist_spend.spend");
                        var blacklistSpendValidator = blacklistSpendValidatorOpt.get();

                        var blacklistSpendInitParams = ListPlutusData.of(BytesPlutusData.of(
                                        HexUtil.decodeHexString(parameterisedBlacklistMintingScript.getPolicyId())));
                        var parameterisedBlacklistSpendingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(blacklistSpendInitParams,
                                                        blacklistSpendValidator.scriptBytes()),
                                        PlutusVersion.v3);
                        log.info("parameterisedBlacklistSpendingScript: {}",
                                        parameterisedBlacklistSpendingScript.getPolicyId());

                        var blacklistSpendAddress = AddressProvider.getEntAddress(parameterisedBlacklistSpendingScript,
                                        network.getCardanoNetwork());
                        log.info("blacklistSpend: {}", blacklistSpendAddress.getAddress());

                        var blacklistUtxos = utxoProvider.findUtxos(blacklistSpendAddress.getAddress());
                        log.info("blacklistUtxos: {}", blacklistUtxos.size());
                        blacklistUtxos.forEach(utxo -> log.info("bl utxo: {}", utxo));

                        var aliceStakingPkh = blacklistedAddress.getDelegationCredentialHash()
                                        .map(HexUtil::encodeHexString).get();
                        var blocklistNodeToReplaceOpt = blacklistUtxos.stream()
                                        .flatMap(utxo -> blacklistNodeParser.parse(utxo.getInlineDatum())
                                                        .stream()
                                                        .flatMap(blacklistNode -> Stream
                                                                        .of(new Pair<>(utxo, blacklistNode))))
                                        .filter(utxoBlacklistNodePair -> {
                                                var datum = utxoBlacklistNodePair.second();
                                                return datum.key().compareTo(aliceStakingPkh) < 0
                                                                && aliceStakingPkh.compareTo(datum.next()) < 0;
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

                        var mintRedeemer = ConstrPlutusData.of(1,
                                        BytesPlutusData.of(HexUtil.decodeHexString(aliceStakingPkh)));

                        // Before/Updated
                        var preExistingAmount = blocklistNodeToReplace.first().getAmount();
                        // Next/minted
                        var mintedAmount = Value.from(parameterisedBlacklistMintingScript.getPolicyId(),
                                        "0x" + aliceStakingPkh, ONE);

                        var tx = new ScriptTx()
                                        .collectFrom(feePayerUtxos)
                                        .collectFrom(blocklistNodeToReplace.first(), ConstrPlutusData.of(0))
                                        .mintAsset(parameterisedBlacklistMintingScript,
                                                        Asset.builder().name("0x" + aliceStakingPkh).value(ONE).build(),
                                                        mintRedeemer)
                                        // Replaced
                                        .payToContract(blacklistSpendAddress.getAddress(), preExistingAmount,
                                                        beforeNode.toPlutusData())
                                        .payToContract(blacklistSpendAddress.getAddress(),
                                                        ValueUtil.toAmountList(mintedAmount), afterNode.toPlutusData())
                                        .attachSpendingValidator(parameterisedBlacklistSpendingScript)
                                        .withChangeAddress(request.feePayerAddress());

                        // Fee payer has already been validated to be the blacklist manager above
                        // So we only need one signature (the fee payer/blacklist manager)
                        log.info("Requiring signature from fee payer/blacklist manager: {}", feePayerPkh);
                        log.info("Transaction inputs: {} admin UTXOs (payment-locked) + 1 blacklist node (script-locked)",
                                        feePayerUtxos.size());

                        var transaction = quickTxBuilder.compose(tx)
                                        .withCollateralInputs(collateralInput)
                                        .withRequiredSigners(HexUtil.decodeHexString(feePayerPkh))
                                        .feePayer(request.feePayerAddress())
                                        // .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                                        .mergeOutputs(false)
                                        .build();

                        log.info("Transaction built. Total inputs: {}, Total outputs: {}, Required signers count: {}",
                                        transaction.getBody().getInputs().size(),
                                        transaction.getBody().getOutputs().size(),
                                        transaction.getBody().getRequiredSigners() != null
                                                        ? transaction.getBody().getRequiredSigners().size()
                                                        : 0);
                        log.info("transaction: {}", transaction.serializeToHex());

                        return TransactionContext.ok(transaction.serializeToHex());

                } catch (Exception e) {
                        return TransactionContext.error(String.format("error: %s", e.getMessage()));

                }

<<<<<<< HEAD
=======
    }

    /**
     * Check if an address is currently blacklisted.
     * This is a read-only query operation that checks the on-chain blacklist linked-list.
     *
     * @param address The bech32 address to check
     * @return true if the address is blacklisted (frozen), false otherwise
     */
    public boolean isAddressBlacklisted(String address) {
        try {
            log.debug("Checking blacklist status for address: {}", address);

            // 1. Extract stake credential from address (same as add/remove operations)
            var targetAddress = new Address(address);
            var credentialHashOpt = targetAddress.getDelegationCredentialHash()
                    .map(HexUtil::encodeHexString);

            if (credentialHashOpt.isEmpty()) {
                log.debug("Address {} has no stake credential", address);
                return false; // No stake credential = cannot be blacklisted
            }

            var credentialHash = credentialHashOpt.get();
            log.debug("Extracted stake credential: {}", credentialHash);

            // 2. Derive blacklist mint and spend scripts
            var blacklistScripts = fesScriptBuilder.buildBlacklistScripts(
                    context.getBlacklistInitTxInput(),
                    context.getIssuerAdminPkh()
            );
            var parameterisedBlacklistMintingScript = blacklistScripts.first();
            var parameterisedBlacklistSpendingScript = blacklistScripts.second();
            var blacklistPolicyId = parameterisedBlacklistMintingScript.getPolicyId();
            log.debug("Derived blacklist policy ID: {}", blacklistPolicyId);

            // 3. Compute blacklist spend address
            var blacklistSpendAddress = AddressProvider.getEntAddress(
                    parameterisedBlacklistSpendingScript,
                    network.getCardanoNetwork()
            );
            log.debug("Derived blacklist spend address: {}", blacklistSpendAddress.getAddress());

            // 5. Query UTxOs at blacklist address
            var blacklistUtxos = utxoProvider.findUtxos(blacklistSpendAddress.getAddress());
            log.debug("Found {} blacklist UTxOs", blacklistUtxos.size());

            // 6. Parse datums and check if credential is in the list
            boolean isBlacklisted = blacklistUtxos.stream()
                    .flatMap(utxo -> blacklistNodeParser.parse(utxo.getInlineDatum()).stream())
                    .anyMatch(blacklistNode -> blacklistNode.key().equals(credentialHash));

            log.debug("Address {} is blacklisted: {}", address, isBlacklisted);
            return isBlacklisted;

        } catch (Exception e) {
            log.error("Error checking blacklist status for address: {}", address, e);
            // Fail-safe: return false to avoid blocking legitimate users
            return false;
>>>>>>> upstream/main
        }

        @Override
        public TransactionContext<Void> buildRemoveFromBlacklistTransaction(
                        RemoveFromBlacklistRequest request,
                        ProtocolBootstrapParams protocolParams) {

                try {

                        var targetAddress = new Address(request.targetAddress());
                        var feePayerAddr = request.feePayerAddress();
                        log.info("Checking UTXOs for fee payer address: {}", feePayerAddr);

                        // Validate that fee payer is the blacklist manager
                        // The blacklist spend validator requires the blacklist manager's signature
                        var feePayerAddressObj = new Address(feePayerAddr);
                        var feePayerPkhOpt = feePayerAddressObj.getPaymentCredentialHash()
                                        .map(HexUtil::encodeHexString);

<<<<<<< HEAD
                        if (feePayerPkhOpt.isEmpty()) {
                                return TransactionContext.typedError(
                                                "Could not extract payment key hash from fee payer address. Please ensure you're using a valid payment address.");
                        }

                        var feePayerPkh = feePayerPkhOpt.get();
                        var blacklistManagerPkh = context.getBlacklistManagerPkh();

                        if (!feePayerPkh.equalsIgnoreCase(blacklistManagerPkh)) {
                                log.error("Fee payer {} does not match blacklist manager {}", feePayerPkh,
                                                blacklistManagerPkh);
                                return TransactionContext.typedError(
                                                String.format("The connected wallet (fee payer) is not the blacklist manager for this token. "
                                                                +
                                                                "Blacklist manager PKH: %s, Fee payer PKH: %s. " +
                                                                "Please connect with the wallet that initialized the blacklist for this token.",
                                                                blacklistManagerPkh, feePayerPkh));
                        }
=======
            log.info("request: {}", request);

            var feePayerAddress = new Address(request.feePayerAddress());
            var feePayerPkh = feePayerAddress.getPaymentCredentialHash().map(HexUtil::encodeHexString).get();

            var adminUtxos = accountService.findAdaOnlyUtxoByPaymentPubKeyHash(feePayerPkh, 10_000_000L);
            log.info("adminUtxos: {}", adminUtxos);
>>>>>>> upstream/main

                        log.info("Fee payer {} matches blacklist manager, proceeding with transaction", feePayerPkh);

                        // Use ADA-only UTXOs from the fee payer address for remove-from-blacklist
                        // operations.
                        // This ensures we only use UTXOs the wallet can definitely sign for.
                        // We need at least 2 ADA for fees and transaction costs.
                        var allAdminUtxos = accountService.findAdaOnlyUtxo(feePayerAddr, 2_000_000L);

                        if (allAdminUtxos.isEmpty()) {
                                log.error("No ADA-only UTXOs found for address: {} on network: {}", feePayerAddr,
                                                network);
                                return TransactionContext.typedError(
                                                String.format("No ADA-only UTXOs found for admin address %s on %s network. Please ensure: 1) Your wallet is connected to the %s network, 2) The address has been funded with at least 2 ADA in UTXOs containing only ADA (no other assets), 3) Wait a few seconds after funding for the UTXO to be indexed.",
                                                                feePayerAddr, network, network));
                        }

                        // Filter to ensure ALL UTXOs are from the exact fee payer address
                        // This is critical - UTXOs from different addresses (even with same payment
                        // key)
                        // might require different signatures that the wallet can't provide
                        var adminUtxos = allAdminUtxos.stream()
                                        .filter(utxo -> {
                                                var utxoAddr = utxo.getAddress();
                                                var matches = feePayerAddr.equals(utxoAddr);
                                                if (!matches) {
                                                        log.warn("Filtering UTXO from different address: {} (expected: {})",
                                                                        utxoAddr, feePayerAddr);
                                                }
                                                return matches;
                                        })
                                        .toList();

                        if (adminUtxos.isEmpty()) {
                                log.error("No UTXOs found matching exact fee payer address: {}", feePayerAddr);
                                return TransactionContext.typedError(
                                                String.format("No UTXOs found matching exact fee payer address %s. This may indicate an address mismatch. Please ensure you're using the correct wallet address.",
                                                                feePayerAddr));
                        }

                        log.info("admin utxos size: {} (filtered from {} total, all from address: {})",
                                        adminUtxos.size(), allAdminUtxos.size(), feePayerAddr);

                        var blackListMintValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "blacklist_mint.blacklist_mint.mint");
                        var blackListMintValidator = blackListMintValidatorOpt.get();

                        var serialisedTxInput = PlutusSerializationHelper.serialize(TransactionInput.builder()
                                        .transactionId(context.getBlacklistInitTxInput().getTransactionId())
                                        .index(context.getBlacklistInitTxInput().getIndex())
                                        .build());

                        var blacklistMintInitParams = ListPlutusData.of(serialisedTxInput,
                                        BytesPlutusData.of(HexUtil.decodeHexString(context.getIssuerAdminPkh())));

                        var parameterisedBlacklistMintingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(blacklistMintInitParams,
                                                        blackListMintValidator.scriptBytes()),
                                        PlutusVersion.v3);

                        var blacklistSpendValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "blacklist_spend.blacklist_spend.spend");
                        var blacklistSpendValidator = blacklistSpendValidatorOpt.get();

                        var blacklistSpendInitParams = ListPlutusData.of(BytesPlutusData.of(
                                        HexUtil.decodeHexString(parameterisedBlacklistMintingScript.getPolicyId())));
                        var parameterisedBlacklistSpendingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(blacklistSpendInitParams,
                                                        blacklistSpendValidator.scriptBytes()),
                                        PlutusVersion.v3);
                        log.info("parameterisedBlacklistSpendingScript: {}",
                                        parameterisedBlacklistSpendingScript.getPolicyId());

                        var blacklistSpendAddress = AddressProvider.getEntAddress(parameterisedBlacklistSpendingScript,
                                        network.getCardanoNetwork());
                        log.info("blacklistSpend: {}", blacklistSpendAddress.getAddress());

                        var blacklistUtxos = utxoProvider.findUtxos(blacklistSpendAddress.getAddress());
                        log.info("blacklistUtxos: {}", blacklistUtxos.size());
                        blacklistUtxos.forEach(utxo -> log.info("bl utxo: {}", utxo));

                        var credentialsToRemove = targetAddress.getDelegationCredentialHash()
                                        .map(HexUtil::encodeHexString).get();

                        var blocklistNodeToRemoveOpt = blacklistUtxos.stream()
                                        .flatMap(utxo -> blacklistNodeParser.parse(utxo.getInlineDatum())
                                                        .stream()
                                                        .flatMap(blacklistNode -> Stream
                                                                        .of(new Pair<>(utxo, blacklistNode))))
                                        .filter(utxoBlacklistNodePair -> {
                                                var datum = utxoBlacklistNodePair.second();
                                                return datum.key().equals(credentialsToRemove);
                                        })
                                        .findAny();

                        var blocklistNodeToUpdateOpt = blacklistUtxos.stream()
                                        .flatMap(utxo -> blacklistNodeParser.parse(utxo.getInlineDatum())
                                                        .stream()
                                                        .flatMap(blacklistNode -> Stream
                                                                        .of(new Pair<>(utxo, blacklistNode))))
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

                        var mintRedeemer = ConstrPlutusData.of(2,
                                        BytesPlutusData.of(HexUtil.decodeHexString(credentialsToRemove)));

                        // Before/Updated
                        var preExistingAmount = blocklistNodeToUpdate.first().getAmount();

                        var tx = new ScriptTx()
                                        .collectFrom(adminUtxos)
                                        .collectFrom(blocklistNodeToRemove.first(), ConstrPlutusData.of(0))
                                        .collectFrom(blocklistNodeToUpdate.first(), ConstrPlutusData.of(0))
                                        .mintAsset(parameterisedBlacklistMintingScript,
                                                        Asset.builder().name("0x" + credentialsToRemove)
                                                                        .value(ONE.negate()).build(),
                                                        mintRedeemer)
                                        // Replaced
                                        .payToContract(blacklistSpendAddress.getAddress(), preExistingAmount,
                                                        updatedNode.toPlutusData())
                                        .attachSpendingValidator(parameterisedBlacklistSpendingScript)
                                        .withChangeAddress(request.feePayerAddress());

                        // Fee payer has already been validated to be the blacklist manager above
                        // So we only need one signature (the fee payer/blacklist manager)
                        log.info("Requiring signature from fee payer/blacklist manager: {}", feePayerPkh);

                        var transaction = quickTxBuilder.compose(tx)
                                        .withRequiredSigners(HexUtil.decodeHexString(feePayerPkh))
                                        .feePayer(request.feePayerAddress())
                                        // .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                                        .mergeOutputs(false)
                                        .build();

                        log.info("transaction: {}", transaction.serializeToHex());
                        log.info("transaction: {}", objectMapper.writeValueAsString(transaction));

                        return TransactionContext.ok(transaction.serializeToHex());

                } catch (Exception e) {
                        return TransactionContext.error(String.format("error: %s", e.getMessage()));

                }

        }

        /**
         * Check if an address is currently blacklisted.
         * This is a read-only query operation that checks the on-chain blacklist
         * linked-list.
         *
         * @param address The bech32 address to check
         * @return true if the address is blacklisted (frozen), false otherwise
         */
        public boolean isAddressBlacklisted(String address) {
                try {
                        log.debug("Checking blacklist status for address: {}", address);

                        // 1. Extract stake credential from address (same as add/remove operations)
                        var targetAddress = new Address(address);
                        var credentialHashOpt = targetAddress.getDelegationCredentialHash()
                                        .map(HexUtil::encodeHexString);

                        if (credentialHashOpt.isEmpty()) {
                                log.debug("Address {} has no stake credential", address);
                                return false; // No stake credential = cannot be blacklisted
                        }

                        var credentialHash = credentialHashOpt.get();
                        log.debug("Extracted stake credential: {}", credentialHash);

<<<<<<< HEAD
                        // 2. Derive blacklist mint script (parameterized with init tx + admin pkh)
                        var blackListMintValidatorOpt = substandardService.getSubstandardValidator(
                                        SUBSTANDARD_ID,
                                        "blacklist_mint.blacklist_mint.mint");
                        if (blackListMintValidatorOpt.isEmpty()) {
                                log.warn("Blacklist mint validator not found for substandard: {}", SUBSTANDARD_ID);
                                return false;
                        }
                        var blackListMintValidator = blackListMintValidatorOpt.get();

                        // Serialize the blacklist init transaction input
                        var serialisedTxInput = PlutusSerializationHelper.serialize(TransactionInput.builder()
                                        .transactionId(context.getBlacklistInitTxInput().getTransactionId())
                                        .index(context.getBlacklistInitTxInput().getIndex())
                                        .build());

                        // Parameters: [txInput, adminPkh]
                        var blacklistMintInitParams = ListPlutusData.of(
                                        serialisedTxInput,
                                        BytesPlutusData.of(HexUtil.decodeHexString(context.getIssuerAdminPkh())));

                        // Apply parameters to get the policy ID
                        var parameterisedBlacklistMintingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(blacklistMintInitParams,
                                                        blackListMintValidator.scriptBytes()),
                                        PlutusVersion.v3);
                        var blacklistPolicyId = parameterisedBlacklistMintingScript.getPolicyId();
                        log.debug("Derived blacklist policy ID: {}", blacklistPolicyId);

                        // 3. Derive blacklist spend script (parameterized with policy ID)
                        var blacklistSpendValidatorOpt = substandardService.getSubstandardValidator(
                                        SUBSTANDARD_ID,
                                        "blacklist_spend.blacklist_spend.spend");
                        if (blacklistSpendValidatorOpt.isEmpty()) {
                                log.warn("Blacklist spend validator not found for substandard: {}", SUBSTANDARD_ID);
                                return false;
                        }
                        var blacklistSpendValidator = blacklistSpendValidatorOpt.get();

                        // Parameter: [blacklistPolicyId]
                        var blacklistSpendInitParams = ListPlutusData.of(
                                        BytesPlutusData.of(HexUtil.decodeHexString(blacklistPolicyId)));

                        var parameterisedBlacklistSpendingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(blacklistSpendInitParams,
                                                        blacklistSpendValidator.scriptBytes()),
                                        PlutusVersion.v3);

                        // 4. Compute blacklist spend address
                        var blacklistSpendAddress = AddressProvider.getEntAddress(
                                        parameterisedBlacklistSpendingScript,
                                        network.getCardanoNetwork());
                        log.debug("Derived blacklist spend address: {}", blacklistSpendAddress.getAddress());

                        // 5. Query UTxOs at blacklist address
                        var blacklistUtxos = utxoProvider.findUtxos(blacklistSpendAddress.getAddress());
                        log.debug("Found {} blacklist UTxOs", blacklistUtxos.size());

                        // 6. Parse datums and check if credential is in the list
                        boolean isBlacklisted = blacklistUtxos.stream()
                                        .flatMap(utxo -> blacklistNodeParser.parse(utxo.getInlineDatum()).stream())
                                        .anyMatch(blacklistNode -> blacklistNode.key().equals(credentialHash));

                        log.debug("Address {} is blacklisted: {}", address, isBlacklisted);
                        return isBlacklisted;

                } catch (Exception e) {
                        log.error("Error checking blacklist status for address: {}", address, e);
                        // Fail-safe: return false to avoid blocking legitimate users
                        return false;
                }
        }

        // ========== Seizeable Implementation ==========

        @Override
        public TransactionContext<Void> buildSeizeTransaction(
                        SeizeRequest request,
                        ProtocolBootstrapParams protocolParams) {

                try {
=======
            // Issuer to be used for minting/burning/sieze
            log.info("context.getIssuerAdminPkh(): {}", context.getIssuerAdminPkh());
            var adminPkh = Credential.fromKey(context.getIssuerAdminPkh());
            var substandardIssueAdminContract = fesScriptBuilder.buildIssuerAdminScript(Credential.fromKey(context.getIssuerAdminPkh()));
            log.info("substandardIssueAdminContract: {}", substandardIssueAdminContract.getPolicyId());
>>>>>>> upstream/main

                        // Use all UTxOs for blacklist seizing operations as well, via address lookup
                        var adminUtxos = utxoProvider.findUtxos(request.feePayerAddress());

                        if (adminUtxos.isEmpty()) {
                                log.error("No admin UTXOs found");
                                return TransactionContext.typedError(
                                                "No UTXOs found for admin address. Please ensure the address has sufficient ADA.");
                        }

                        Utxo collateralUtxo = null;
                        List<Utxo> feePayerUtxos = new ArrayList<>();

                        for (Utxo utxo : adminUtxos) {
                                // For seize, we fetched ALL UTXOs. We need ADA-only for collateral.
                                boolean isAdaOnly = utxo.getAmount().size() == 1 &&
                                                utxo.getAmount().get(0).getUnit().equals("lovelace");

                                // Check if UTXO has >= 5 ADA (5,000,000 lovelace)
                                boolean hasEnoughAda = isAdaOnly &&
                                                utxo.getAmount().get(0).getQuantity()
                                                                .compareTo(new java.math.BigInteger("5000000")) >= 0;

                                if (collateralUtxo == null && hasEnoughAda) {
                                        collateralUtxo = utxo;
                                } else {
                                        feePayerUtxos.add(utxo);
                                }
                        }

                        if (collateralUtxo == null) {
                                return TransactionContext
                                                .typedError("Insufficient collateral: No ADA-only UTXO > 5 ADA found.");
                        }

                        var collateralInput = TransactionInput.builder()
                                        .transactionId(collateralUtxo.getTxHash())
                                        .index(collateralUtxo.getOutputIndex())
                                        .build();

                        var feePayerAddress = new Address(request.feePayerAddress());

                        var bootstrapTxHash = protocolParams.txHash();

                        var progToken = AssetType.fromUnit(request.unit());
                        log.info("policy id: {}, asset name: {}", progToken.policyId(),
                                        progToken.unsafeHumanAssetName());

                        // Directory SPEND parameterization
                        var registrySpendContract = protocolScriptBuilderService
                                        .getParameterizedDirectorySpendScript(protocolParams);
                        log.info("registrySpendContract: {}",
                                        HexUtil.encodeHexString(registrySpendContract.getScriptHash()));

                        var registryAddress = AddressProvider.getEntAddress(registrySpendContract,
                                        network.getCardanoNetwork());
                        log.info("registryAddress: {}", registryAddress.getAddress());

                        var registryEntries = utxoProvider.findUtxos(registryAddress.getAddress());
                        log.info("Found {} registry entries at address: {} (seize operation)", registryEntries.size(),
                                        registryAddress.getAddress());

                        var progTokenRegistryOpt = registryEntries.stream()
                                        .filter(utxo -> {
                                                var registryDatumOpt = registryNodeParser.parse(utxo.getInlineDatum());
                                                return registryDatumOpt
                                                                .map(registryDatum -> registryDatum.key()
                                                                                .equals(progToken.policyId()))
                                                                .orElse(false);
                                        })
                                        .findAny();

                        if (progTokenRegistryOpt.isEmpty()) {
                                log.error("Token not found in registry (seize operation). PolicyId: {}, AssetName: {}, Registry entries found: {}",
                                                progToken.policyId(), progToken.unsafeHumanAssetName(),
                                                registryEntries.size());
                                if (registryEntries.isEmpty()) {
                                        return TransactionContext.typedError(
                                                        String.format("Registry is empty. Token with policy ID %s may not be registered. Please ensure the token is registered in the protocol registry.",
                                                                        progToken.policyId()));
                                } else {
                                        return TransactionContext.typedError(
                                                        String.format("Token with policy ID %s not found in registry. Found %d registry entries but none match this token. Please verify the token is registered and the policy ID is correct.",
                                                                        progToken.policyId(), registryEntries.size()));
                                }
                        }

                        var progTokenRegistry = progTokenRegistryOpt.get();
                        log.info("progTokenRegistry: {}", progTokenRegistry);

                        var registryOpt = registryNodeParser.parse(progTokenRegistry.getInlineDatum());
                        if (registryOpt.isEmpty()) {
                                log.error("Failed to parse registry datum for token (seize operation). PolicyId: {}, UTxO: {}#{}",
                                                progToken.policyId(), progTokenRegistry.getTxHash(),
                                                progTokenRegistry.getOutputIndex());
                                return TransactionContext.typedError(
                                                String.format("Failed to parse registry entry for token with policy ID %s. The registry entry may be corrupted.",
                                                                progToken.policyId()));
                        }

                        var registry = registryOpt.get();
                        log.info("registry: {}", registry);

                        // Use the actual protocol params UTxO transaction hash from bootstrap
                        // Note: This UTxO may be spent (used as reference input), so we construct
                        // TransactionInput directly
                        var protocolParamsTxHash = protocolParams.protocolParams().txInput().txHash();
                        var protocolParamsOutputIndex = protocolParams.protocolParams().txInput().outputIndex();
                        log.info("Using protocol params reference input: txHash={}, outputIndex={}",
                                        protocolParamsTxHash, protocolParamsOutputIndex);
                        var protocolParamsUtxo = TransactionInput.builder()
                                        .transactionId(protocolParamsTxHash)
                                        .index(protocolParamsOutputIndex)
                                        .build();

                        var utxoOpt = utxoProvider.findUtxo(request.utxoTxHash(), request.utxoOutputIndex());

                        if (utxoOpt.isEmpty()) {
                                return TransactionContext.typedError("could not find utxo to seize");
                        }

<<<<<<< HEAD
                        var utxoToSeize = utxoOpt.get();

                        // var seizedAddress = aliceAccount.getBaseAddress();
                        // var seizedProgrammableTokenAddress =
                        // AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                        // seizedAddress.getDelegationCredential().get(),
                        // network);

                        var recipientAddress = new Address(request.destinationAddress());
                        var recipientProgrammableTokenAddress = AddressProvider.getBaseAddress(
                                        Credential.fromScript(
                                                        protocolParams.programmableLogicBaseParams().scriptHash()),
                                        recipientAddress.getDelegationCredential().get(),
                                        network.getCardanoNetwork());

                        // // Programmable Logic Global parameterization
                        var programmableLogicGlobal = protocolScriptBuilderService
                                        .getParameterizedProgrammableLogicGlobalScript(protocolParams);
                        var programmableLogicGlobalAddress = AddressProvider.getRewardAddress(programmableLogicGlobal,
                                        network.getCardanoNetwork());
                        log.info("programmableLogicGlobalAddress policy: {}",
                                        programmableLogicGlobalAddress.getAddress());
                        log.info("protocolBootstrapParams.programmableLogicGlobalPrams().scriptHash(): {}",
                                        protocolParams.programmableLogicGlobalPrams().scriptHash());
                        //
                        //// // Programmable Logic Base parameterization
                        var programmableLogicBase = protocolScriptBuilderService
                                        .getParameterizedProgrammableLogicBaseScript(protocolParams);
                        log.info("programmableLogicBase policy: {}", programmableLogicBase.getPolicyId());

                        // Issuer to be used for minting/burning/sieze
                        // NOTE: Parameterized with adminPkh, asset_name, issuance_prefix,
                        // issuance_postfix, and programmable_base_hash
                        var issuerContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "example_transfer_logic.issuer_admin_contract.withdraw");
                        if (issuerContractOpt.isEmpty()) {
                                return TransactionContext.typedError("could not find issuer contract validator");
                        }
                        var issuerContract = issuerContractOpt.get();

                        // Extract issuance prefix/postfix from issuance UTxO
                        // For seize, we need to get issuance UTxO from protocol params
                        var issuanceTxHash = protocolParams.issuanceParams().txInput().txHash();
                        var issuanceOutputIndex = protocolParams.issuanceParams().txInput().outputIndex();
                        var issuanceUtxoOpt = utxoProvider.findUtxo(issuanceTxHash, issuanceOutputIndex);
                        if (issuanceUtxoOpt.isEmpty()) {
                                return TransactionContext
                                                .typedError("could not find issuance UTxO to extract prefix/postfix");
                        }
                        var prefixPostfixOpt = extractIssuancePrefixPostfix(issuanceUtxoOpt.get());
                        if (prefixPostfixOpt.isEmpty()) {
                                return TransactionContext.typedError(
                                                "could not extract issuance prefix/postfix from UTxO datum");
                        }
                        var prefixPostfix = prefixPostfixOpt.get();
                        var issuancePrefix = prefixPostfix.first();
                        var issuancePostfix = prefixPostfix.second();

                        var adminPkh = Credential.fromKey(context.getIssuerAdminPkh());
                        // Build parameter list: [permitted_cred, asset_name, issuance_prefix,
                        // _issuance_postfix, programmable_base_hash]
                        // IMPORTANT: For seize operations, asset name validation is skipped (no
                        // minting)
                        var assetNameBytes = HexUtil.decodeHexString(progToken.assetName());
                        var programmableBaseHash = HexUtil.decodeHexString(
                                        protocolParams.programmableLogicBaseParams().scriptHash());
                        var issuerAdminContractInitParams = ListPlutusData.of(
                                        serialize(adminPkh),
                                        BytesPlutusData.of(assetNameBytes),
                                        BytesPlutusData.of(issuancePrefix),
                                        BytesPlutusData.of(issuancePostfix),
                                        BytesPlutusData.of(programmableBaseHash));

                        var substandardIssueAdminContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                                        AikenScriptUtil.applyParamToScript(issuerAdminContractInitParams,
                                                        issuerContract.scriptBytes()),
                                        PlutusVersion.v3);
                        log.info("substandardIssueAdminContract: {}", substandardIssueAdminContract.getPolicyId());

                        var substandardIssueAdminAddress = AddressProvider
                                        .getRewardAddress(substandardIssueAdminContract, network.getCardanoNetwork());

                        var substandardTransferContractOpt = substandardService.getSubstandardValidator(SUBSTANDARD_ID,
                                        "example_transfer_logic.transfer.withdraw");
                        if (substandardTransferContractOpt.isEmpty()) {
                                log.warn("could not resolve transfer contract");
                                return TransactionContext.typedError("could not resolve transfer contract");
                        }
=======
            var tx = new ScriptTx()
                    .collectFrom(adminUtxos)
                    .collectFrom(utxoToSeize, ConstrPlutusData.of(0))
                    .withdraw(substandardIssueAdminAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                    .withdraw(programmableLogicGlobalAddress.getAddress(), BigInteger.ZERO, programmableGlobalRedeemer)
                    .payToContract(recipientProgrammableTokenAddress.getAddress(), ValueUtil.toAmountList(tokenAssetToSeize), ConstrPlutusData.of(0))
                    .payToContract(utxoToSeize.getAddress(), ValueUtil.toAmountList(utxoToSeize.toValue().subtract(tokenAssetToSeize)), ConstrPlutusData.of(0))
                    .readFrom(sortedReferenceInputs.toArray(new TransactionInput[0]))
                    .attachRewardValidator(programmableLogicGlobal) // global
                    .attachRewardValidator(substandardIssueAdminContract)
                    .attachSpendingValidator(programmableLogicBase) // base
                    .withChangeAddress(feePayerAddress.getAddress());


            var transaction = quickTxBuilder.compose(tx)
                    .feePayer(feePayerAddress.getAddress())
                    .mergeOutputs(false)
                    .preBalanceTx((txBuilderContext, transaction1) -> {
                        try {
                            log.info("pre balance tx: {}", objectMapper.writeValueAsString(transaction1));
                        } catch (JsonProcessingException e) {
                            throw new RuntimeException(e);
                        }
                    })
//                    .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                    .withRequiredSigners(adminPkh.getBytes())
                    .build();


            log.info("tx: {}", transaction.serializeToHex());
            log.info("tx: {}", objectMapper.writeValueAsString(transaction));

            return TransactionContext.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.warn("error", e);
            return TransactionContext.typedError("error: " + e.getMessage());
        }
>>>>>>> upstream/main

                        var valueToSeize = utxoToSeize.toValue().amountOf(progToken.policyId(),
                                        "0x" + progToken.assetName());
                        log.info("amount to seize: {}", valueToSeize);

                        var tokenAssetToSeize = Value.from(progToken.policyId(), "0x" + progToken.assetName(),
                                        valueToSeize);

                        var sortedInputs = Stream.concat(feePayerUtxos.stream(), Stream.of(utxoToSeize))
                                        .sorted(new UtxoComparator())
                                        .toList();

                        var seizeInputIndex = sortedInputs.indexOf(utxoToSeize);
                        log.info("seizeInputIndex: {}", seizeInputIndex);

                        var registryRefInput = TransactionInput.builder()
                                        .transactionId(progTokenRegistry.getTxHash())
                                        .index(progTokenRegistry.getOutputIndex())
                                        .build();
                        var refInputsList = new java.util.ArrayList<TransactionInput>();
                        refInputsList.add(protocolParamsUtxo);
                        refInputsList.add(registryRefInput);
                        var sortedReferenceInputs = refInputsList.stream()
                                        .sorted(new TransactionInputComparator())
                                        .toList();

                        var registryRefInputInex = sortedReferenceInputs.indexOf(registryRefInput);
                        log.info("registryRefInputInex: {}", registryRefInputInex);

                        var programmableGlobalRedeemer = ConstrPlutusData.of(1,
                                        BigIntPlutusData.of(registryRefInputInex),
                                        ListPlutusData.of(BigIntPlutusData.of(seizeInputIndex)),
                                        BigIntPlutusData.of(2), // Index of the first output
                                        BigIntPlutusData.of(1));

                        var tx = new ScriptTx()
                                        .collectFrom(feePayerUtxos)
                                        .collectFrom(utxoToSeize, ConstrPlutusData.of(0))
                                        .withdraw(substandardIssueAdminAddress.getAddress(), BigInteger.ZERO,
                                                        ConstrPlutusData.of(0))
                                        .withdraw(programmableLogicGlobalAddress.getAddress(), BigInteger.ZERO,
                                                        programmableGlobalRedeemer)
                                        .payToContract(recipientProgrammableTokenAddress.getAddress(),
                                                        ValueUtil.toAmountList(tokenAssetToSeize),
                                                        ConstrPlutusData.of(0))
                                        .payToContract(utxoToSeize.getAddress(),
                                                        ValueUtil.toAmountList(utxoToSeize.toValue()
                                                                        .subtract(tokenAssetToSeize)),
                                                        ConstrPlutusData.of(0))
                                        .readFrom(sortedReferenceInputs.toArray(new TransactionInput[0]))
                                        .attachRewardValidator(programmableLogicGlobal) // global
                                        .attachRewardValidator(substandardIssueAdminContract)
                                        .attachSpendingValidator(programmableLogicBase) // base
                                        .withChangeAddress(feePayerAddress.getAddress());

                        var transaction = quickTxBuilder.compose(tx)
                                        .withCollateralInputs(collateralInput)
                                        .feePayer(feePayerAddress.getAddress())
                                        .mergeOutputs(false)
                                        // .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                                        .withRequiredSigners(adminPkh.getBytes())
                                        .build();

                        log.info("tx: {}", transaction.serializeToHex());
                        log.info("tx: {}", objectMapper.writeValueAsString(transaction));

                        return TransactionContext.ok(transaction.serializeToHex());

                } catch (Exception e) {
                        log.warn("error", e);
                        return TransactionContext.typedError("error: " + e.getMessage());
                }

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