package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.WhitelistInitEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface WhitelistInitRepository extends JpaRepository<WhitelistInitEntity, String> {

    Optional<WhitelistInitEntity> findByWhitelistPolicyId(String whitelistPolicyId);

    boolean existsByWhitelistPolicyId(String whitelistPolicyId);
}
