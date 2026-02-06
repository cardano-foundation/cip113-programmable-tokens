package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.service.ScriptRegistrationService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * REST controller for script stake address registration operations.
 *
 * <p>Script stake addresses must be registered on-chain before they can be used
 * with the "withdraw 0" trick for validator invocation.</p>
 *
 * <p>Endpoints:</p>
 * <ul>
 *   <li>GET /check - Check if a stake address is registered</li>
 *   <li>POST /register - Build a transaction to register stake addresses</li>
 * </ul>
 */
@RestController
@RequestMapping("${apiPrefix}/script-registration")
@RequiredArgsConstructor
@Slf4j
public class ScriptRegistrationController {

    private final ScriptRegistrationService scriptRegistrationService;

    /**
     * Response for stake address registration check.
     */
    public record CheckRegistrationResponse(String stakeAddress, boolean isRegistered) {}

    /**
     * Request to register stake addresses.
     */
    public record RegisterStakeAddressRequest(
            List<String> stakeAddresses,
            String feePayerAddress
    ) {}

    /**
     * Response for stake address registration transaction.
     */
    public record RegisterStakeAddressResponse(String unsignedTx) {}

    /**
     * Check if a stake address is registered on-chain.
     *
     * @param stakeAddress The stake address to check (e.g., stake_test1...)
     * @return Registration status
     */
    @GetMapping("/check")
    public ResponseEntity<CheckRegistrationResponse> checkRegistration(
            @RequestParam String stakeAddress) {

        log.info("GET /script-registration/check - stakeAddress: {}", stakeAddress);

        try {
            boolean isRegistered = scriptRegistrationService.isStakeAddressRegistered(stakeAddress);
            return ResponseEntity.ok(new CheckRegistrationResponse(stakeAddress, isRegistered));

        } catch (Exception e) {
            log.error("Error checking stake address registration", e);
            return ResponseEntity.internalServerError().build();
        }
    }

    /**
     * Build a transaction to register one or more stake addresses.
     * The returned transaction must be signed and submitted by the caller.
     *
     * @param request The registration request containing stake addresses and fee payer
     * @return Unsigned CBOR transaction hex
     */
    @PostMapping("/register")
    public ResponseEntity<?> buildRegisterTransaction(
            @RequestBody RegisterStakeAddressRequest request) {

        log.info("POST /script-registration/register - addresses: {}, feePayer: {}",
                request.stakeAddresses(), request.feePayerAddress());

        try {
            if (request.stakeAddresses() == null || request.stakeAddresses().isEmpty()) {
                return ResponseEntity.badRequest().body("No stake addresses provided");
            }

            if (request.feePayerAddress() == null || request.feePayerAddress().isBlank()) {
                return ResponseEntity.badRequest().body("Fee payer address is required");
            }

            var txContext = scriptRegistrationService.buildRegisterStakeAddressTransaction(
                    request.stakeAddresses(),
                    request.feePayerAddress());

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(new RegisterStakeAddressResponse(txContext.unsignedCborTx()));
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }

        } catch (Exception e) {
            log.error("Error building stake address registration transaction", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }
}
