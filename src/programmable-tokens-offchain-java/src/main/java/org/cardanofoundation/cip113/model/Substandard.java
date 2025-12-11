package org.cardanofoundation.cip113.model;

import java.util.List;

/**
 * A substandard definition containing multiple validators.
 *
 * <p>Substandards are pre-built collections of validators that implement specific
 * token behavior patterns. Each substandard is loaded from a directory in
 * {@code resources/substandards/} containing a Plutus blueprint file.
 *
 * <h2>Common Substandards</h2>
 * <ul>
 *   <li><b>blacklist</b>: Block transfers to/from specific addresses</li>
 *   <li><b>whitelist</b>: Allow transfers only to approved addresses</li>
 *   <li><b>transfer-limit</b>: Enforce maximum transfer amounts</li>
 *   <li><b>kyc-required</b>: Require identity verification for transfers</li>
 * </ul>
 *
 * @param id The substandard identifier (directory name)
 * @param validators List of validators in this substandard
 * @see SubstandardValidator
 * @see org.cardanofoundation.cip113.service.SubstandardService
 */
public record Substandard(
        String id,
        List<SubstandardValidator> validators
) {
}
