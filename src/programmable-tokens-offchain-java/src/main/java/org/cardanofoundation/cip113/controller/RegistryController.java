package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.RegistryNodeEntity;
import org.cardanofoundation.cip113.model.ProtocolParams;
import org.cardanofoundation.cip113.model.RegistryNode;
import org.cardanofoundation.cip113.model.RegistryNodes;
import org.cardanofoundation.cip113.service.ProtocolParamsService;
import org.cardanofoundation.cip113.service.RegistryService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("${apiPrefix}/registry")
@RequiredArgsConstructor
@Slf4j
public class RegistryController {

    private final RegistryService registryService;
    private final ProtocolParamsService protocolParamsService;

    /**
     * Get all registered tokens (across all protocol params versions)
     * Excludes sentinel nodes
     *
     * @return list of all registered tokens
     */
    @GetMapping("/tokens")
    public ResponseEntity<List<RegistryNodes>> getAllTokens(
            @RequestParam(required = false) Long protocolParamsId) {
        log.info("GET /tokens - protocolParamsId={}", protocolParamsId);

        List<RegistryNodeEntity> tokens;
        if (protocolParamsId != null) {
            tokens = registryService.getAllTokens(protocolParamsId);
        } else {
            tokens = registryService.getAllTokens();
        }

        var registryNodes = tokens.stream()
                .collect(Collectors.groupingBy(RegistryNodeEntity::getProtocolParams, Collectors.mapping(RegistryNode::from, Collectors.toList())))
                .entrySet()
                .stream()
                .map(protocolParamsEntity -> new RegistryNodes(new ProtocolParams(protocolParamsEntity.getKey().getRegistryNodePolicyId(), protocolParamsEntity.getKey().getProgLogicScriptHash()), protocolParamsEntity.getValue()))
                .toList();

        return ResponseEntity.ok(registryNodes);
    }

    /**
     * Get token configuration by policy ID
     *
     * @param policyId the token policy ID
     * @return the token configuration or 404 if not found
     */
    @GetMapping("/token/{policyId}")
    public ResponseEntity<RegistryNode> getTokenByPolicyId(@PathVariable String policyId) {
        log.debug("GET /token/{} - fetching token configuration", policyId);
        return registryService.getByKey(policyId)
                .map(RegistryNode::from)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Check if a token is registered as a programmable token
     *
     * @param policyId the token policy ID
     * @return map with "registered" boolean
     */
    @GetMapping("/is-registered/{policyId}")
    public ResponseEntity<Map<String, Boolean>> isTokenRegistered(@PathVariable String policyId) {
        log.debug("GET /is-registered/{} - checking if token is registered", policyId);
        boolean isRegistered = registryService.isTokenRegistered(policyId);
        Map<String, Boolean> response = new HashMap<>();
        response.put("registered", isRegistered);
        return ResponseEntity.ok(response);
    }

    /**
     * Get all protocol params with their registry statistics
     *
     * @return list of protocol params with token counts
     */
    @GetMapping("/protocols")
    public ResponseEntity<List<Map<String, Object>>> getProtocolsWithStats() {
        log.debug("GET /protocols - fetching protocol params with registry stats");

        List<Map<String, Object>> result = protocolParamsService.getAll().stream()
                .map(pp -> {
                    Map<String, Object> stats = new HashMap<>();
                    stats.put("protocolParamsId", pp.getId());
                    stats.put("registryNodePolicyId", pp.getRegistryNodePolicyId());
                    stats.put("progLogicScriptHash", pp.getProgLogicScriptHash());
                    stats.put("slot", pp.getSlot());
                    stats.put("txHash", pp.getTxHash());
                    stats.put("tokenCount", registryService.countTokens(pp.getId()));
                    return stats;
                })
                .toList();

        return ResponseEntity.ok(result);
    }

    /**
     * Get tokens sorted in lexicographic order (linked list order)
     *
     * @param protocolParamsId the protocol params ID
     * @return list of tokens sorted by key
     */
    @GetMapping("/tokens/sorted")
    public ResponseEntity<List<RegistryNodes>> getTokensSorted(
            @RequestParam Long protocolParamsId) {
        log.debug("GET /tokens/sorted - protocolParamsId={}", protocolParamsId);
        List<RegistryNodeEntity> tokens = registryService.getTokensSorted(protocolParamsId);
        var registryNodes = tokens.stream()
                .collect(Collectors.groupingBy(RegistryNodeEntity::getProtocolParams, Collectors.mapping(RegistryNode::from, Collectors.toList())))
                .entrySet()
                .stream()
                .map(protocolParamsEntity -> new RegistryNodes(new ProtocolParams(protocolParamsEntity.getKey().getRegistryNodePolicyId(), protocolParamsEntity.getKey().getProgLogicScriptHash()), protocolParamsEntity.getValue()))
                .toList();
        return ResponseEntity.ok(registryNodes);
    }

    /**
     * Get all registry nodes including sentinel (for debugging)
     *
     * @param protocolParamsId the protocol params ID
     * @return list of all nodes including sentinel
     */
    @GetMapping("/nodes/all")
    public ResponseEntity<List<RegistryNodes>> getAllNodes(
            @RequestParam Long protocolParamsId) {
        log.debug("GET /nodes/all - protocolParamsId={}", protocolParamsId);
        List<RegistryNodeEntity> nodes = registryService.getAllNodes(protocolParamsId);
        var registryNodes = nodes.stream()
                .collect(Collectors.groupingBy(RegistryNodeEntity::getProtocolParams, Collectors.mapping(RegistryNode::from, Collectors.toList())))
                .entrySet()
                .stream()
                .map(protocolParamsEntity -> new RegistryNodes(new ProtocolParams(protocolParamsEntity.getKey().getRegistryNodePolicyId(), protocolParamsEntity.getKey().getProgLogicScriptHash()), protocolParamsEntity.getValue()))
                .toList();
        return ResponseEntity.ok(registryNodes);
    }
}
