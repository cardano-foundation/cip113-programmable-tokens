package org.cardanofoundation.cip113.model;

import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

/**
 * Base class for token registration requests with polymorphic JSON deserialization.
 * The {@code substandardId} field acts as the discriminator for Jackson.
 *
 * <p>Each substandard defines its own request subtype with specific fields:</p>
 * <ul>
 *   <li>{@link DummyRegisterRequest} - No additional fields</li>
 *   <li>{@link FreezeAndSeizeRegisterRequest} - adminPubKeyHash, blacklistNodePolicyId</li>
 * </ul>
 */
@JsonTypeInfo(
        use = JsonTypeInfo.Id.NAME,
        include = JsonTypeInfo.As.EXISTING_PROPERTY,
        property = "substandardId",
        visible = true
)
@JsonSubTypes({
        @JsonSubTypes.Type(value = DummyRegisterRequest.class, name = "dummy"),
        @JsonSubTypes.Type(value = FreezeAndSeizeRegisterRequest.class, name = "freeze-and-seize")
})
@Data
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
public abstract class RegisterTokenRequest {

    /**
     * The substandard identifier (discriminator for polymorphic deserialization).
     */
    private String substandardId;

    /**
     * The address that pays for the transaction fees.
     */
    private String feePayerAddress;

    /**
     * The asset name for the programmable token (hex-encoded).
     */
    private String assetName;

    /**
     * The quantity of tokens to mint during registration.
     */
    private String quantity;

    /**
     * The recipient address for the minted tokens.
     */
    private String recipientAddress;

    /**
     * Optional tx hash that can be used to mempool chaining tx, it's assumed to have a few ada (10 ada+)
     */
    private String chainingTransactionCborHex;

}
