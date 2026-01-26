package org.cardanofoundation.cip113.controller;

import com.easy1staking.cardano.model.AssetType;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.entity.ProgrammableTokenRegistryEntity;
import org.cardanofoundation.cip113.model.onchain.RegistryNode;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.repository.ProgrammableTokenRegistryRepository;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.cardanofoundation.cip113.service.UtxoProvider;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("${apiPrefix}/util")
@RequiredArgsConstructor
@Slf4j
public class UtilController {

    private final ProtocolBootstrapService protocolBootstrapService;

    private final UtxoProvider utxoProvider;

    private final RegistryNodeParser registryNodeParser;

    private final ProgrammableTokenRegistryRepository programmableTokenRegistryRepository;

    @GetMapping
    public ResponseEntity<?> resyncToken() {

        var dummyPolicyId = "93953ade00698f887283f7981297e5a84d19dfa3928371dbe429dee2";

        var protocolBootstrapParams = protocolBootstrapService.getProtocolBootstrapParams();

        var registryPaymentScriptHash = protocolBootstrapParams.directorySpendParams().scriptHash();
        var registryUtxos = utxoProvider.findUtxosByPaymentPkh(registryPaymentScriptHash);
        registryUtxos.forEach(utxo -> log.info("registry utxo: {}", utxo));

        var progTokenPolicyIds = registryUtxos.stream()
                .flatMap(utxo -> registryNodeParser.parse(utxo.getInlineDatum()).stream())
                .map(RegistryNode::key)
                .filter(key -> !"".equals(key))
                .toList();

        var programmableLogicBaseScriptHash = protocolBootstrapParams.programmableLogicBaseParams().scriptHash();

        var allProgTokensUtxos = utxoProvider.findUtxosByPaymentPkh(programmableLogicBaseScriptHash);
        allProgTokensUtxos.forEach(utxo -> log.info("prog token utxo: {}", utxo));

        allProgTokensUtxos.stream()
                .flatMap(utxo -> utxo.getAmount().stream())
                .map(amount -> AssetType.fromUnit(amount.getUnit()))
                .filter(assetType -> progTokenPolicyIds.contains(assetType.policyId()))
                .forEach(assetType -> {
                    log.info("assetType: {}", assetType);
                    var substandardId = assetType.policyId().equals(dummyPolicyId) ? "dummy" : "freeze-and-seize";
                    programmableTokenRegistryRepository.save(ProgrammableTokenRegistryEntity.builder()
                            .policyId(assetType.policyId())
                            .assetName(assetType.assetName())
                            .substandardId(substandardId)
                            .build());
                });

        return ResponseEntity.ok().build();

    }

}
