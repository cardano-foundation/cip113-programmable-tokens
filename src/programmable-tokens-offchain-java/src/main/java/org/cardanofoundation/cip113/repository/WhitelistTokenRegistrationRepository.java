package org.cardanofoundation.cip113.repository;

import org.cardanofoundation.cip113.entity.WhitelistTokenRegistrationEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface WhitelistTokenRegistrationRepository extends JpaRepository<WhitelistTokenRegistrationEntity, String> {

    Optional<WhitelistTokenRegistrationEntity> findByProgrammableTokenPolicyId(String programmableTokenPolicyId);

    List<WhitelistTokenRegistrationEntity> findByIssuerAdminPkh(String issuerAdminPkh);

    List<WhitelistTokenRegistrationEntity> findByWhitelistInit_WhitelistPolicyId(String whitelistPolicyId);

    List<WhitelistTokenRegistrationEntity> findByManagerListInit_ManagerListPolicyId(String managerListPolicyId);

    boolean existsByProgrammableTokenPolicyId(String programmableTokenPolicyId);
}
