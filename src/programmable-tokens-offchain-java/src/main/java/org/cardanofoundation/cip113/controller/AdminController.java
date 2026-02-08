package org.cardanofoundation.cip113.controller;

import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Utxo;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.easy1staking.cardano.model.AssetType;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.entity.BlacklistInitEntity;
import org.cardanofoundation.cip113.entity.FreezeAndSeizeTokenRegistrationEntity;
import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.repository.BlacklistInitRepository;
import org.cardanofoundation.cip113.repository.FreezeAndSeizeTokenRegistrationRepository;
import org.cardanofoundation.cip113.repository.ProgrammableTokenRegistryRepository;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.cardanofoundation.cip113.service.UtxoProvider;
import org.cardanofoundation.cip113.util.BalanceValueHelper;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.*;
import java.util.stream.Collectors;

import static java.math.BigInteger.ZERO;

/**
 * Admin controller for querying tokens where a user has admin roles.
 * Used by the admin panel UI to determine which tokens a connected wallet can manage.
 */
@RestController
@RequestMapping("${apiPrefix}/admin")
@RequiredArgsConstructor
@Slf4j
public class AdminController {

    private final FreezeAndSeizeTokenRegistrationRepository freezeAndSeizeRepo;
    private final BlacklistInitRepository blacklistInitRepo;
    private final ProtocolBootstrapService protocolBootstrapService;
    private final ProgrammableTokenRegistryRepository programmableTokenRepo;
    private final UtxoProvider utxoProvider;
    private final AppConfig.Network network;

    /**
     * Get all tokens where the given PKH has admin roles.
     * Returns tokens where the PKH is:
     * - ISSUER_ADMIN (from freeze-and-seize token registration)
     * - BLACKLIST_MANAGER (from blacklist init)
     * - Or all dummy tokens (anyone can mint dummy tokens)
     *
     * @param pkh Payment key hash of the admin
     * @return List of tokens with roles
     */
    @GetMapping("/tokens/{pkh}")
    public ResponseEntity<AdminTokensResponse> getAdminTokens(@PathVariable String pkh) {
        log.info("GET /admin/tokens/{} - fetching admin tokens", pkh);

        Map<String, AdminTokenInfo> tokenMap = new LinkedHashMap<>();

        // 1. Query freeze-and-seize tokens where user is issuer admin
        List<FreezeAndSeizeTokenRegistrationEntity> issuerAdminTokens =
                freezeAndSeizeRepo.findByIssuerAdminPkh(pkh);

        for (FreezeAndSeizeTokenRegistrationEntity token : issuerAdminTokens) {
            String policyId = token.getProgrammableTokenPolicyId();
            log.info("policyId: {}", policyId);
            BlacklistInitEntity blacklistInit = token.getBlacklistInit();

            List<String> roles = new ArrayList<>();
            roles.add("ISSUER_ADMIN");

            // Check if also blacklist manager
            if (blacklistInit != null && pkh.equals(blacklistInit.getAdminPkh())) {
                roles.add("BLACKLIST_MANAGER");
            }

            // Look up the registry entry for asset name
            Optional<ProgrammableTokenRegistryEntity> registryEntry =
                    programmableTokenRepo.findByPolicyId(policyId);
            if (registryEntry.isPresent()) {
                var foo = registryEntry.get();
                log.info("registryEntry: {}, {}, {}", foo.getSubstandardId(), foo.getPolicyId(), foo.getAssetName());
            }

            String assetName = registryEntry.map(ProgrammableTokenRegistryEntity::getAssetName).orElse("");
            String assetNameDisplay = hexToString(assetName);
            String substandardId = registryEntry.map(ProgrammableTokenRegistryEntity::getSubstandardId).orElse("freeze-and-seize");

            AdminTokenDetails details = new AdminTokenDetails(
                    blacklistInit != null ? blacklistInit.getBlacklistNodePolicyId() : null,
                    token.getIssuerAdminPkh(),
                    blacklistInit != null ? blacklistInit.getAdminPkh() : null
            );

            tokenMap.put(policyId, new AdminTokenInfo(
                    policyId,
                    assetName,
                    assetNameDisplay,
                    substandardId,
                    roles,
                    details
            ));
        }

        // 2. Query blacklist inits where user is ONLY blacklist manager (not issuer admin)
        List<BlacklistInitEntity> blacklistManagerEntries = blacklistInitRepo.findByAdminPkh(pkh);

        for (BlacklistInitEntity blacklistInit : blacklistManagerEntries) {
            String blacklistPolicyId = blacklistInit.getBlacklistNodePolicyId();

            // Find tokens linked to this blacklist that aren't already added
            List<FreezeAndSeizeTokenRegistrationEntity> linkedTokens =
                    freezeAndSeizeRepo.findByBlacklistInit_BlacklistNodePolicyId(blacklistPolicyId);

            for (FreezeAndSeizeTokenRegistrationEntity token : linkedTokens) {
                String policyId = token.getProgrammableTokenPolicyId();

                if (tokenMap.containsKey(policyId)) {
                    // Already added as issuer admin, just ensure BLACKLIST_MANAGER is in roles
                    AdminTokenInfo existing = tokenMap.get(policyId);
                    if (!existing.roles().contains("BLACKLIST_MANAGER")) {
                        List<String> updatedRoles = new ArrayList<>(existing.roles());
                        updatedRoles.add("BLACKLIST_MANAGER");
                        tokenMap.put(policyId, new AdminTokenInfo(
                                existing.policyId(),
                                existing.assetName(),
                                existing.assetNameDisplay(),
                                existing.substandardId(),
                                updatedRoles,
                                existing.details()
                        ));
                    }
                } else {
                    // Only blacklist manager, not issuer admin
                    Optional<ProgrammableTokenRegistryEntity> registryEntry =
                            programmableTokenRepo.findByPolicyId(policyId);

                    String assetName = registryEntry.map(ProgrammableTokenRegistryEntity::getAssetName).orElse("");
                    String assetNameDisplay = hexToString(assetName);
                    String substandardId = registryEntry.map(ProgrammableTokenRegistryEntity::getSubstandardId).orElse("freeze-and-seize");

                    AdminTokenDetails details = new AdminTokenDetails(
                            blacklistPolicyId,
                            token.getIssuerAdminPkh(),
                            blacklistInit.getAdminPkh()
                    );

                    tokenMap.put(policyId, new AdminTokenInfo(
                            policyId,
                            assetName,
                            assetNameDisplay,
                            substandardId,
                            List.of("BLACKLIST_MANAGER"),
                            details
                    ));
                }
            }
        }

        // 3. For dummy tokens - include ALL registered dummy tokens (anyone can mint)
        List<ProgrammableTokenRegistryEntity> dummyTokens =
                programmableTokenRepo.findBySubstandardId("dummy");

        for (ProgrammableTokenRegistryEntity dummyToken : dummyTokens) {
            String policyId = dummyToken.getPolicyId();

            // Don't override if already added with actual roles
            if (!tokenMap.containsKey(policyId)) {
                String assetName = dummyToken.getAssetName() != null ? dummyToken.getAssetName() : "";
                String assetNameDisplay = hexToString(assetName);

                tokenMap.put(policyId, new AdminTokenInfo(
                        policyId,
                        assetName,
                        assetNameDisplay,
                        "dummy",
                        List.of(),  // Empty roles - anyone can mint dummy tokens
                        new AdminTokenDetails(null, null, null)
                ));
            }
        }

        log.info("Found {} tokens for PKH {}", tokenMap.size(), pkh);

        return ResponseEntity.ok(new AdminTokensResponse(pkh, new ArrayList<>(tokenMap.values())));
    }

    /**
     * Get all UTxOs that contain a specific programmable token for a user's wallet.
     * Used by the burn admin UI to let admins select which UTxOs to burn from.
     * <p>
     * IMPORTANT: Users provide their vanilla wallet address (addr_test1...),
     * but programmable tokens live at smart contract addresses where:
     * - Payment credential = script hash (prog_logic validator)
     * - Stake credential = user's payment PKH
     * <p>
     * So we query by payment PKH, not the provided address directly.
     *
     * @param address   User's wallet address (vanilla address)
     * @param policyId  Policy ID of the token
     * @param assetName Hex-encoded asset name
     * @return List of UTxOs containing the specified token
     */
    @GetMapping("/utxos")
    public ResponseEntity<?> getUtxosForBurning(
            @RequestParam String address,
            @RequestParam String policyId,
            @RequestParam String assetName,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("GET /admin/utxos - address: {}, policyId: {}, assetName: {}, protocolTxHash: {}",
                address, policyId, assetName, protocolTxHash);

        var assetToBurn = new AssetType(policyId, assetName);

        ProtocolBootstrapParams protocolBootstrapParams;
        if (protocolTxHash == null) {
            protocolBootstrapParams = protocolBootstrapService.getProtocolBootstrapParams();
        } else {
            protocolBootstrapParams = protocolBootstrapService.getProtocolBootstrapParamsByTxHash(protocolTxHash)
                    .orElseThrow();
        }

        log.info("protocolBootstrapParams: {}", protocolBootstrapParams);
        try {

            var userAddress = new Address(address);
            var recipientProgrammableTokenAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                    userAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            // Query UTxOs by stake PKH (programmable token UTxOs have user PKH in stake part)
            // For programmable tokens: payment = script hash, stake = user's payment PKH
            log.info("userAddress: {}", userAddress.getAddress());
            log.info("recipientProgrammableTokenAddress: {}", recipientProgrammableTokenAddress.getAddress());

            List<Utxo> allUtxos = utxoProvider.findUtxos(recipientProgrammableTokenAddress.getAddress());

            log.info("Found {} total UTxOs with stake credential matching payment PKH", allUtxos.size());

            // Filter to UTxOs containing the specific token
            List<UtxoInfo> filteredUtxos = allUtxos.stream()
                    .filter(utxo -> utxo.toValue().amountOf(assetToBurn.policyId(), "0x" + assetToBurn.assetName()).compareTo(ZERO) > 0)
                    .map(utxo -> {
                        Value value = utxo.toValue();
                        var amount = utxo.toValue().amountOf(assetToBurn.policyId(), "0x" + assetToBurn.assetName());

                        return new UtxoInfo(
                                utxo.getTxHash(),
                                utxo.getOutputIndex(),
                                amount.toString(),
                                BalanceValueHelper.toJson(value)  // Full value for reference
                        );
                    })
                    .collect(Collectors.toList());

            log.info("Found {} UTxOs containing token {} for address {}",
                    filteredUtxos.size(), assetToBurn.toUnit(), address);

            return ResponseEntity.ok(new UtxoListResponse(address, policyId, assetName, filteredUtxos));

        } catch (Exception e) {
            log.error("Failed to fetch UTxOs for address: {}", address, e);
            return ResponseEntity.internalServerError()
                    .body(Map.of("error", "Failed to fetch UTxOs: " + e.getMessage()));
        }
    }

    /**
     * Convert hex-encoded string to human-readable string.
     */
    private String hexToString(String hex) {
        if (hex == null || hex.isEmpty()) {
            return "";
        }
        try {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < hex.length(); i += 2) {
                String str = hex.substring(i, i + 2);
                sb.append((char) Integer.parseInt(str, 16));
            }
            return sb.toString();
        } catch (Exception e) {
            log.debug("Failed to decode hex string: {}", hex);
            return hex;
        }
    }

    // Response DTOs

    public record AdminTokensResponse(
            String adminPkh,
            List<AdminTokenInfo> tokens
    ) {
    }

    public record AdminTokenInfo(
            String policyId,
            String assetName,           // Hex encoded
            String assetNameDisplay,    // Human readable
            String substandardId,
            List<String> roles,         // ["ISSUER_ADMIN", "BLACKLIST_MANAGER"]
            AdminTokenDetails details
    ) {
    }

    public record AdminTokenDetails(
            String blacklistNodePolicyId,   // For freeze-and-seize
            String issuerAdminPkh,
            String blacklistAdminPkh
    ) {
    }

    public record UtxoInfo(
            String txHash,
            int outputIndex,
            String tokenAmount,       // Amount of the queried token
            String fullValue         // Full Value JSON for debugging
    ) {
    }

    public record UtxoListResponse(
            String address,
            String policyId,
            String assetName,
            List<UtxoInfo> utxos
    ) {
    }
}
