package org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist;

import com.bloxbean.cardano.client.plutus.spec.PlutusData;
import com.bloxbean.cardano.client.util.HexUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.Optional;

@Component
@RequiredArgsConstructor
@Slf4j
public class BlacklistNodeParser {

    private final ObjectMapper objectMapper;

    public Optional<BlacklistNode> parse(String inlineDatum) {
        try {
            var data = PlutusData.deserialize(HexUtil.decodeHexString(inlineDatum));
            var jsonData = objectMapper.readTree(objectMapper.writeValueAsString(data));
            var fields = jsonData.path("fields");
            var key =fields.get(0).path("bytes").asText();
            var next =fields.get(1).path("bytes").asText();
            return Optional.of(new BlacklistNode(key, next));
        } catch (Exception e) {
            log.error("Failed to parse registry node from inline datum", e);
            return Optional.empty();
        }
    }


}
