package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProtocolParamsEntity;
import org.cardanofoundation.cip113.service.ProtocolParamsService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("${apiPrefix}/protocol-params")
@RequiredArgsConstructor
@Slf4j
public class ProtocolParamsController {

    private final ProtocolParamsService protocolParamsService;

    /**
     * Get the latest protocol params version
     *
     * @return the latest protocol params or 404 if none exist
     */
    @GetMapping("/latest")
    public ResponseEntity<ProtocolParamsEntity> getLatest() {
        log.debug("GET /latest - fetching latest protocol params");
        return protocolParamsService.getLatest()
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get all protocol params versions (ordered by slot ascending)
     *
     * @return list of all protocol params
     */
    @GetMapping("/all")
    public ResponseEntity<List<ProtocolParamsEntity>> getAll() {
        log.debug("GET /all - fetching all protocol params");
        List<ProtocolParamsEntity> allParams = protocolParamsService.getAll();
        return ResponseEntity.ok(allParams);
    }

    /**
     * Get protocol params by transaction hash
     *
     * @param txHash the transaction hash
     * @return the protocol params or 404 if not found
     */
    @GetMapping("/by-tx/{txHash}")
    public ResponseEntity<ProtocolParamsEntity> getByTxHash(@PathVariable String txHash) {
        log.debug("GET /by-tx/{} - fetching protocol params by tx hash", txHash);
        return protocolParamsService.getByTxHash(txHash)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get protocol params by slot number
     *
     * @param slot the slot number
     * @return the protocol params or 404 if not found
     */
    @GetMapping("/by-slot/{slot}")
    public ResponseEntity<ProtocolParamsEntity> getBySlot(@PathVariable Long slot) {
        log.debug("GET /by-slot/{} - fetching protocol params by slot", slot);
        return protocolParamsService.getBySlot(slot)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Get protocol params valid at a given slot (closest version <= slot)
     *
     * @param slot the slot number
     * @return the protocol params valid at that slot or 404 if none
     */
    @GetMapping("/valid-at-slot/{slot}")
    public ResponseEntity<ProtocolParamsEntity> getValidAtSlot(@PathVariable Long slot) {
        log.debug("GET /valid-at-slot/{} - fetching protocol params valid at slot", slot);
        return protocolParamsService.getValidAtSlot(slot)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
}
