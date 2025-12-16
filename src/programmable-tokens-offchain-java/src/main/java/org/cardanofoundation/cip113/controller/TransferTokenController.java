package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.TransferTokenRequest;
import org.cardanofoundation.cip113.service.TokenOperationsService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("${apiPrefix}/transfer-token")
@RequiredArgsConstructor
@Slf4j
public class TransferTokenController {

    private final TokenOperationsService tokenOperationsService;

    @PostMapping("/transfer")
    public ResponseEntity<?> transfer(
            @RequestBody TransferTokenRequest transferTokenRequest,
            @RequestParam(required = false) String protocolTxHash) {

        log.info("transferTokenRequest: {}, protocolTxHash: {}", transferTokenRequest, protocolTxHash);

        try {

            var transactionContext = tokenOperationsService.transferToken(transferTokenRequest, protocolTxHash);

            if (transactionContext.isSuccessful()) {
                return ResponseEntity.ok(transactionContext.unsignedCborTx());
            } else {
                return ResponseEntity.internalServerError().body(transactionContext.error());
            }

        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }


}
