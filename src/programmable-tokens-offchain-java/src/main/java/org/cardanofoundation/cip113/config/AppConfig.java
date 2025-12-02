package org.cardanofoundation.cip113.config;

import com.bloxbean.cardano.client.common.model.Networks;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.conversions.CardanoConverters;
import org.cardanofoundation.conversions.ClasspathConversionsFactory;
import org.cardanofoundation.conversions.domain.NetworkType;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.ArrayList;

/**
 * Application Configuration for CIP-113 Off-Chain Service.
 *
 * <p>Provides configuration beans and network setup for the Cardano blockchain
 * integration. Reads network settings from application properties and initializes
 * the appropriate Cardano network configuration.</p>
 *
 * <h2>Configuration Properties</h2>
 * <ul>
 *   <li><b>cardano.network:</b> Network name (preview, preprod, mainnet)</li>
 *   <li><b>cardano.protocol-magic:</b> Network protocol magic number</li>
 * </ul>
 *
 * <h2>Beans Provided</h2>
 * <ul>
 *   <li><b>CardanoConverters:</b> Utility for address and data conversions</li>
 *   <li><b>Network:</b> Cardano network configuration</li>
 * </ul>
 *
 * @see YaciConfiguration
 * @see BlockfrostConfig
 */
import java.util.List;

@Configuration
@EnableScheduling
@Slf4j
public class AppConfig {

    @Component
    @Getter
    public static class ProtocolParamsConfig {

        @Value("${network}")
        private String network;

        private List<String> transactionIds;

        @PostConstruct
        public void init() {
            try {
                ObjectMapper objectMapper = new ObjectMapper();
                String fileName = "protocol-params-" + network + ".json";
                ClassPathResource resource = new ClassPathResource(fileName);

                if (!resource.exists()) {
                    log.warn("Protocol params file not found: {}, using empty transaction list", fileName);
                    transactionIds = new ArrayList<>();
                    return;
                }

                JsonNode rootNode = objectMapper.readTree(resource.getInputStream());

                transactionIds = new ArrayList<>();
                JsonNode txIdsNode = rootNode.get("transaction_ids");
                if (txIdsNode != null && txIdsNode.isArray()) {
                    txIdsNode.forEach(node -> transactionIds.add(node.asText()));
                }

                log.info("Loaded {} transaction IDs from {} for network: {}", transactionIds.size(), fileName, network);
            } catch (IOException e) {
                log.error("Failed to load protocol-params-{}.json", network, e);
                transactionIds = new ArrayList<>();
            }
        }

    }

    @Component
    @Getter
    public static class Network {

        @Value("${network}")
        private String network;

        public com.bloxbean.cardano.client.common.model.Network getCardanoNetwork() {
            return switch (network) {
                case "preprod" -> Networks.preprod();
                case "preview" -> Networks.preview();
                default -> Networks.mainnet();
            };
        }

    }

    @Bean
    public CardanoConverters cardanoConverters(@Value("${network}") String network) {
        var networkType = switch (network) {
            case "preprod" -> NetworkType.PREPROD;
            case "preview" -> NetworkType.PREVIEW;
            default -> NetworkType.MAINNET;
        };
        log.info("INIT Converters network: {}, network type: {}", network, networkType);
        return ClasspathConversionsFactory.createConverters(networkType);
    }

}
