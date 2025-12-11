package org.cardanofoundation.cip113;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * CIP-0113 Off-Chain Service Application.
 *
 * <p>This Spring Boot application provides the backend REST API for the CIP-0113
 * Programmable Tokens protocol. It handles:
 * <ul>
 *   <li>Transaction building for token operations (mint, transfer, register)</li>
 *   <li>Blockchain indexing via Yaci UTxO sync</li>
 *   <li>Protocol configuration and bootstrap management</li>
 *   <li>Balance tracking and registry queries</li>
 * </ul>
 *
 * <h2>Architecture</h2>
 * <ul>
 *   <li><b>Controllers</b>: REST endpoints for frontend communication</li>
 *   <li><b>Services</b>: Business logic and transaction building</li>
 *   <li><b>Repositories</b>: JPA data access for indexed blockchain data</li>
 *   <li><b>Contracts</b>: Plutus script wrappers for validation</li>
 * </ul>
 *
 * <h2>Configuration</h2>
 * <p>Configure via {@code application.yaml} or environment variables:
 * <ul>
 *   <li>{@code NETWORK}: Target Cardano network (preview, preprod, mainnet)</li>
 *   <li>{@code DB_URL}: PostgreSQL connection URL</li>
 *   <li>{@code BLOCKFROST_API_KEY}: Blockfrost API key for chain queries</li>
 * </ul>
 *
 * @see org.cardanofoundation.cip113.service.ProtocolBootstrapService
 * @see org.cardanofoundation.cip113.controller.IssueTokenController
 */
@SpringBootApplication(scanBasePackages = "org.cardanofoundation.cip113")
@EnableJpaRepositories("org.cardanofoundation.cip113.repository")
@EntityScan("org.cardanofoundation.cip113.entity")
public class Cip113OffchainApp {

    public static void main(String[] args) {
        SpringApplication.run(Cip113OffchainApp.class, args);
    }

}
