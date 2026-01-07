package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.api.exception.ApiException;
import com.bloxbean.cardano.client.api.model.Utxo;
import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.model.UtxoId;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.repository.UtxoRepository;
import com.easy1staking.cardano.util.UtxoUtil;
import jakarta.annotation.Nullable;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
@Slf4j
public class UtxoService {

    private final BFBackendService bfBackendService;

    @Nullable
    private final UtxoRepository utxoRepository;

    public Optional<Utxo> findUtxo(String txHash, int outputIndex) {

        if (utxoRepository == null) {
            try {
                var utxoResult = bfBackendService.getUtxoService().getTxOutput(txHash, outputIndex);
                if (utxoResult.isSuccessful()) {
                    return Optional.of(utxoResult.getValue());
                } else {
                    return Optional.empty();
                }
            } catch (ApiException e) {
                throw new RuntimeException(e);
            }
        } else {
            return utxoRepository.findById(UtxoId.builder()
                            .txHash(txHash)
                            .outputIndex(outputIndex)
                            .build())
                    .map(UtxoUtil::toUtxo);
        }

    }

    public List<Utxo> findUtxos(String address) {

        if (utxoRepository == null) {
            try {
                var utxoResult = bfBackendService.getUtxoService().getUtxos(address, 100, 1);
                if (utxoResult.isSuccessful()) {
                    return utxoResult.getValue();
                } else {
                    return List.of();
                }
            } catch (ApiException e) {
                throw new RuntimeException(e);
            }
        } else {
            return utxoRepository.findUnspentByOwnerAddr(address, Pageable.unpaged())
                    .stream()
                    .flatMap(Collection::stream)
                    .map(UtxoUtil::toUtxo)
                    .toList();
        }

    }

}
