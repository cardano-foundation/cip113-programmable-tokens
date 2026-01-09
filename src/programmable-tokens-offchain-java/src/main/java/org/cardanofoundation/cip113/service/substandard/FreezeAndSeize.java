package org.cardanofoundation.cip113.service.substandard;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.plutus.spec.PlutusScript;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.model.UtxoId;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.repository.UtxoRepository;
import com.easy1staking.cardano.util.UtxoUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.model.*;
import org.cardanofoundation.cip113.model.bootstrap.ProtocolBootstrapParams;
import org.cardanofoundation.cip113.model.onchain.RegistryNodeParser;
import org.cardanofoundation.cip113.service.AccountService;
import org.cardanofoundation.cip113.service.ProtocolScriptBuilderService;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.cardanofoundation.cip113.util.PlutusSerializationHelper;
import org.springframework.stereotype.Service;

import java.util.Optional;
import java.util.Set;

import static java.math.BigInteger.ONE;

/**
 * Handler for the "dummy" programmable token substandard.
 * This is a simple reference implementation with basic issue and transfer validators.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class FreezeAndSeize implements SubstandardHandler {

    private static final String SUBSTANDARD_NAME = "freeze-and-seize";

    private final ObjectMapper objectMapper;

    private final AppConfig.Network network;

    private final UtxoRepository utxoRepository;

    private final RegistryNodeParser registryNodeParser;

    private final AccountService accountService;

    private final SubstandardService substandardService;

    private final ProtocolScriptBuilderService protocolScriptBuilderService;

    private final QuickTxBuilder quickTxBuilder;

    @Override
    public String getSubstandardId() {
        return SUBSTANDARD_NAME;
    }

    public record FreezeAndSiezeBlacklistInitRequest(TransactionInput bootstrapUtxo, String adminAddress) {

    }

    public Optional<String> initBlacklist(FreezeAndSiezeBlacklistInitRequest blacklistInitRequest) {

        var bootstrapUtxoOpt = utxoRepository.findById(UtxoId.builder()
                        .txHash(blacklistInitRequest.bootstrapUtxo().getTransactionId())
                        .outputIndex(blacklistInitRequest.bootstrapUtxo().getIndex())
                        .build())
                .map(UtxoUtil::toUtxo);

        if (bootstrapUtxoOpt.isEmpty()) {
            log.warn("blacklist utxo init now found: {}", blacklistInitRequest.bootstrapUtxo());
            return Optional.empty();
        }

        var adminAddress = new Address(blacklistInitRequest.adminAddress());

        var blackListMintValidatorOpt = substandardService.getSubstandardValidator(SUBSTANDARD_NAME, "blacklist_mint.blacklist_mint.mint");
        var blackListMintValidator = blackListMintValidatorOpt.get();

        var serialisedTxInput = PlutusSerializationHelper.serialize(blacklistInitRequest.bootstrapUtxo());

        var blacklistInitParams = ListPlutusData.of(serialisedTxInput, BytesPlutusData.of(adminAddress.getPaymentCredentialHash().get()));

        var script = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                AikenScriptUtil.applyParamToScript(blacklistInitParams, blackListMintValidator.scriptBytes()),
                PlutusVersion.v3
        );

        var adminUtxos = accountService.findAdaOnlyUtxo(blacklistInitRequest.adminAddress(), 10_000_000L);

//        var tx = new ScriptTx()
//                .collectFrom(adminUtxos)
//                .mintAsset(script, Asset.builder().name().value(ONE).build(), )

        return Optional.empty();
    }

    @Override
    public RegisterTransactionContext buildRegistrationTransaction(RegisterTokenRequest request, ProtocolBootstrapParams protocolParams) {
        return null;
    }

    @Override
    public TransactionContext buildMintTransaction(MintTokenRequest request, ProtocolBootstrapParams protocolParams) {
        return null;
    }

    @Override
    public TransactionContext buildTransferTransaction(TransferTokenRequest request, ProtocolBootstrapParams protocolParams) {
        return null;
    }

    @Override
    public Set<String> getRequiredValidators() {
        return Set.of();
    }

    @Override
    public PlutusScript getParameterizedIssueValidator(String contractName, Object... params) {
        return null;
    }

    @Override
    public PlutusScript getParameterizedTransferValidator(String contractName, Object... params) {
        return null;
    }

    @Override
    public PlutusScript getParameterizedThirdPartyValidator(String contractName, Object... params) {
        return null;
    }
}
