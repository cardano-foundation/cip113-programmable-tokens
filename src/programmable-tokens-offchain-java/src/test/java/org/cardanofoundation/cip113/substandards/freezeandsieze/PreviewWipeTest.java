package org.cardanofoundation.cip113.substandards.freezeandsieze;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.aiken.AikenTransactionEvaluator;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.common.model.Network;
import com.bloxbean.cardano.client.common.model.Networks;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.fasterxml.jackson.core.JsonProcessingException;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.AbstractPreviewTest;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.service.*;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.util.List;

import static org.cardanofoundation.cip113.util.PlutusSerializationHelper.serialize;

@Slf4j
public class PreviewWipeTest extends AbstractPreviewTest {

    private static final String DEFAULT_PROTOCOL = "61fae36e28a62a65496907c9660da9cf5d27fa0e9054a04581e1d8a087fbd93e";

    private final Network network = Networks.preview();

    private final UtxoProvider utxoProvider = new UtxoProvider(bfBackendService, null);

    private final AccountService accountService = new AccountService(utxoProvider);

    private final ProtocolBootstrapService protocolBootstrapService = new ProtocolBootstrapService(OBJECT_MAPPER, new AppConfig.Network("preview"));

    private final ProtocolScriptBuilderService protocolScriptBuilderService = new ProtocolScriptBuilderService(protocolBootstrapService);

    private SubstandardService substandardService;

    @BeforeEach
    public void init() {
        substandardService = new SubstandardService(OBJECT_MAPPER);
        substandardService.init();

        protocolBootstrapService.init();
    }

    @Test
    public void test() throws Exception {

// BOB minted
        log.info("userWipeAccount.baseAddress(): {}", userWipeAccount.baseAddress());


        if (true) return;

        var dryRun = false;

        var substandardName = "freeze-and-seize";

        var issuerAdminAccount = bobAccount;

        var adminUtxos = accountService.findAdaOnlyUtxo(adminAccount.baseAddress(), 10_000_000L);

        var protocolBootstrapParamsOpt = protocolBootstrapService.getProtocolBootstrapParamsByTxHash(DEFAULT_PROTOCOL);
        var protocolBootstrapParams = protocolBootstrapParamsOpt.get();
        log.info("protocolBootstrapParams: {}", protocolBootstrapParams);

        var bootstrapTxHash = protocolBootstrapParams.txHash();

        var issuanceUtxoOpt = utxoProvider.findUtxo(bootstrapTxHash, 2);
        if (issuanceUtxoOpt.isEmpty()) {
            Assertions.fail("could not resolve issuance params");
        }
        var issuanceUtxo = issuanceUtxoOpt.get();
        log.info("issuanceUtxo: {}", issuanceUtxo);

        /// Getting Substandard Contracts and parameterize
        // Issuer to be used for minting/burning/sieze
        var issuerContractOpt = substandardService.getSubstandardValidator(substandardName, "example_transfer_logic.issuer_admin_contract.withdraw");
        var issuerContract = issuerContractOpt.get();

        var issuerAdminContractInitParams = ListPlutusData.of(serialize(issuerAdminAccount.getBaseAddress().getPaymentCredential().get()));

        var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                AikenScriptUtil.applyParamToScript(issuerAdminContractInitParams, issuerContract.scriptBytes()),
                PlutusVersion.v3
        );
        log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

        var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network);
        log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());


        var issuanceContract = protocolScriptBuilderService.getParameterizedIssuanceMintScript(protocolBootstrapParams, substandardIssueContract);
        log.info("issuanceContract: {}", issuanceContract.getPolicyId());

        var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));

        // Programmable Token Mint
        var programmableToken = Asset.builder()
                .name("0x" + HexUtil.encodeHexString("tUSDT".getBytes()))
                .value(BigInteger.valueOf(1_000_000_000_000L))
                .build();

        Value programmableTokenValue = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(issuanceContract.getPolicyId())
                                .assets(List.of(programmableToken))
                                .build()
                ))
                .build();

        var payeeAddress = aliceAccount.getBaseAddress();

        var targetAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                payeeAddress.getDelegationCredential().get(),
                network);


        var tx = new ScriptTx()
                .collectFrom(adminUtxos)
                .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, ConstrPlutusData.of(0))
                .mintAsset(issuanceContract, programmableToken, issuanceRedeemer)
                .payToContract(targetAddress.getAddress(), ValueUtil.toAmountList(programmableTokenValue), ConstrPlutusData.of(0))
                .attachRewardValidator(substandardIssueContract)
                .withChangeAddress(adminAccount.baseAddress());

        var transaction = quickTxBuilder.compose(tx)
                .withRequiredSigners(bobAccount.getBaseAddress())
                .withSigner(SignerProviders.signerFrom(adminAccount))
                .withSigner(SignerProviders.signerFrom(bobAccount))
//                    .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                .feePayer(adminAccount.baseAddress())
                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                .preBalanceTx((txBuilderContext, transaction1) -> {
                    var outputs = transaction1.getBody().getOutputs();
                    if (outputs.getFirst().getAddress().equals(adminAccount.baseAddress())) {
                        log.info("found dummy input, moving it...");
                        var first = outputs.removeFirst();
                        outputs.addLast(first);
                    }
                    try {
                        log.info("pre tx: {}", OBJECT_MAPPER.writeValueAsString(transaction1));
                    } catch (JsonProcessingException e) {
                        throw new RuntimeException(e);
                    }
                })
                .postBalanceTx((txBuilderContext, transaction1) -> {
                    try {
                        log.info("post tx: {}", OBJECT_MAPPER.writeValueAsString(transaction1));
                    } catch (JsonProcessingException e) {
                        throw new RuntimeException(e);
                    }
                })
                .buildAndSign();

        log.info("tx: {}", transaction.serializeToHex());
        log.info("tx: {}", OBJECT_MAPPER.writeValueAsString(transaction));

        if (!dryRun) {
            var txHash = bfBackendService.getTransactionService().submitTransaction(transaction.serialize());
            log.info("txHash: {}", txHash);
        }


    }


}
