package org.cardanofoundation.cip113.controller;

import com.bloxbean.cardano.client.transaction.spec.Value;
import com.easy1staking.cardano.model.AssetType;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.BalanceLogEntity;
import org.cardanofoundation.cip113.service.BalanceService;
import org.cardanofoundation.cip113.service.RegistryService;
import org.cardanofoundation.cip113.util.BalanceValueHelper;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigInteger;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("${apiPrefix}/balances")
@RequiredArgsConstructor
@Slf4j
public class BalanceController {

    private final BalanceService balanceService;
    private final RegistryService registryService;

    /**
     * Get current balance for all assets at an address
     * Returns the balance as a unit map: {"lovelace": "1000000", "policyId+assetName": "amount"}
     *
     * @param address the bech32 address
     * @return map of unit to amount
     */
    @GetMapping("/current/{address}")
    public ResponseEntity<Map<String, String>> getCurrentBalance(@PathVariable String address) {
        log.debug("GET /current/{} - fetching current balance", address);
        Map<String, String> balance = balanceService.getCurrentBalanceByUnit(address);
        return ResponseEntity.ok(balance);
    }

    /**
     * Get current balance for a specific asset
     *
     * @param address the bech32 address
     * @param unit the asset unit ("lovelace" for ADA, or "policyId+assetName" for native assets)
     * @return map with the asset amount
     */
    @GetMapping("/current/{address}/{unit}")
    public ResponseEntity<Map<String, String>> getCurrentBalanceForAsset(
            @PathVariable String address,
            @PathVariable String unit) {
        log.debug("GET /current/{}/{} - fetching balance for asset", address, unit);

        return balanceService.getLatestBalance(address)
                .map(entity -> {
                    BigInteger amount = balanceService.getAssetAmount(entity.getBalance(), unit);
                    Map<String, String> response = new HashMap<>();
                    response.put("address", address);
                    response.put("unit", unit);
                    response.put("amount", amount.toString());
                    response.put("txHash", entity.getTxHash());
                    response.put("slot", entity.getSlot().toString());
                    return ResponseEntity.ok(response);
                })
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get current balances by payment script hash
     *
     * @param scriptHash the payment script hash
     * @return list of latest balances
     */
    @GetMapping("/current-by-payment/{scriptHash}")
    public ResponseEntity<List<BalanceLogEntity>> getCurrentBalanceByPaymentScript(
            @PathVariable String scriptHash) {
        log.debug("GET /current-by-payment/{} - fetching balances", scriptHash);
        List<BalanceLogEntity> balances = balanceService.getLatestBalancesByPaymentScript(scriptHash);
        return ResponseEntity.ok(balances);
    }

    /**
     * Get current balances by stake key hash
     *
     * @param stakeHash the stake key hash
     * @return list of latest balances
     */
    @GetMapping("/current-by-stake/{stakeHash}")
    public ResponseEntity<List<BalanceLogEntity>> getCurrentBalanceByStakeKey(
            @PathVariable String stakeHash) {
        log.debug("GET /current-by-stake/{} - fetching balances", stakeHash);
        List<BalanceLogEntity> balances = balanceService.getLatestBalancesByStakeKey(stakeHash);
        return ResponseEntity.ok(balances);
    }

    /**
     * Get current balance by payment script hash and stake key hash
     * Payment script + stake key uniquely identifies an address, so returns at most one entry
     *
     * @param scriptHash the payment script hash
     * @param stakeHash the stake key hash
     * @return the latest balance or 404 if not found
     */
    @GetMapping("/current-by-payment-and-stake/{scriptHash}/{stakeHash}")
    public ResponseEntity<BalanceLogEntity> getCurrentBalanceByPaymentScriptAndStakeKey(
            @PathVariable String scriptHash,
            @PathVariable String stakeHash) {
        log.debug("GET /current-by-payment-and-stake/{}/{} - fetching balance", scriptHash, stakeHash);
        List<BalanceLogEntity> balances = balanceService.getLatestBalancesByPaymentScriptAndStakeKey(
                scriptHash, stakeHash);

        // Payment script + stake key uniquely identifies one address, so at most one result
        return balances.stream()
                .findFirst()
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get balance history for all assets at an address
     *
     * @param address the bech32 address
     * @param limit maximum number of entries (default 100)
     * @return list of balance entries
     */
    @GetMapping("/history/{address}")
    public ResponseEntity<List<BalanceLogEntity>> getBalanceHistory(
            @PathVariable String address,
            @RequestParam(defaultValue = "100") int limit) {
        log.debug("GET /history/{} - fetching balance history, limit={}", address, limit);
        List<BalanceLogEntity> history = balanceService.getBalanceHistory(address, limit);
        return ResponseEntity.ok(history);
    }

    /**
     * Get transaction list with balance diffs
     *
     * @param address the bech32 address
     * @param limit maximum number of entries (default 100)
     * @return list of transactions with balance differences
     */
    @GetMapping("/transactions/{address}")
    public ResponseEntity<List<Map<String, Object>>> getTransactionsWithDiffs(
            @PathVariable String address,
            @RequestParam(defaultValue = "100") int limit) {
        log.debug("GET /transactions/{} - fetching transactions with diffs, limit={}", address, limit);

        List<BalanceLogEntity> history = balanceService.getBalanceHistory(address, limit);

        // Calculate diffs between consecutive entries
        List<Map<String, Object>> transactions = history.stream()
                .map(entry -> {
                    Map<String, Object> txData = new HashMap<>();
                    txData.put("txHash", entry.getTxHash());
                    txData.put("slot", entry.getSlot());
                    txData.put("blockHeight", entry.getBlockHeight());
                    txData.put("balance", BalanceValueHelper.fromJson(entry.getBalance()));

                    // Get previous balance to calculate diff
                    balanceService.getPreviousBalance(entry).ifPresentOrElse(
                            prevEntry -> {
                                Value diff = balanceService.calculateBalanceDiff(entry, prevEntry);
                                txData.put("diff", BalanceValueHelper.toUnitMap(diff));
                                txData.put("previousBalance", BalanceValueHelper.fromJson(prevEntry.getBalance()));
                            },
                            () -> {
                                // First transaction, diff is the balance itself
                                Value balance = BalanceValueHelper.fromJson(entry.getBalance());
                                txData.put("diff", BalanceValueHelper.toUnitMap(balance));
                                txData.put("previousBalance", BalanceValueHelper.empty());
                            }
                    );

                    return txData;
                })
                .collect(Collectors.toList());

        return ResponseEntity.ok(transactions);
    }

    /**
     * Get balance changes for a specific transaction
     *
     * @param txHash the transaction hash
     * @return list of balance entries for this transaction
     */
    @GetMapping("/by-transaction/{txHash}")
    public ResponseEntity<List<BalanceLogEntity>> getBalancesByTransaction(@PathVariable String txHash) {
        log.debug("GET /by-transaction/{} - fetching balance changes", txHash);
        List<BalanceLogEntity> balances = balanceService.getBalancesByTransaction(txHash);
        return ResponseEntity.ok(balances);
    }

    /**
     * Get only programmable token balances for an address
     * Filters the balance to include only assets that are registered in the programmable token registry
     *
     * @param address the bech32 address
     * @return map of programmable token units to amounts
     */
    @GetMapping("/programmable-only/{address}")
    public ResponseEntity<Map<String, String>> getProgrammableTokenBalances(@PathVariable String address) {
        log.debug("GET /programmable-only/{} - fetching programmable token balances", address);

        Map<String, String> allBalances = balanceService.getCurrentBalanceByUnit(address);

        // Filter to only programmable tokens by checking registry
        Map<String, String> programmableBalances = allBalances.entrySet().stream()
                .filter(entry -> {
                    String unit = entry.getKey();

                    // Skip lovelace (ADA)
                    if ("lovelace".equals(unit)) {
                        return false;
                    }

                    // Parse unit to get policy ID
                    AssetType assetType = AssetType.fromUnit(unit);
                    String policyId = assetType.policyId();

                    // Check if token is registered in registry
                    return registryService.isTokenRegistered(policyId);
                })
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));

        return ResponseEntity.ok(programmableBalances);
    }
}
