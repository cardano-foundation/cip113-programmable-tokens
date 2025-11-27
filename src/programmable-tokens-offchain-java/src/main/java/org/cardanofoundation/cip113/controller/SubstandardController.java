package org.cardanofoundation.cip113.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.Substandard;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("${apiPrefix}/substandards")
@RequiredArgsConstructor
@Slf4j
public class SubstandardController {

    private final SubstandardService substandardService;

    /**
     * Get all substandards
     *
     * @return list of all substandards with their validators
     */
    @GetMapping
    public ResponseEntity<List<Substandard>> getAllSubstandards() {
        log.debug("GET /substandards - fetching all substandards");
        List<Substandard> substandards = substandardService.getAllSubstandards();
        return ResponseEntity.ok(substandards);
    }

    /**
     * Get a specific substandard by ID (folder name)
     *
     * @param id the substandard ID (folder name in substandards directory)
     * @return the substandard with its validators or 404 if not found
     */
    @GetMapping("/{id}")
    public ResponseEntity<Substandard> getSubstandardById(@PathVariable String id) {
        log.debug("GET /substandards/{} - fetching substandard by id", id);
        return substandardService.getSubstandardById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
}
