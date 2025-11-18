package org.cardanofoundation.cip113.model.onchain;

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
public class ProtocolParamsParser {

    private final ObjectMapper objectMapper;

    public Optional<ProtocolParams> parse(String inlineDatum) {
        try {

            var data = PlutusData.deserialize(HexUtil.decodeHexString(inlineDatum));
            var jsonData = objectMapper.readTree(objectMapper.writeValueAsString(data));
            log.info("jsonData: {}", jsonData);

            var registryNodePolicyId = jsonData.path("fields").get(0).path("bytes").asText();
            var programmableLogicBaseScriptHash = jsonData.path("fields").get(1).path("fields").get(0).path("bytes").asText();

            return Optional.of(ProtocolParams.builder()
                    .registryNodePolicyId(registryNodePolicyId)
                    .programmableLogicBaseScriptHash(programmableLogicBaseScriptHash)
                    .build());
        } catch (Exception e) {
            log.warn("error", e);
            return Optional.empty();
        }
    }


}
