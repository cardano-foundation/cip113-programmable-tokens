package org.cardanofoundation.cip113.util;

import com.bloxbean.cardano.client.plutus.spec.BigIntPlutusData;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.PlutusData;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.util.HexUtil;

public class PlutusSerializationHelper {

    public static PlutusData serialize(TransactionInput transactionInput) {
        return ConstrPlutusData.of(0,
                BytesPlutusData.of(HexUtil.decodeHexString(transactionInput.getTransactionId())),
                BigIntPlutusData.of(transactionInput.getIndex())
        );
    }

}
