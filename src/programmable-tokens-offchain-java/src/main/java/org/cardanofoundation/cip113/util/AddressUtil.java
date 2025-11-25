package org.cardanofoundation.cip113.util;

import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.util.HexUtil;
import lombok.extern.slf4j.Slf4j;

import java.util.Optional;

@Slf4j
public class AddressUtil {

    public static class AddressComponents {
        private final String fullAddress;
        private final String paymentScriptHash;
        private final String stakeKeyHash;

        public AddressComponents(String fullAddress, String paymentScriptHash, String stakeKeyHash) {
            this.fullAddress = fullAddress;
            this.paymentScriptHash = paymentScriptHash;
            this.stakeKeyHash = stakeKeyHash;
        }

        public String getFullAddress() {
            return fullAddress;
        }

        public String getPaymentScriptHash() {
            return paymentScriptHash;
        }

        public String getStakeKeyHash() {
            return stakeKeyHash;
        }

        @Override
        public String toString() {
            return "AddressComponents{" +
                    "fullAddress='" + fullAddress + '\'' +
                    ", paymentScriptHash='" + paymentScriptHash + '\'' +
                    ", stakeKeyHash='" + stakeKeyHash + '\'' +
                    '}';
        }
    }

    /**
     * Decompose a Cardano address into its components
     *
     * @param bech32Address the bech32 encoded address
     * @return AddressComponents containing payment and stake credentials, or null if parsing fails
     */
    public static AddressComponents decompose(String bech32Address) {
        try {
            Address address = new Address(bech32Address);

            String paymentScriptHash = null;
            String stakeKeyHash = null;

            // Extract payment credential
            Optional<Credential> paymentCredOpt = address.getPaymentCredential();
            if (paymentCredOpt.isPresent()) {
                Credential paymentCred = paymentCredOpt.get();
                byte[] credBytes = paymentCred.getBytes();
                if (credBytes != null) {
                    paymentScriptHash = HexUtil.encodeHexString(credBytes);
                }
            }

            // Extract stake credential (optional)
            Optional<Credential> stakeCredOpt = address.getDelegationCredential();
            if (stakeCredOpt.isPresent()) {
                Credential stakeCred = stakeCredOpt.get();
                byte[] credBytes = stakeCred.getBytes();
                if (credBytes != null) {
                    stakeKeyHash = HexUtil.encodeHexString(credBytes);
                }
            }

            return new AddressComponents(bech32Address, paymentScriptHash, stakeKeyHash);

        } catch (Exception e) {
            log.error("Failed to decompose address: {}", bech32Address, e);
            return null;
        }
    }

    /**
     * Check if an address uses a specific payment script hash
     *
     * @param bech32Address the address to check
     * @param scriptHash the script hash to match
     * @return true if the address uses this script hash, false otherwise
     */
    public static boolean hasPaymentScriptHash(String bech32Address, String scriptHash) {
        AddressComponents components = decompose(bech32Address);
        if (components == null || components.getPaymentScriptHash() == null) {
            return false;
        }
        return components.getPaymentScriptHash().equalsIgnoreCase(scriptHash);
    }
}
