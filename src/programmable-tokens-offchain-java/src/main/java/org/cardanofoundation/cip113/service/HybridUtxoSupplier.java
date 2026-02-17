package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.api.model.Utxo;
import com.bloxbean.cardano.client.backend.api.DefaultUtxoSupplier;
import com.bloxbean.cardano.client.backend.api.UtxoService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;
import java.util.Vector;

@Service
@Slf4j
public class HybridUtxoSupplier extends DefaultUtxoSupplier {

    private final List<Utxo> mempoolUtxo = new Vector<>();

    public HybridUtxoSupplier(UtxoService utxoService) {
        super(utxoService);
    }

    @Override
    public Optional<Utxo> getTxOutput(String txHash, int outputIndex) {
        log.info("Get tx output: {}:{}", txHash, outputIndex);
        return mempoolUtxo.stream()
                .filter(utxo -> utxo.getTxHash().equals(txHash) && utxo.getOutputIndex() == outputIndex)
                .findFirst()
                .or(()->super.getTxOutput(txHash, outputIndex));
    }

    public void add(Utxo utxo) {
        log.info("adding utxo: {}", utxo);
        mempoolUtxo.add(utxo);
    }

    public void clear() {
        log.info("clearing utxos");
        mempoolUtxo.clear();
    }

}
