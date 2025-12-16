package org.cardanofoundation.cip113.util;

import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.easy1staking.cardano.model.AssetType;
import com.easy1staking.cardano.util.AmountUtil;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;

import java.math.BigInteger;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

@Slf4j
public class BalanceValueHelper {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
    private static final String LOVELACE_UNIT = "lovelace";

    /**
     * Convert a Value object to JSON string
     * Format: {"lovelace": "1000000", "policyId+assetName": "100"}
     *
     * @param value the Value object
     * @return JSON string representation
     */
    public static String toJson(Value value) {
        try {
            Map<String, String> balanceMap = toUnitMap(value);
            return OBJECT_MAPPER.writeValueAsString(balanceMap);
        } catch (JsonProcessingException e) {
            log.error("Failed to serialize Value to JSON", e);
            return "{}";
        }
    }

    /**
     * Convert a JSON string to Value object
     *
     * @param json the JSON string
     * @return Value object
     */
    public static Value fromJson(String json) {
        try {
            Map<String, String> balanceMap = OBJECT_MAPPER.readValue(json, new TypeReference<Map<String, String>>() {
            });
            return fromUnitMap(balanceMap);
        } catch (JsonProcessingException e) {
            log.error("Failed to deserialize JSON to Value", e);
            return Value.builder().coin(BigInteger.ZERO).build();
        }
    }

    /**
     * Convert a Value object to a unit map
     * Format: {"lovelace": "1000000", "policyId+assetName": "100"}
     *
     * @param value the Value object
     * @return map of unit to amount (as string)
     */
    public static Map<String, String> toUnitMap(Value value) {
        Map<String, String> map = new HashMap<>();

        ValueUtil.toAmountList(value).forEach(amount -> {
            var assetType = AssetType.fromUnit(amount.getUnit());
            if (assetType.isAda()){
                map.put(AssetType.LOVELACE, String.valueOf(amount.getQuantity()));
            } else {
                map.put(assetType.toUnit(), String.valueOf(amount.getQuantity()));
            }

        });

        return map;
    }

    /**
     * Convert a Value object to a unit map with BigInteger amounts
     * Format: {"lovelace": BigInteger("1000000"), "policyId+assetName": BigInteger("100")}
     *
     * @param value the Value object
     * @return map of unit to amount (as BigInteger)
     */
    public static Map<String, BigInteger> toMap(Value value) {
        Map<String, BigInteger> map = new HashMap<>();

        ValueUtil.toAmountList(value).forEach(amount -> {
            var assetType = AssetType.fromUnit(amount.getUnit());
            if (assetType.isAda()){
                map.put(AssetType.LOVELACE, amount.getQuantity());
            } else {
                map.put(assetType.toUnit(), amount.getQuantity());
            }
        });

        return map;
    }

    /**
     * Convert a unit map to Value object
     *
     * @param unitMap map of unit to amount (as string)
     * @return Value object
     */
    public static Value fromUnitMap2(Map<String, BigInteger> unitMap) {
        return unitMap.entrySet()
                .stream()
                .reduce(Value.builder().build(), (value, stringStringEntry) -> {
                    var assetType = AssetType.fromUnit(stringStringEntry.getKey());
                    var amount = stringStringEntry.getValue();
                    if (assetType.isAda()) {
                        return value.addCoin(amount);
                    } else {
                        return value.add(assetType.policyId(), "0x" + assetType.assetName(), amount);
                    }
                }, Value::add);
    }
    /**
     * Convert a unit map to Value object
     *
     * @param unitMap map of unit to amount (as string)
     * @return Value object
     */
    public static Value fromUnitMap(Map<String, String> unitMap) {
        return unitMap.entrySet()
                .stream()
                .reduce(Value.builder().build(), (value, stringStringEntry) -> {
                    var assetType = AssetType.fromUnit(stringStringEntry.getKey());
                    var amount = new BigInteger(stringStringEntry.getValue());
                    if (assetType.isAda()) {
                        return value.addCoin(amount);
                    } else {
                        return value.add(assetType.policyId(), "0x" + assetType.assetName(), amount);
                    }
                }, Value::add);
    }

    /**
     * Create an empty Value
     *
     * @return Value with zero coin and no assets
     */
    public static Value empty() {
        return Value.builder().coin(BigInteger.ZERO).build();
    }

    /**
     * Check if Value is empty (zero coin and no assets)
     *
     * @param value the Value to check
     * @return true if empty
     */
    public static boolean isEmpty(Value value) {
        if (value == null) {
            return true;
        }

        boolean hasCoin = value.getCoin() != null && value.getCoin().compareTo(BigInteger.ZERO) > 0;
        boolean hasAssets = value.getMultiAssets() != null && !value.getMultiAssets().isEmpty();

        return !hasCoin && !hasAssets;
    }

    /**
     * Calculate the signed difference between two balances
     * Returns a map with signed amounts (negative amounts prefixed with "-")
     *
     * @param currentBalance the current balance as JSON
     * @param previousBalance the previous balance as JSON (or null for first entry)
     * @return map of unit to signed amount difference
     */
    public static Map<String, String> calculateSignedDiff(String currentBalance, String previousBalance) {
        Map<String, String> current = toUnitMap(fromJson(currentBalance));

        Map<String, String> previous = previousBalance != null
            ? toUnitMap(fromJson(previousBalance))
            : new HashMap<>();

        Map<String, String> diff = new HashMap<>();

        // Get all units from both current and previous
        Set<String> allUnits = new HashSet<>();
        allUnits.addAll(current.keySet());
        allUnits.addAll(previous.keySet());

        for (String unit : allUnits) {
            BigInteger currentAmount = current.containsKey(unit)
                ? new BigInteger(current.get(unit))
                : BigInteger.ZERO;

            BigInteger previousAmount = previous.containsKey(unit)
                ? new BigInteger(previous.get(unit))
                : BigInteger.ZERO;

            BigInteger difference = currentAmount.subtract(previousAmount);

            // Only include non-zero differences
            if (difference.compareTo(BigInteger.ZERO) != 0) {
                diff.put(unit, difference.toString());
            }
        }

        return diff;
    }
}
