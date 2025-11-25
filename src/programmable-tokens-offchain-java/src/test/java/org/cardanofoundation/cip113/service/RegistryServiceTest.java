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
    void testUpsertNewNode() {
        // Given
        RegistryNodeEntity entity = createNode("token123", "token456");

        // When
        RegistryNodeEntity saved = registryService.upsert(entity);

        // Then
        assertNotNull(saved.getId());
        assertEquals("token123", saved.getKey());
        assertEquals("token456", saved.getNext());
        assertTrue(registryService.isTokenRegistered("token123"));
    }

    @Test
    void testUpsertUpdateNextField() {
        // Given - create initial node
        RegistryNodeEntity entity1 = createNode("token123", "token456");
        registryService.upsert(entity1);

        // When - update 'next' field
        RegistryNodeEntity entity2 = createNode("token123", "token789");
        entity2.setLastTxHash("newTxHash");
        entity2.setLastSlot(200000L);
        RegistryNodeEntity updated = registryService.upsert(entity2);

        // Then
        assertEquals("token789", updated.getNext());
        assertEquals("newTxHash", updated.getLastTxHash());
        assertEquals(200000L, updated.getLastSlot());

        // Should only have one node
        assertEquals(1, registryNodeRepository.count());
    }

    @Test
    void testUpsertNoChangeSkipsUpdate() {
        // Given
        RegistryNodeEntity entity1 = createNode("token123", "token456");
        RegistryNodeEntity saved1 = registryService.upsert(entity1);

        // When - upsert same node with same 'next'
        RegistryNodeEntity entity2 = createNode("token123", "token456");
        entity2.setLastTxHash("differentTxHash");
        RegistryNodeEntity saved2 = registryService.upsert(entity2);

        // Then - should return existing without update
        assertEquals(saved1.getId(), saved2.getId());
        assertEquals(saved1.getLastTxHash(), saved2.getLastTxHash()); // Not updated
    }

    @Test
    void testGetAllTokensExcludesSentinel() {
        // Given
        RegistryNodeEntity sentinel = createNode("", "token123"); // Sentinel has empty key
        RegistryNodeEntity token1 = createNode("token123", "token456");
        RegistryNodeEntity token2 = createNode("token456", "ffffff");

        registryService.upsert(sentinel);
        registryService.upsert(token1);
        registryService.upsert(token2);

        // When
        List<RegistryNodeEntity> tokens = registryService.getAllTokens(protocolParams.getId());

        // Then - should exclude sentinel
        assertEquals(2, tokens.size());
        assertFalse(tokens.stream().anyMatch(t -> t.getKey().isEmpty()));
    }

    @Test
    void testGetTokensSortedByKey() {
        // Given - insert in random order
        RegistryNodeEntity token3 = createNode("ccc", "fff");
        RegistryNodeEntity token1 = createNode("aaa", "bbb");
        RegistryNodeEntity token2 = createNode("bbb", "ccc");

        registryService.upsert(token3);
        registryService.upsert(token1);
        registryService.upsert(token2);

        // When
        List<RegistryNodeEntity> sorted = registryService.getTokensSorted(protocolParams.getId());

        // Then - should be sorted alphabetically
        assertEquals(3, sorted.size());
        assertEquals("aaa", sorted.get(0).getKey());
        assertEquals("bbb", sorted.get(1).getKey());
        assertEquals("ccc", sorted.get(2).getKey());
    }

    @Test
    void testGetByKey() {
        // Given
        RegistryNodeEntity entity = createNode("token123", "token456");
        registryService.upsert(entity);

        // When
        RegistryNodeEntity found = registryService.getByKey("token123").orElseThrow();

        // Then
        assertEquals("token123", found.getKey());
        assertEquals("token456", found.getNext());
    }

    @Test
    void testIsTokenRegistered() {
        // Given
        RegistryNodeEntity entity = createNode("token123", "token456");
        registryService.upsert(entity);

        // Then
        assertTrue(registryService.isTokenRegistered("token123"));
        assertFalse(registryService.isTokenRegistered("nonexistent"));
    }

    @Test
    void testCountTokens() {
        // Given
        RegistryNodeEntity sentinel = createNode("", "token1");
        RegistryNodeEntity token1 = createNode("token1", "token2");
        RegistryNodeEntity token2 = createNode("token2", "fff");

        registryService.upsert(sentinel);
        registryService.upsert(token1);
        registryService.upsert(token2);

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
        RegistryNodeEntity node1 = createNode("token1", "fff");
        RegistryNodeEntity node2 = createNodeForProtocolParams("token2", "fff", protocolParams2);

        registryService.upsert(node1);
        registryService.upsert(node2);

        // When
        List<RegistryNodeEntity> tokens1 = registryService.getAllTokens(protocolParams.getId());
        List<RegistryNodeEntity> tokens2 = registryService.getAllTokens(protocolParams2.getId());
        List<RegistryNodeEntity> allTokens = registryService.getAllTokens();

        // Then
        assertEquals(1, tokens1.size());
        assertEquals(1, tokens2.size());
        assertEquals(2, allTokens.size());
    }

    private RegistryNodeEntity createNode(String key, String next) {
        return createNodeForProtocolParams(key, next, protocolParams);
    }

    private RegistryNodeEntity createNodeForProtocolParams(String key, String next, ProtocolParamsEntity pp) {
        return RegistryNodeEntity.builder()
                .key(key)
                .next(next)
                .transferLogicScript("transferScript123")
                .thirdPartyTransferLogicScript("thirdPartyScript456")
                .globalStatePolicyId("globalState789")
                .protocolParams(pp)
                .lastTxHash("txHash" + key)
                .lastSlot(100000L)
                .lastBlockHeight(1000L)
                .build();
    }
}
