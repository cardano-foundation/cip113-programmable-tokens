package org.cardanofoundation.cip113.model.bootstrap;

import com.bloxbean.cardano.client.api.model.Utxo;
import lombok.Builder;

@Builder
public record TxInput(String txHash, int outputIndex) {

    public static TxInput from(Utxo utxo) {
        return TxInput.builder()
                .txHash(utxo.getTxHash())
                .outputIndex(utxo.getOutputIndex())
                .build();
    }

}
