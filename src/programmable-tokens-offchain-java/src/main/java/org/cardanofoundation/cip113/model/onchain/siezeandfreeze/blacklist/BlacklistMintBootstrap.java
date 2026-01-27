package org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist;

import org.cardanofoundation.cip113.model.bootstrap.TxInput;

public record BlacklistMintBootstrap(TxInput txInput, String adminPubKeyHash, String scriptHash) {


}
