package org.cardanofoundation.cip113;

import com.bloxbean.cardano.client.account.Account;
import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.client.common.model.Network;
import com.bloxbean.cardano.client.common.model.Networks;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.model.blueprint.Validator;

import java.util.List;

import static com.bloxbean.cardano.client.backend.blockfrost.common.Constants.BLOCKFROST_PREVIEW_URL;
import static org.cardanofoundation.cip113.PreviewConstants.BLOCKFROST_KEY;

@Slf4j
public abstract class AbstractPreviewTest {

    protected static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    protected static final Network network = Networks.preview();

    protected static final Account adminAccount = Account.createFromMnemonic(network, PreviewConstants.ADMIN_MNEMONIC);

    protected static final Account refInputAccount = Account.createFromMnemonic(network, PreviewConstants.ADMIN_MNEMONIC, 10, 0);

    protected static final Account aliceAccount = Account.createFromMnemonic(network, PreviewConstants.ADMIN_MNEMONIC, 1, 0);

    protected static final Account bobAccount = Account.createFromMnemonic(network, PreviewConstants.ADMIN_MNEMONIC, 2, 0);

    protected static final Account userWipeAccount = Account.createFromMnemonic(network, PreviewConstants.ADMIN_MNEMONIC, 3, 0);

    static {
        log.info("Admin Address: {}", adminAccount.baseAddress());
        log.info("Alice Address: {}", aliceAccount.baseAddress());
        log.info("Bob Address: {}", bobAccount.baseAddress());
        log.info("Wipe Address: {}", userWipeAccount.baseAddress());
    }

    protected final BFBackendService bfBackendService = new BFBackendService(BLOCKFROST_PREVIEW_URL, BLOCKFROST_KEY);

    protected final QuickTxBuilder quickTxBuilder = new QuickTxBuilder(bfBackendService);

    protected String getCompiledCodeFor(String contractTitle, List<Validator> validators) {
        return validators.stream().filter(validator -> validator.title().equals(contractTitle)).findAny().get().compiledCode();
    }

}
