package org.cardanofoundation.cip113;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

@SpringBootApplication(scanBasePackages = "org.cardanofoundation.cip113")
@EnableJpaRepositories("org.cardanofoundation.cip113.repository")
@EntityScan("org.cardanofoundation.cip113.entity")
public class Cip113OffchainApp {

    public static void main(String[] args) {
        SpringApplication.run(Cip113OffchainApp.class, args);
    }

}
