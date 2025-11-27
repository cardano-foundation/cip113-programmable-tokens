package org.cardanofoundation.cip113.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PostConstruct;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.blueprint.Plutus;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.springframework.stereotype.Service;

import java.io.IOException;

@Service
@RequiredArgsConstructor
@Slf4j
public class ProtocolBootstrapService {

    private final ObjectMapper objectMapper;

    @Getter
    private Plutus plutus;

    @Getter
    private ProtocolBootstrapParams protocolBootstrapParams;

    @PostConstruct
    public void init() {
        try {
            protocolBootstrapParams = objectMapper.readValue(this.getClass().getClassLoader().getResourceAsStream("protocolBootstrap.json"), ProtocolBootstrapParams.class);
             plutus = objectMapper.readValue(this.getClass().getClassLoader().getResourceAsStream("plutus.json"), Plutus.class);
        } catch (IOException e) {
            log.error("could not load bootstrap or protocol blueprint");
            throw new RuntimeException(e);
        }

    }

}
