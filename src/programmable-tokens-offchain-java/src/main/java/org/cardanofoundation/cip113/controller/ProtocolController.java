package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.blueprint.Plutus;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("${apiPrefix}/protocol")
@RequiredArgsConstructor
@Slf4j
public class ProtocolController {

    private final ProtocolBootstrapService protocolBootstrapService;

    @GetMapping("/blueprint")
    public ResponseEntity<Plutus> getPlutus() {
        return ResponseEntity.ok(protocolBootstrapService.getPlutus());
    }

    @GetMapping("/bootstrap")
    public ResponseEntity<ProtocolBootstrapParams> getLatest(@RequestParam(required = false) String txHash) {
        if (txHash != null) {
            return protocolBootstrapService.getProtocolBootstrapParamsByTxHash(txHash)
                    .map(ResponseEntity::ok)
                    .orElse(ResponseEntity.notFound().build());
        } else {
            return ResponseEntity.ok(protocolBootstrapService.getProtocolBootstrapParams());
        }

    }


}
