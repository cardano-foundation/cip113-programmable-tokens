package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.cardanofoundation.cip113.model.TokenContextResponse;
import org.cardanofoundation.cip113.repository.FreezeAndSeizeTokenRegistrationRepository;
import org.cardanofoundation.cip113.repository.ProgrammableTokenRegistryRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("${apiPrefix}/token-context")
@RequiredArgsConstructor
@Slf4j
public class TokenContextController {

    private final ProgrammableTokenRegistryRepository programmableTokenRegistryRepository;
    private final FreezeAndSeizeTokenRegistrationRepository freezeAndSeizeTokenRegistrationRepository;

    @GetMapping("/{policyId}")
    public ResponseEntity<TokenContextResponse> getTokenContext(@PathVariable String policyId) {
        var registryEntry = programmableTokenRegistryRepository.findByPolicyId(policyId);

        if (registryEntry.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        var substandardId = registryEntry.get().getSubstandardId();
        String blacklistNodePolicyId = null;

        if ("freeze-and-seize".equals(substandardId)) {
            var tokenRegistration = freezeAndSeizeTokenRegistrationRepository
                    .findByProgrammableTokenPolicyId(policyId);

            if (tokenRegistration.isPresent()) {
                var blacklistInit = tokenRegistration.get().getBlacklistInit();
                if (blacklistInit != null) {
                    blacklistNodePolicyId = blacklistInit.getBlacklistNodePolicyId();
                }
            }
        }

        return ResponseEntity.ok(new TokenContextResponse(
                policyId,
                substandardId,
                blacklistNodePolicyId
        ));
    }
}
