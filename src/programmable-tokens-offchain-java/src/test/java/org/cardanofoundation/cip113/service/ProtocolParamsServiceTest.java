package org.cardanofoundation.cip113.service;

import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.repository.ProtocolParamsRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

import static org.junit.jupiter.api.Assertions.*;

@DataJpaTest
@TestPropertySource(properties = {
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.flyway.enabled=false"
})
class ProtocolParamsServiceTest {

    @Autowired
    private ProtocolParamsRepository repository;

    private ProtocolParamsService service;

    @BeforeEach
    void setUp() {
        repository.deleteAll();
        service = new ProtocolParamsService(repository);
    }

    @Test
    void testSaveAndRetrieve() {
        // Given
        ProtocolParamsEntity entity = ProtocolParamsEntity.builder()
                .registryNodePolicyId("2584c485b40f65f3659dc94d36ee4389c3f95349f41437cb9b422160")
                .progLogicScriptHash("aaa513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126102")
                .txHash("eb59453ba52b87587c158879352e131bc69c6fdd245f6cd647b798e7393baf15")
                .slot(154984561L)
                .blockHeight(10000000L)
                .build();

        // When
        service.init(); // Initialize in-memory cache
        ProtocolParamsEntity saved = service.save(entity);

        // Then
        assertNotNull(saved.getId());
        assertEquals(entity.getTxHash(), saved.getTxHash());
        assertTrue(service.existsByTxHash(entity.getTxHash()));
    }

    @Test
    void testGetLatest() {
        // Given
        service.init();

        ProtocolParamsEntity entity1 = createEntity("txHash1", 100L, 1000L);
        ProtocolParamsEntity entity2 = createEntity("txHash2", 200L, 2000L);
        ProtocolParamsEntity entity3 = createEntity("txHash3", 150L, 1500L);

        // When
        service.save(entity1);
        service.save(entity2);
        service.save(entity3);

        // Then
        ProtocolParamsEntity latest = service.getLatest().orElseThrow();
        assertEquals("txHash2", latest.getTxHash());
        assertEquals(200L, latest.getSlot());
    }

    @Test
    void testGetValidAtSlot() {
        // Given
        service.init();

        ProtocolParamsEntity entity1 = createEntity("txHash1", 100L, 1000L);
        ProtocolParamsEntity entity2 = createEntity("txHash2", 200L, 2000L);
        ProtocolParamsEntity entity3 = createEntity("txHash3", 300L, 3000L);

        service.save(entity1);
        service.save(entity2);
        service.save(entity3);

        // When - query for slot between entity2 and entity3
        ProtocolParamsEntity validAt250 = service.getValidAtSlot(250L).orElseThrow();

        // Then - should return entity2 (closest version <= 250)
        assertEquals("txHash2", validAt250.getTxHash());
        assertEquals(200L, validAt250.getSlot());
    }

    @Test
    void testInMemoryCacheLoadedAtBoot() {
        // Given - save directly to repository
        ProtocolParamsEntity entity = createEntity("txHash1", 100L, 1000L);
        repository.save(entity);

        // When - initialize service (simulating boot)
        service.init();

        // Then - should be loaded in memory
        assertTrue(service.existsByTxHash("txHash1"));
        assertEquals(1, service.getAll().size());
    }

    @Test
    void testNoDuplicateTxHash() {
        // Given
        service.init();

        ProtocolParamsEntity entity1 = createEntity("sameTxHash", 100L, 1000L);
        ProtocolParamsEntity entity2 = createEntity("sameTxHash", 200L, 2000L);

        // When
        service.save(entity1);
        ProtocolParamsEntity saved = service.save(entity2);

        // Then - should return existing entity, not create duplicate
        assertEquals(entity1.getTxHash(), saved.getTxHash());
        assertEquals(1, service.getAll().size());
    }

    @Test
    void testGetAllOrderedBySlot() {
        // Given
        service.init();

        service.save(createEntity("txHash3", 300L, 3000L));
        service.save(createEntity("txHash1", 100L, 1000L));
        service.save(createEntity("txHash2", 200L, 2000L));

        // When
        var allParams = service.getAll();

        // Then - should be ordered by slot ascending
        assertEquals(3, allParams.size());
        assertEquals(100L, allParams.get(0).getSlot());
        assertEquals(200L, allParams.get(1).getSlot());
        assertEquals(300L, allParams.get(2).getSlot());
    }

    private ProtocolParamsEntity createEntity(String txHash, Long slot, Long blockHeight) {
        return ProtocolParamsEntity.builder()
                .registryNodePolicyId("2584c485b40f65f3659dc94d36ee4389c3f95349f41437cb9b422160")
                .progLogicScriptHash("aaa513b0fcc01d635f8535d49f38acc33d4d6b62ee8732ca6e126102")
                .txHash(txHash)
                .slot(slot)
                .blockHeight(blockHeight)
                .build();
    }
}
