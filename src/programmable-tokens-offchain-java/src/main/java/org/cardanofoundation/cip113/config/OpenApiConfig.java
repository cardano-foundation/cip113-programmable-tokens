package org.cardanofoundation.cip113.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.servers.Server;
import io.swagger.v3.oas.models.tags.Tag;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;

/**
 * OpenAPI/Swagger configuration for CIP-113 Programmable Tokens API.
 *
 * <p>This configuration provides automatic API documentation generation
 * accessible at /swagger-ui.html and /v3/api-docs.</p>
 *
 * @see <a href="https://cips.cardano.org/cip/CIP-0113">CIP-0113 Specification</a>
 */
@Configuration
public class OpenApiConfig {

    @Value("${server.port:8080}")
    private String serverPort;

    @Value("${spring.profiles.active:default}")
    private String activeProfile;

    /**
     * Creates the OpenAPI specification for the CIP-113 API.
     *
     * @return configured OpenAPI object
     */
    @Bean
    public OpenAPI cip113OpenAPI() {
        return new OpenAPI()
                .info(apiInfo())
                .servers(List.of(
                        new Server()
                                .url("http://localhost:" + serverPort)
                                .description("Local development server"),
                        new Server()
                                .url("https://api.preview.cip113.cardano.org")
                                .description("Preview testnet server")
                ))
                .tags(List.of(
                        new Tag().name("Token Issuance")
                                .description("Endpoints for minting and managing programmable tokens"),
                        new Tag().name("Protocol")
                                .description("Protocol configuration and blueprint endpoints"),
                        new Tag().name("Substandards")
                                .description("CIP-113 substandard validators"),
                        new Tag().name("Registry")
                                .description("Token registry management"),
                        new Tag().name("Balances")
                                .description("Token balance queries"),
                        new Tag().name("History")
                                .description("Transaction history"),
                        new Tag().name("Protocol Parameters")
                                .description("Protocol parameter management"),
                        new Tag().name("Health")
                                .description("Service health checks")
                ));
    }

    private Info apiInfo() {
        return new Info()
                .title("CIP-113 Programmable Tokens API")
                .description("""
                        REST API for CIP-113 Programmable Tokens on Cardano.

                        ## Overview
                        This API enables minting and managing programmable tokens with embedded
                        validation logic on the Cardano blockchain. It supports various substandards
                        including blacklist, freezable, and permissioned token types.

                        ## Authentication
                        Currently, no authentication is required. Transactions are signed client-side
                        using wallet integration (Mesh SDK).

                        ## Key Features
                        - **Token Minting**: Create programmable tokens with custom validation rules
                        - **Transfer Validation**: Automatic compliance checking during transfers
                        - **Blacklist Management**: Address restriction for regulated tokens
                        - **Protocol Registry**: Track all issued programmable tokens

                        ## Related Resources
                        - [CIP-0113 Specification](https://cips.cardano.org/cip/CIP-0113)
                        - [GitHub Repository](https://github.com/cardano-foundation/cip113-programmable-tokens)
                        """)
                .version("1.0.0")
                .contact(new Contact()
                        .name("Cardano Foundation")
                        .url("https://cardanofoundation.org")
                        .email("info@cardanofoundation.org"))
                .license(new License()
                        .name("Apache 2.0")
                        .url("https://www.apache.org/licenses/LICENSE-2.0"));
    }
}
