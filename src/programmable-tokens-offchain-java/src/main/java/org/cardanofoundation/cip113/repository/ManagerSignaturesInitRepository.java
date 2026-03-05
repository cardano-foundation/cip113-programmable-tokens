package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.ManagerSignaturesInitEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ManagerSignaturesInitRepository extends JpaRepository<ManagerSignaturesInitEntity, String> {

    Optional<ManagerSignaturesInitEntity> findByManagerSigsPolicyId(String managerSigsPolicyId);

    List<ManagerSignaturesInitEntity> findByAdminPkh(String adminPkh);

    boolean existsByManagerSigsPolicyId(String managerSigsPolicyId);
}
