package org.cardanofoundation.cip113.config;

import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Blockfrost API Configuration.
 *
 * <p>Configures the Blockfrost backend service for querying blockchain data
 * and submitting transactions. Blockfrost provides a simple HTTP API to
 * interact with the Cardano blockchain without running a full node.</p>
 *
 * <h2>Configuration Properties</h2>
 * <ul>
 *   <li><b>blockfrost.url:</b> Blockfrost API endpoint URL</li>
 *   <li><b>blockfrost.key:</b> Blockfrost project API key</li>
 * </ul>
 *
 * <h2>Usage</h2>
 * <p>The BFBackendService bean is injected into services that need to query
 * UTxOs, submit transactions, or fetch blockchain state.</p>
 *
 * @see com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService
 */
@Configuration
@Slf4j
public class BlockfrostConfig {

    @Value("${blockfrost.url}")
    private String blockfrostUrl;

    @Value("${blockfrost.key}")
    private String blockfrostKey;

    @Bean
    public BFBackendService bfBackendService() {
        log.info("INIT - Using BF url: {}", blockfrostUrl);
        return new BFBackendService(blockfrostUrl, blockfrostKey);
    }

}
