package org.cardanofoundation.cip113.config;

import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Yaci/Cardano Client Library Configuration.
 *
 * <p>Provides beans for building and submitting Cardano transactions using
 * the cardano-client-lib QuickTxBuilder. This simplifies transaction construction
 * by handling UTXO selection, fee calculation, and balancing automatically.</p>
 *
 * <h2>Transaction Building</h2>
 * <p>QuickTxBuilder uses the BFBackendService to query UTXOs and submit
 * transactions to the Cardano network via Blockfrost.</p>
 *
 * @see com.bloxbean.cardano.client.quicktx.QuickTxBuilder
 * @see BlockfrostConfig
 */
@Configuration
public class YaciConfiguration {

    @Bean
    public QuickTxBuilder quickTxBuilder(BFBackendService bfBackendService) {
        return new QuickTxBuilder(bfBackendService);
    }


}
