package org.cardanofoundation.cip113.service;

import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.entity.RegistryNodeEntity;
import org.cardanofoundation.cip113.repository.ProtocolParamsRepository;
import org.cardanofoundation.cip113.repository.RegistryNodeRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

@DataJpaTest
@TestPropertySource(properties = {
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.flyway.enabled=false"
})
class RegistryServiceTest {

    @Autowired
    private RegistryNodeRepository registryNodeRepository;

    @Autowired
    private ProtocolParamsRepository protocolParamsRepository;

    private RegistryService registryService;
    private ProtocolParamsEntity protocolParams;

    @BeforeEach
    void setUp() {
        registryNodeRepository.deleteAll();
        protocolParamsRepository.deleteAll();

        // Create test protocol params
        protocolParams = ProtocolParamsEntity.builder()
                .registryNodePolicyId("testRegistryPolicyId123")
                .progLogicScriptHash("testProgLogicScriptHash456")
                .txHash("testTxHash789")
                .slot(100000L)
                .blockHeight(1000L)
                .build();
        protocolParams = protocolParamsRepository.save(protocolParams);

        registryService = new RegistryService(registryNodeRepository);
    }

    @Test
    void testInsertNewNode() {
        // Given
        RegistryNodeEntity entity = createNode("token123", "token456", 100L);

        // When
        RegistryNodeEntity saved = registryService.insert(entity);

        // Then
        assertNotNull(saved.getId());
        assertEquals("token123", saved.getKey());
        assertEquals("token456", saved.getNext());
        assertTrue(registryService.isTokenRegistered("token123"));
    }

    @Test
    void testInsertMultipleStatesForSameKey() {
        // Given - insert two states for same key (append-only log)
        RegistryNodeEntity state1 = createNode("token123", "token456", 100L);
        RegistryNodeEntity state2 = createNode("token123", "token789", 200L);
        state2.setTxHash("newTxHash");

        // When
        registryService.insert(state1);
        registryService.insert(state2);

        // Then - should have 2 entries in the log
        assertEquals(2, registryNodeRepository.count());

        // But queries should return the latest state (slot 200)
        RegistryNodeEntity latest = registryService.getByKey("token123").orElseThrow();
        assertEquals("token789", latest.getNext());
        assertEquals("newTxHash", latest.getTxHash());
        assertEquals(200L, latest.getSlot());
    }

    @Test
    void testDeletedNodesNotReturned() {
        // Given - insert a node then mark it as deleted
        RegistryNodeEntity state1 = createNode("token123", "token456", 100L);
        registryService.insert(state1);

        RegistryNodeEntity deletedState = createNode("token123", "token456", 200L);
        deletedState.setIsDeleted(true);
        registryService.insert(deletedState);

        // When
        List<RegistryNodeEntity> allTokens = registryService.getAllTokens(protocolParams.getId());

        // Then - should not include deleted token
        assertEquals(0, allTokens.size());
        assertFalse(registryService.isTokenRegistered("token123"));
    }

    @Test
    void testGetAllTokensExcludesSentinel() {
        // Given
        RegistryNodeEntity sentinel = createNode("", "token123", 100L); // Sentinel has empty key
        RegistryNodeEntity token1 = createNode("token123", "token456", 100L);
        RegistryNodeEntity token2 = createNode("token456", "ffffff", 100L);

        registryService.insert(sentinel);
        registryService.insert(token1);
        registryService.insert(token2);

        // When
        List<RegistryNodeEntity> tokens = registryService.getAllTokens(protocolParams.getId());

        // Then - should exclude sentinel
        assertEquals(2, tokens.size());
        assertFalse(tokens.stream().anyMatch(t -> t.getKey().isEmpty()));
    }

    @Test
    void testGetTokensSortedByKey() {
        // Given - insert in random order
        RegistryNodeEntity token3 = createNode("ccc", "fff", 100L);
        RegistryNodeEntity token1 = createNode("aaa", "bbb", 100L);
        RegistryNodeEntity token2 = createNode("bbb", "ccc", 100L);

        registryService.insert(token3);
        registryService.insert(token1);
        registryService.insert(token2);

        // When
        List<RegistryNodeEntity> sorted = registryService.getTokensSorted(protocolParams.getId());

        // Then - should be sorted alphabetically
        assertEquals(3, sorted.size());
        assertEquals("aaa", sorted.get(0).getKey());
        assertEquals("bbb", sorted.get(1).getKey());
        assertEquals("ccc", sorted.get(2).getKey());
    }

    @Test
    void testGetByKeyReturnsLatestState() {
        // Given - insert multiple states for same key
        RegistryNodeEntity state1 = createNode("token123", "token456", 100L);
        RegistryNodeEntity state2 = createNode("token123", "token789", 200L);
        RegistryNodeEntity state3 = createNode("token123", "tokenXYZ", 300L);

        registryService.insert(state1);
        registryService.insert(state2);
        registryService.insert(state3);

        // When
        RegistryNodeEntity found = registryService.getByKey("token123").orElseThrow();

        // Then - should return latest state (slot 300)
        assertEquals("token123", found.getKey());
        assertEquals("tokenXYZ", found.getNext());
        assertEquals(300L, found.getSlot());
    }

    @Test
    void testIsTokenRegistered() {
        // Given
        RegistryNodeEntity entity = createNode("token123", "token456", 100L);
        registryService.insert(entity);

        // Then
        assertTrue(registryService.isTokenRegistered("token123"));
        assertFalse(registryService.isTokenRegistered("nonexistent"));
    }

    @Test
    void testCountTokens() {
        // Given
        RegistryNodeEntity sentinel = createNode("", "token1", 100L);
        RegistryNodeEntity token1 = createNode("token1", "token2", 100L);
        RegistryNodeEntity token2 = createNode("token2", "fff", 100L);

        registryService.insert(sentinel);
        registryService.insert(token1);
        registryService.insert(token2);

        // When
        long count = registryService.countTokens(protocolParams.getId());

        // Then - should exclude sentinel
        assertEquals(2, count);
    }

    @Test
    void testMultipleProtocolParams() {
        // Given - create second protocol params
        ProtocolParamsEntity protocolParams2 = ProtocolParamsEntity.builder()
                .registryNodePolicyId("registry2")
                .progLogicScriptHash("logic2")
                .txHash("tx2")
                .slot(200000L)
                .blockHeight(2000L)
                .build();
        protocolParams2 = protocolParamsRepository.save(protocolParams2);

        // Create nodes for different registries
        RegistryNodeEntity node1 = createNode("token1", "fff", 100L);
        RegistryNodeEntity node2 = createNodeForProtocolParams("token2", "fff", 100L, protocolParams2);

        registryService.insert(node1);
        registryService.insert(node2);

        // When
        List<RegistryNodeEntity> tokens1 = registryService.getAllTokens(protocolParams.getId());
        List<RegistryNodeEntity> tokens2 = registryService.getAllTokens(protocolParams2.getId());
        List<RegistryNodeEntity> allTokens = registryService.getAllTokens();

        // Then
        assertEquals(1, tokens1.size());
        assertEquals(1, tokens2.size());
        assertEquals(2, allTokens.size());
    }

    private RegistryNodeEntity createNode(String key, String next, long slot) {
        return createNodeForProtocolParams(key, next, slot, protocolParams);
    }

    private RegistryNodeEntity createNodeForProtocolParams(String key, String next, long slot, ProtocolParamsEntity pp) {
        return RegistryNodeEntity.builder()
                .key(key)
                .next(next)
                .transferLogicScript("transferScript123")
                .thirdPartyTransferLogicScript("thirdPartyScript456")
                .globalStatePolicyId("globalState789")
                .protocolParams(pp)
                .txHash("txHash" + key + slot)
                .slot(slot)
                .blockHeight(1000L)
                .isDeleted(false)
                .build();
    }
}
