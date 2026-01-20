package org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist;

import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.PlutusData;
import com.bloxbean.cardano.client.util.HexUtil;
import lombok.Builder;

@Builder(toBuilder = true)
public record BlacklistNode(String key, String next) {

    public PlutusData toPlutusData() {
        return ConstrPlutusData.of(0,
                BytesPlutusData.of(HexUtil.decodeHexString(key)),
                BytesPlutusData.of(HexUtil.decodeHexString(next))
        );
    }

}
