package com.easy1staking.liqwidfinance.liquidation.bot.config;

import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

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
