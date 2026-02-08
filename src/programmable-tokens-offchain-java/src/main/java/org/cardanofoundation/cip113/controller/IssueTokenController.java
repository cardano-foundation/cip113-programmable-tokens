package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.BurnTokenRequest;
import org.cardanofoundation.cip113.model.MintTokenRequest;
import org.cardanofoundation.cip113.model.RegisterTokenRequest;
import org.cardanofoundation.cip113.model.RegisterTokenResponse;
import org.cardanofoundation.cip113.service.TokenOperationsService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("${apiPrefix}/issue-token")
@RequiredArgsConstructor
@Slf4j
public class IssueTokenController {

    private final TokenOperationsService tokenOperationsService;

    @PostMapping("/pre-register")
    public ResponseEntity<?> preRegisterToken(
            @RequestBody RegisterTokenRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("preRegisterToken request: {}, protocolTxHash: {}", request, protocolTxHash);

        try {
            var txContext = tokenOperationsService.preRegisterToken(request, protocolTxHash);

            if (txContext.isSuccessful()) {
                return ResponseEntity.ok(txContext);
            } else {
                return ResponseEntity.badRequest().body(txContext.error());
            }
        } catch (Exception e) {
            log.warn("error", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(
            @RequestBody RegisterTokenRequest registerTokenRequest,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("registerTokenRequest: {}, protocolTxHash: {}", registerTokenRequest, protocolTxHash);

        try {

            var result = tokenOperationsService.registerToken(registerTokenRequest, protocolTxHash);

            if (result.isSuccessful()) {
                return ResponseEntity.ok(new RegisterTokenResponse(result.metadata().policyId(), result.unsignedCborTx()));
            } else {
                return ResponseEntity.badRequest().body(result.error());
            }

        } catch (Exception e) {
            log.warn("error", e);
            return ResponseEntity.internalServerError().build();
        }
    }


    @PostMapping("/mint")
    public ResponseEntity<?> mint(@RequestBody MintTokenRequest mintTokenRequest,
                                  @RequestParam(required = false) String protocolTxHash) {

        try {

            var transactionContext = tokenOperationsService.mintToken(mintTokenRequest, protocolTxHash);

            if (transactionContext.isSuccessful()) {
                return ResponseEntity.ok(transactionContext.unsignedCborTx());
            } else {
                return ResponseEntity.internalServerError().body(transactionContext.error());
            }


        } catch (Exception e) {
            log.warn("error", e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    @PostMapping("/burn")
    public ResponseEntity<String> burnToken(
            @RequestBody BurnTokenRequest request,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("POST /issue-token/burn - policyId: {}, assetName: {}, quantity: {}, utxo: {}#{}",
                request.tokenPolicyId(), request.assetName(), request.quantity(),
                request.utxoTxHash(), request.utxoOutputIndex());

        try {
            // Call burn-specific method that preserves UTxO information
            var txContext = tokenOperationsService.burnToken(request, protocolTxHash);

            if (!txContext.isSuccessful()) {
                log.error("Burn transaction build failed: {}", txContext.error());
                return ResponseEntity.badRequest().body(txContext.error());
            }

            log.info("Burn transaction built successfully");
            return ResponseEntity.ok(txContext.unsignedCborTx());

        } catch (Exception e) {
            log.error("Failed to build burn transaction", e);
            return ResponseEntity.internalServerError()
                    .body("Failed to build burn transaction: " + e.getMessage());
        }
    }


}
