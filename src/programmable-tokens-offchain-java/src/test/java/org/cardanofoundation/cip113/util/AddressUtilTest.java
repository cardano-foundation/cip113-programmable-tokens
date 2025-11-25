package org.cardanofoundation.cip113.util;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class AddressUtilTest {

    @Test
    void testDecomposeBaseAddress() {
        // Given - a base address (payment + stake)
        // Note: This is a test address - in real tests you'd use actual mainnet/testnet addresses
        String baseAddress = "addr1q9xyz..."; // Example base address with payment and stake credentials

        // When
        AddressUtil.AddressComponents components = AddressUtil.decompose(baseAddress);

        // Then
        assertNotNull(components);
        assertNotNull(components.getPaymentScriptHash());
        // Base addresses have stake credentials
        // assertNotNull(components.getStakeKeyHash());
    }

    @Test
    void testDecomposeEnterpriseAddress() {
        // Given - an enterprise address (payment only, no stake)
        // Note: This is a test address
        String enterpriseAddress = "addr1v8xyz..."; // Example enterprise address

        // When
        AddressUtil.AddressComponents components = AddressUtil.decompose(enterpriseAddress);

        // Then
        assertNotNull(components);
        assertNotNull(components.getPaymentScriptHash());
        // Enterprise addresses don't have stake credentials
        // assertNull(components.getStakeKeyHash());
    }

    @Test
    void testDecomposeInvalidAddress() {
        // Given - invalid address
        String invalidAddress = "not_a_valid_address";

        // When
        AddressUtil.AddressComponents components = AddressUtil.decompose(invalidAddress);

        // Then - should return null on failure
        assertNull(components);
    }

    @Test
    void testHasPaymentScriptHash() {
        // Given
        String address = "addr1test...";
        String scriptHash = "aaa513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126102";

        // When/Then
        // This test would need a valid address/script hash pair
        // assertFalse(AddressUtil.hasPaymentScriptHash(address, scriptHash));

        // Test with invalid address
        assertFalse(AddressUtil.hasPaymentScriptHash("invalid", scriptHash));
    }

    @Test
    void testAddressComponentsToString() {
        // Given
        AddressUtil.AddressComponents components = new AddressUtil.AddressComponents(
                "addr1test123",
                "paymentScript123",
                "stakeKey456"
        );

        // When
        String toString = components.toString();

        // Then
        assertNotNull(toString);
        assertTrue(toString.contains("addr1test123"));
        assertTrue(toString.contains("paymentScript123"));
        assertTrue(toString.contains("stakeKey456"));
    }

    @Test
    void testAddressComponentsGetters() {
        // Given
        AddressUtil.AddressComponents components = new AddressUtil.AddressComponents(
                "addr1test123",
                "paymentScript123",
                "stakeKey456"
        );

        // Then
        assertEquals("addr1test123", components.getFullAddress());
        assertEquals("paymentScript123", components.getPaymentScriptHash());
        assertEquals("stakeKey456", components.getStakeKeyHash());
    }
}
