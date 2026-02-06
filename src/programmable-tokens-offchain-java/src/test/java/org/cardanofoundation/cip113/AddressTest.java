package org.cardanofoundation.cip113;

import com.bloxbean.cardano.client.account.Account;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.common.model.Networks;
import com.bloxbean.cardano.client.exception.CborDeserializationException;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.PlutusData;
import com.bloxbean.cardano.client.util.HexUtil;
import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.Test;

@Slf4j
public class AddressTest {


    @Test
    public void genMnemonics() {

        var account = new Account();
        log.info(account.mnemonic());


    }

    @Test
    public void serde() throws CborDeserializationException {

        var version = "1.2.0";

        var plutusBytes = BytesPlutusData.of(HexUtil.encodeHexString(version.getBytes()));

        var bytesPlutusData = (BytesPlutusData) PlutusData.deserialize(plutusBytes.serializeToBytes());

        var actualVersion = bytesPlutusData.getValue();

        log.info(new String(HexUtil.decodeHexString(new String(actualVersion))));


    }

    @Test
    public void serde2() throws CborDeserializationException {

        var version = "1.2.0";

        var plutusBytes = BytesPlutusData.of(HexUtil.encodeHexString(version.getBytes()));

        var inlineDatum = plutusBytes.serializeToBytes();

        var bytesPlutusData = (BytesPlutusData) PlutusData.deserialize(inlineDatum);

        var actualVersion = bytesPlutusData.getValue();

        log.info(new String(HexUtil.decodeHexString(new String(actualVersion))));


    }

    @Test
    public void addressDerivationCIP() {

        var progTokenPaymentBasedAddress = AddressProvider.getBaseAddress(Credential.fromScript("f2182b00a37bd746e20575c9af01ab31312213514cd31e872e0a2a3e"),
                Credential.fromKey("faf7e92db401d6b222797a7f8135eb8f3d2a7b4587d2cfa31e8f1314"),
                Networks.preview());

        var progTokenStakingBasedAddress = AddressProvider.getBaseAddress(Credential.fromScript("f2182b00a37bd746e20575c9af01ab31312213514cd31e872e0a2a3e"),
                Credential.fromKey("7350def5f1aa50624fbaf6ac0f4f6ab36de826867b4ed20fe7a8dfea"),
                Networks.preview());

        log.info("progTokenPaymentBasedAddress: {}", progTokenPaymentBasedAddress.getAddress());
        log.info("progTokenStakingBasedAddress: {}", progTokenStakingBasedAddress.getAddress());

    }


}
