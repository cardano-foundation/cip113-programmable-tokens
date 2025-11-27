package com.easy1staking.liqwidfinance.liquidation.bot.config;

import com.bloxbean.cardano.client.api.ProtocolParamsSupplier;
import com.bloxbean.cardano.client.api.TransactionProcessor;
import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.bloxbean.cardano.yaci.core.common.Constants;
import com.bloxbean.cardano.yaci.helper.LocalClientProvider;
import com.bloxbean.cardano.yaci.helper.LocalTxSubmissionClient;
import com.easy1staking.liqwidfinance.liquidation.bot.service.DefaultLocalTxSubmissionListener;
import com.easy1staking.liqwidfinance.liquidation.bot.service.HybridScriptSupplier;
import com.easy1staking.liqwidfinance.liquidation.bot.service.HybridUtxoSupplier;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.EnableScheduling;

@Configuration
@Profile("!test")
@Slf4j
@EnableScheduling
public class YaciConfiguration {

    @Bean
    public LocalClientProvider socatLocalClientProvider(@Value("${cardano.node.host}") String cardanoNodeHost,
                                                        @Value("${cardano.node.socat.port}") int cardanoNodeSocatPort) {
        log.info("INIT Cardano node: {}:{}", cardanoNodeHost, cardanoNodeSocatPort);
        LocalClientProvider localClientProvider = new LocalClientProvider(cardanoNodeHost, cardanoNodeSocatPort, Constants.MAINNET_PROTOCOL_MAGIC);
        localClientProvider.addTxSubmissionListener(new DefaultLocalTxSubmissionListener("NODE"));
        localClientProvider.start();
        return localClientProvider;
    }

    @Bean
    public LocalTxSubmissionClient socketLocalTxSubmissionClient(@Autowired LocalClientProvider localClientProvider) {
        return localClientProvider.getTxSubmissionClient();
    }

    @Bean
    public QuickTxBuilder quickTxBuilder(BFBackendService bfBackendService) {
        return new QuickTxBuilder(bfBackendService);
    }

    @Bean
    public QuickTxBuilder mempoolQuickTxBuilder(HybridUtxoSupplier hybridUtxoSupplier,
                                                TransactionProcessor transactionProcessor,
                                                HybridScriptSupplier hybridScriptSupplier,
                                                ProtocolParamsSupplier protocolParamsSupplier) {

        log.info("transactionProcessor: {}, class: {}", transactionProcessor, transactionProcessor.getClass());

        return new QuickTxBuilder(hybridUtxoSupplier,
                protocolParamsSupplier,
                hybridScriptSupplier,
                transactionProcessor);

    }

}
