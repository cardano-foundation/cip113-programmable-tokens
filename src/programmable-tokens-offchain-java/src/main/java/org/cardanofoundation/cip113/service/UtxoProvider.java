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
public class UtxoProvider {

    private final BFBackendService bfBackendService;

    @Nullable
    private final UtxoRepository utxoRepository;

    public Optional<Utxo> findUtxo(String txHash, int outputIndex) {
        // Always try Blockfrost first to avoid stale data from local DB
        try {
            var utxoResult = bfBackendService.getUtxoService().getTxOutput(txHash, outputIndex);
            if (utxoResult.isSuccessful()) {
                log.debug("Successfully found UTXO {}#{} via Blockfrost", txHash, outputIndex);
                // Check if we can determine if it's spent?
                // The SDK returns Utxo, likely filtering out spent ones or we assume the API
                // does.
                // For now, we assume if we get it here, it is valid.
                return Optional.of(utxoResult.getValue());
            } else {
                // If Blockfrost fails/checks for spent, we might get here.
                log.warn("getTxOutput failed for {}#{} via Blockfrost: {}", txHash, outputIndex,
                        utxoResult.getResponse());
            }
        } catch (Exception e) {
            log.warn("Blockfrost lookup failed for {}#{}: {}", txHash, outputIndex, e.getMessage());
        }

        if (utxoRepository == null) {
            // If we are here, Blockfrost failed and we have no local DB
            return Optional.empty();
        } else {
            var utxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(txHash)
                    .outputIndex(outputIndex)
                    .build())
                    .map(UtxoUtil::toUtxo);

            if (utxoOpt.isEmpty()) {
                log.info("UTXO {}#{} not found in local DB either", txHash, outputIndex);
            }
            return utxoOpt;
        }

    }

    public List<Utxo> findUtxos(String address) {
        log.debug("Finding UTXOs for address: {}", address);

        // Always try Blockfrost first to avoid stale data from local DB
        try {
            log.debug("Prioritizing Blockfrost for UTXOs at address: {}", address);
            return getBlockfrostUtxos(address);
        } catch (Exception e) {
            log.warn("Failed to fetch UTXOs from Blockfrost: {}", e.getMessage());
        }

        if (utxoRepository != null) {
            log.debug("Falling back to local DB for address: {}", address);
            var utxos = utxoRepository.findUnspentByOwnerAddr(address, Pageable.unpaged())
                    .stream()
                    .flatMap(Collection::stream)
                    .map(UtxoUtil::toUtxo)
                    .toList();

<<<<<<< HEAD
            log.debug("Found {} UTXOs in local DB for address: {}", utxos.size(), address);
            return utxos;
=======
            if (utxos.isEmpty()) {
                log.info("No UTxos found for address {}", address);
                // falling back on blockfrost if indexer is behind
                return getBlockfrostUtxos(address);
            } else {
                return utxos;
            }

>>>>>>> upstream/main
        }

        return List.of();
    }

    private List<Utxo> getBlockfrostUtxos(String address) {
        try {
            log.debug("Querying Blockfrost for UTXOs at address: {}", address);
            var utxoResult = bfBackendService.getUtxoService().getUtxos(address, 100, 1);
            if (utxoResult.isSuccessful()) {
                var utxos = utxoResult.getValue();
                log.info("Blockfrost returned {} UTXOs for address: {}", utxos.size(), address);
                return utxos;
            } else {
                log.error("Blockfrost query failed for address {}: {}", address, utxoResult.getResponse());
                return List.of();
            }
        } catch (ApiException e) {
            log.error("ApiException while querying Blockfrost for address {}: {}", address, e.getMessage(), e);
            throw new RuntimeException(e);
        } catch (Exception e) {
            log.error("Unexpected exception while querying Blockfrost for address {}: {}", address, e.getMessage(), e);
            throw new RuntimeException(e);
        }
    }

    public List<Utxo> findUtxosByPaymentPkh(String paymentPkh) {

        if (utxoRepository == null) {
            throw new RuntimeException("Unsupported");
        } else {
            return utxoRepository.findUnspentByOwnerPaymentCredential(paymentPkh, Pageable.unpaged())
                    .stream()
                    .flatMap(Collection::stream)
                    .map(UtxoUtil::toUtxo)
                    .toList();
        }

    }

    /**
     * Find UTxOs by stake credential (delegation credential).
     * For programmable tokens, the user's payment PKH is used as the stake credential.
     *
     * @param stakePkh The stake key hash / delegation credential
     * @return List of UTxOs with this stake credential
     */
    public List<Utxo> findUtxosByStakePkh(String stakePkh) {

        if (utxoRepository == null) {
            throw new RuntimeException("Unsupported - requires local UTXO repository");
        } else {
            return utxoRepository.findUnspentByOwnerStakeCredential(stakePkh, Pageable.unpaged())
                    .stream()
                    .flatMap(Collection::stream)
                    .map(UtxoUtil::toUtxo)
                    .toList();
        }

    }

}
