package org.cardanofoundation.cip113.repository;

import com.bloxbean.cardano.yaci.store.staking.storage.impl.model.StakeRegistrationEntity;
import com.bloxbean.cardano.yaci.store.staking.storage.impl.repository.StakeRegistrationRepository;
import org.springframework.context.annotation.Primary;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
@Primary
public interface CustomStakeRegistrationRepository extends StakeRegistrationRepository {

    @Query(value = """
            SELECT * FROM stake_registration
            WHERE address = :stakeAddress
            ORDER BY slot DESC, cert_index DESC
            LIMIT 1
            """, nativeQuery = true)
    Optional<StakeRegistrationEntity> findRegistrationsByStakeAddress(String stakeAddress);

}
