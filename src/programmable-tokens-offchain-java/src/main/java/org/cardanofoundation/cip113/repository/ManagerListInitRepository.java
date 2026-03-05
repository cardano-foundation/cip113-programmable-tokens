package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.ManagerListInitEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ManagerListInitRepository extends JpaRepository<ManagerListInitEntity, String> {

    Optional<ManagerListInitEntity> findByManagerListPolicyId(String managerListPolicyId);

    List<ManagerListInitEntity> findByManagerSigsInit_ManagerSigsPolicyId(String managerSigsPolicyId);

    boolean existsByManagerListPolicyId(String managerListPolicyId);
}
