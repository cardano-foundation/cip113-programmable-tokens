package org.cardanofoundation.cip113;

import com.bloxbean.cardano.client.account.Account;
import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.Test;

@Slf4j
public class AddressTest {


    @Test
    public void genMnemonics() {

        var account = new Account();
        log.info(account.mnemonic());


    }

}
