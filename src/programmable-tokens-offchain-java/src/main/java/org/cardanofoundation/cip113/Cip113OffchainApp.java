package org.cardanofoundation.cip113;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * Main Spring Boot Application for CIP-113 Programmable Tokens Off-Chain Service.
 *
 * <p>This application provides the off-chain indexing and API layer for CIP-113
 * programmable tokens on Cardano. It connects to a Cardano node via Yaci Store
 * to index on-chain data and exposes REST APIs for token operations.</p>
 *
 * <h2>Components</h2>
 * <ul>
 *   <li><b>Controllers:</b> REST endpoints for minting, transfers, and queries</li>
 *   <li><b>Services:</b> Business logic for token operations</li>
 *   <li><b>Repositories:</b> JPA repositories for indexed data</li>
 *   <li><b>Event Listeners:</b> Yaci Store integration for blockchain indexing</li>
 * </ul>
 *
 * <h2>Configuration</h2>
 * <p>See application.yaml for network configuration (preview, preprod, mainnet).</p>
 *
 * @see org.cardanofoundation.cip113.config.AppConfig
 * @see org.cardanofoundation.cip113.service.ProtocolBootstrapService
 */
@SpringBootApplication(scanBasePackages = "org.cardanofoundation.cip113")
@EnableJpaRepositories("org.cardanofoundation.cip113.repository")
@EntityScan("org.cardanofoundation.cip113.entity")
public class Cip113OffchainApp {

    public static void main(String[] args) {
        SpringApplication.run(Cip113OffchainApp.class, args);
    }

}
