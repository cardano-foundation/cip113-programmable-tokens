package org.cardanofoundation.cip113.model;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Validation tests for MintTokenRequest DTO.
 * Tests Bean Validation annotations for API request validation.
 */
@DisplayName("MintTokenRequest Validation Tests")
class MintTokenRequestValidationTest {

    private static Validator validator;

    @BeforeAll
    static void setUp() {
        ValidatorFactory factory = Validation.buildDefaultValidatorFactory();
        validator = factory.getValidator();
    }

    @Test
    @DisplayName("should pass validation with valid request")
    void shouldPassValidationWithValidRequest() {
        MintTokenRequest request = new MintTokenRequest(
                "addr_test1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwq2ytjqp",
                "blacklist",
                "blacklist_mint",
                "48656c6c6f", // "Hello" in hex
                "1000000",
                "addr_test1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwq2ytjqp"
        );

        Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);
        assertTrue(violations.isEmpty(), "Expected no validation errors");
    }

    @Nested
    @DisplayName("Issuer Base Address Validation")
    class IssuerBaseAddressValidation {

        @ParameterizedTest
        @NullAndEmptySource
        @ValueSource(strings = {"   ", "\t", "\n"})
        @DisplayName("should reject blank issuer address")
        void shouldRejectBlankIssuerAddress(String issuerAddress) {
            MintTokenRequest request = withIssuerBaseAddress(issuerAddress);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertFalse(violations.isEmpty(), "Expected validation error for blank address");
            assertTrue(violations.stream().anyMatch(v ->
                    v.getPropertyPath().toString().equals("issuerBaseAddress")));
        }

        @ParameterizedTest
        @ValueSource(strings = {
                "invalid_address",
                "addr2qz2fxv2umyhttkxyxp8x", // wrong prefix (addr2 instead of addr1)
                "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4" // bitcoin address
        })
        @DisplayName("should reject invalid issuer address format")
        void shouldRejectInvalidAddressFormat(String invalidAddress) {
            MintTokenRequest request = withIssuerBaseAddress(invalidAddress);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertFalse(violations.isEmpty(), "Expected validation error for invalid address");
            assertTrue(violations.stream().anyMatch(v ->
                    v.getMessage().contains("Invalid issuer address format")));
        }

        @ParameterizedTest
        @ValueSource(strings = {
                "addr_test1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwq2ytjqp",
                "addr1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwqxcl9g7"
        })
        @DisplayName("should accept valid Cardano addresses")
        void shouldAcceptValidAddresses(String validAddress) {
            MintTokenRequest request = withIssuerBaseAddress(validAddress);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertTrue(violations.stream().noneMatch(v ->
                    v.getPropertyPath().toString().equals("issuerBaseAddress")),
                    "Expected no validation errors for valid address");
        }
    }    @Nested
    @DisplayName("Asset Name Validation")
    class AssetNameValidation {

        @ParameterizedTest
        @NullAndEmptySource
        @DisplayName("should reject blank asset name")
        void shouldRejectBlankAssetName(String assetName) {
            MintTokenRequest request = withAssetName(assetName);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertFalse(violations.isEmpty(), "Expected validation error for blank asset name");
        }

        @ParameterizedTest
        @ValueSource(strings = {
                "ghijk", // invalid hex chars
                "12345678901234567890123456789012345678901234567890123456789012345", // 65 chars (too long)
                "hello world", // spaces not allowed
                "GHIJK" // uppercase non-hex
        })
        @DisplayName("should reject invalid hex asset names")
        void shouldRejectInvalidHexAssetName(String invalidAssetName) {
            MintTokenRequest request = withAssetName(invalidAssetName);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertFalse(violations.isEmpty(), "Expected validation error for invalid hex");
        }

        @ParameterizedTest
        @ValueSource(strings = {
                "48656c6c6f", // "Hello"
                "ABCDEF1234567890", // uppercase hex is valid
                "a", // minimum 1 char
                "1234567890123456789012345678901234567890123456789012345678901234" // max 64 chars
        })
        @DisplayName("should accept valid hex asset names")
        void shouldAcceptValidHexAssetNames(String validAssetName) {
            MintTokenRequest request = withAssetName(validAssetName);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertTrue(violations.stream().noneMatch(v ->
                    v.getPropertyPath().toString().equals("assetName")),
                    "Expected no validation errors for valid asset name");
        }
    }    @Nested
    @DisplayName("Quantity Validation")
    class QuantityValidation {

        @ParameterizedTest
        @NullAndEmptySource
        @DisplayName("should reject blank quantity")
        void shouldRejectBlankQuantity(String quantity) {
            MintTokenRequest request = withQuantity(quantity);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertFalse(violations.isEmpty(), "Expected validation error for blank quantity");
        }

        @ParameterizedTest
        @ValueSource(strings = {"0", "-1", "-100", "00", "01"})
        @DisplayName("should reject non-positive quantities")
        void shouldRejectNonPositiveQuantities(String invalidQuantity) {
            MintTokenRequest request = withQuantity(invalidQuantity);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertFalse(violations.isEmpty(), "Expected validation error for non-positive quantity");
        }

        @ParameterizedTest
        @ValueSource(strings = {"1", "100", "1000000", "999999999999"})
        @DisplayName("should accept valid positive quantities")
        void shouldAcceptPositiveQuantities(String validQuantity) {
            MintTokenRequest request = withQuantity(validQuantity);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertTrue(violations.stream().noneMatch(v ->
                    v.getPropertyPath().toString().equals("quantity")),
                    "Expected no validation errors for valid quantity");
        }
    }    @Nested
    @DisplayName("Substandard Name Validation")
    class SubstandardNameValidation {

        @ParameterizedTest
        @NullAndEmptySource
        @ValueSource(strings = {"   ", "\t"})
        @DisplayName("should reject blank substandard name")
        void shouldRejectBlankSubstandardName(String substandardName) {
            MintTokenRequest request = withSubstandardName(substandardName);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertFalse(violations.isEmpty(), "Expected validation error for blank substandard name");
        }
    }

    @Nested
    @DisplayName("Recipient Address Validation")
    class RecipientAddressValidation {

        @Test
        @DisplayName("should accept null recipient address (optional)")
        void shouldAcceptNullRecipientAddress() {
            MintTokenRequest request = withRecipientAddress(null);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertTrue(violations.stream().noneMatch(v ->
                    v.getPropertyPath().toString().equals("recipientAddress")),
                    "Expected no validation errors for null recipient address");
        }

        @ParameterizedTest
        @ValueSource(strings = {
                "invalid_address",
                "addr2qz2fxv2umyhttkxyxp8x", // wrong prefix
                "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4" // bitcoin address
        })
        @DisplayName("should reject invalid recipient address format when provided")
        void shouldRejectInvalidRecipientAddressFormat(String invalidAddress) {
            MintTokenRequest request = withRecipientAddress(invalidAddress);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertFalse(violations.isEmpty(), "Expected validation error for invalid recipient address");
            assertTrue(violations.stream().anyMatch(v ->
                    v.getMessage().contains("Invalid recipient address format")));
        }

        @ParameterizedTest
        @ValueSource(strings = {
                "addr_test1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwq2ytjqp",
                "addr1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwqxcl9g7"
        })
        @DisplayName("should accept valid recipient addresses when provided")
        void shouldAcceptValidRecipientAddresses(String validAddress) {
            MintTokenRequest request = withRecipientAddress(validAddress);
            Set<ConstraintViolation<MintTokenRequest>> violations = validator.validate(request);

            assertTrue(violations.stream().noneMatch(v ->
                    v.getPropertyPath().toString().equals("recipientAddress")),
                    "Expected no validation errors for valid recipient address");
        }
    }    // Helper to create a valid request for modification in tests
    private MintTokenRequest createValidRequest() {
        return new MintTokenRequest(
                "addr_test1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwq2ytjqp",
                "blacklist",
                "blacklist_mint",
                "48656c6c6f",
                "1000000",
                "addr_test1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwq2ytjqp"
        );
    }

    private MintTokenRequest withIssuerBaseAddress(String value) {
        var base = createValidRequest();
        return new MintTokenRequest(value, base.substandardName(), base.substandardIssueContractName(),
                base.assetName(), base.quantity(), base.recipientAddress());
    }

    private MintTokenRequest withSubstandardName(String value) {
        var base = createValidRequest();
        return new MintTokenRequest(base.issuerBaseAddress(), value, base.substandardIssueContractName(),
                base.assetName(), base.quantity(), base.recipientAddress());
    }

    private MintTokenRequest withAssetName(String value) {
        var base = createValidRequest();
        return new MintTokenRequest(base.issuerBaseAddress(), base.substandardName(), base.substandardIssueContractName(),
                value, base.quantity(), base.recipientAddress());
    }

    private MintTokenRequest withQuantity(String value) {
        var base = createValidRequest();
        return new MintTokenRequest(base.issuerBaseAddress(), base.substandardName(), base.substandardIssueContractName(),
                base.assetName(), value, base.recipientAddress());
    }

    private MintTokenRequest withRecipientAddress(String value) {
        var base = createValidRequest();
        return new MintTokenRequest(base.issuerBaseAddress(), base.substandardName(), base.substandardIssueContractName(),
                base.assetName(), base.quantity(), value);
    }
}
