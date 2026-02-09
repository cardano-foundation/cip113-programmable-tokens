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
public class RegistryNodeParser {

    private final ObjectMapper objectMapper;

    public Optional<RegistryNode> parse(String inlineDatum) {
        try {
            var data = PlutusData.deserialize(HexUtil.decodeHexString(inlineDatum));
            var jsonData = objectMapper.readTree(objectMapper.writeValueAsString(data));
            System.out.println("Parsing registry node jsonData: " + jsonData);

            String rootName;
            if (jsonData.has("constructor")) {
                rootName = "fields";
            } else {
                rootName = "list";
            }

            var key = jsonData.path(rootName).get(0).path("bytes").asText();
            var next = jsonData.path(rootName).get(1).path("bytes").asText();
            var transferLogicScript = jsonData.path(rootName).get(2)
                    .path("fields").get(0).path("bytes").asText();
            var thirdPartyTransferLogicScript = jsonData.path(rootName).get(3)
                    .path("fields").get(0).path("bytes").asText();
            String globalStatePolicyId;
            if (jsonData.path(rootName).has(4)) {
                globalStatePolicyId = jsonData.path(rootName).get(4).path("bytes").asText();
            } else {
                globalStatePolicyId = "";
            }

            return Optional.of(RegistryNode.builder()
                    .key(key)
                    .next(next)
                    .transferLogicScript(transferLogicScript)
                    .thirdPartyTransferLogicScript(thirdPartyTransferLogicScript)
                    .globalStatePolicyId(globalStatePolicyId)
                    .build());
        } catch (Exception e) {
            System.out.println("Failed to parse registry node: " + e.getMessage());
            e.printStackTrace(System.out);
            return Optional.empty();
        }
    }

}
