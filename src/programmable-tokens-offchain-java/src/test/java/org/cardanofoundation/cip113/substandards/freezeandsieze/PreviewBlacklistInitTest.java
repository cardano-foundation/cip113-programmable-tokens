package org.cardanofoundation.cip113.substandards.freezeandsieze;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.aiken.AikenTransactionEvaluator;
import com.bloxbean.cardano.client.address.AddressProvider;
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
import com.bloxbean.cardano.client.plutus.spec.PlutusData;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import lombok.Getter;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.AbstractPreviewTest;
import org.cardanofoundation.cip113.model.bootstrap.TxInput;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistBootstrap;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistMintBootstrap;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistNode;
import org.cardanofoundation.cip113.model.onchain.siezeandfreeze.blacklist.BlacklistSpendBootstrap;
import org.cardanofoundation.cip113.service.AccountService;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.cardanofoundation.cip113.service.UtxoService;
import org.cardanofoundation.cip113.util.PlutusSerializationHelper;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.util.List;
import java.util.Map;

import static java.math.BigInteger.ONE;
import static java.math.BigInteger.ZERO;

@Slf4j
public class PreviewBlacklistInitTest extends AbstractPreviewTest {

    private final Network network = Networks.preview();

    private final UtxoService utxoService = new UtxoService(bfBackendService, null);

    private final AccountService accountService = new AccountService(utxoService);

    private SubstandardService substandardService;

    @BeforeEach
    public void init() {
        substandardService = new SubstandardService(OBJECT_MAPPER);
        substandardService.init();
    }

    @Test
    public void test() throws Exception {

        var substandardName = "freeze-and-seize";

        var adminUtxos = accountService.findAdaOnlyUtxo(adminAccount.baseAddress(), 10_000_000L);
        log.info("admin utxos size: {}", adminUtxos.size());
        var adminAdaBalance = adminUtxos.stream()
                .flatMap(utxo -> utxo.getAmount().stream())
                .map(Amount::getQuantity)
                .reduce(BigInteger::add)
                .orElse(ZERO);
        log.info("admin ada balance: {}", adminAdaBalance);
        var bootstrapUtxo = adminUtxos.getFirst();
        log.info("bootstrapUtxo: {}", bootstrapUtxo);

        var bootstrapUtxoOpt = utxoService.findUtxo(bootstrapUtxo.getTxHash(), bootstrapUtxo.getOutputIndex());

        if (bootstrapUtxoOpt.isEmpty()) {
            Assertions.fail("no utxo found");
        }

        var blackListMintValidatorOpt = substandardService.getSubstandardValidator(substandardName, "blacklist_mint.blacklist_mint.mint");
        var blackListMintValidator = blackListMintValidatorOpt.get();

        var serialisedTxInput = PlutusSerializationHelper.serialize(TransactionInput.builder()
                .transactionId(bootstrapUtxo.getTxHash())
                .index(bootstrapUtxo.getOutputIndex())
                .build());

        var adminPkhBytes = adminAccount.getBaseAddress().getPaymentCredentialHash().get();
        var adminPks = HexUtil.encodeHexString(adminPkhBytes);
        var blacklistMintInitParams = ListPlutusData.of(serialisedTxInput,
                BytesPlutusData.of(adminPkhBytes)
        );

        var parameterisedBlacklistMintingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                AikenScriptUtil.applyParamToScript(blacklistMintInitParams, blackListMintValidator.scriptBytes()),
                PlutusVersion.v3
        );

        var blacklistSpendValidatorOpt = substandardService.getSubstandardValidator(substandardName, "blacklist_spend.blacklist_spend.spend");
        var blacklistSpendValidator = blacklistSpendValidatorOpt.get();

        var blacklistSpendInitParams = ListPlutusData.of(BytesPlutusData.of(HexUtil.decodeHexString(parameterisedBlacklistMintingScript.getPolicyId())));
        var parameterisedBlacklistSpendingScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                AikenScriptUtil.applyParamToScript(blacklistSpendInitParams, blacklistSpendValidator.scriptBytes()),
                PlutusVersion.v3
        );
        var blacklistSpendAddress = AddressProvider.getEntAddress(parameterisedBlacklistSpendingScript, network);

        var blacklistInitDatum = BlacklistNode.builder()
                .key("")
                .next("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
                .build();

        var blacklistAsset = Asset.builder().name("0x").value(ONE).build();

        var blacklistNft = Asset.builder()
                .name("0x")
                .value(BigInteger.ONE)
                .build();

        Value blacklistValue = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(parameterisedBlacklistMintingScript.getPolicyId())
                                .assets(List.of(blacklistNft))
                                .build()
                ))
                .build();

        var tx = new ScriptTx()
                .collectFrom(adminUtxos)
                .mintAsset(parameterisedBlacklistMintingScript, blacklistAsset, ConstrPlutusData.of(0))
                .payToContract(blacklistSpendAddress.getAddress(), ValueUtil.toAmountList(blacklistValue), blacklistInitDatum.toPlutusData())
                .withChangeAddress(adminAccount.baseAddress());


        var transaction = quickTxBuilder.compose(tx)
                .feePayer(adminAccount.baseAddress())
                .withSigner(SignerProviders.signerFrom(adminAccount))
                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                .mergeOutputs(false)
                .buildAndSign();

        log.info("transaction: {}", transaction.serializeToHex());
        log.info("transaction: {}", OBJECT_MAPPER.writeValueAsString(transaction));

        bfBackendService.getTransactionService().submitTransaction(transaction.serialize());

        var mintBootstrap = new BlacklistMintBootstrap(TxInput.from(bootstrapUtxo), adminPks, parameterisedBlacklistMintingScript.getPolicyId());
        var spendBootstrap = new BlacklistSpendBootstrap(parameterisedBlacklistMintingScript.getPolicyId(), parameterisedBlacklistSpendingScript.getPolicyId());
        var bootstrap = new BlacklistBootstrap(mintBootstrap, spendBootstrap);

        log.info("bootstrap: {}", OBJECT_MAPPER.writeValueAsString(bootstrap));
//{"blacklistMintBootstrap":{"txInput":{"txHash":"7172a517d98d65dc9fdaf270cb52383de54840fbf44721d8ae82ae8d8175a1a5","outputIndex":1},"adminPubKeyHash":"32e7e00eae28502a2aa271cf4202b1b01b94ca8efe642e380c93d5e2","scriptHash":"30a8c9cc2fd9e9424dc4732f2ccdcf5bee863e5b77817090a1acefbb"},"blacklistSpendBootstrap":{"blacklistMintScriptHash":"30a8c9cc2fd9e9424dc4732f2ccdcf5bee863e5b77817090a1acefbb","scriptHash":"97c007326cf3839c4820da1d8fa3c097abeab42d1f5f18044c0188d8"}}
    }

    @Getter
    enum ComplierType {
        AIKEN(0), HELIOS(1), SCALUS(2), OPSHIN(3);
        private final int compileId;

        ComplierType(int compileId) {
            this.compileId = compileId;
        }
    }

    record PlutusScanRequest(ComplierType complierType,
            String org,
            String repo,
            String commitHash,
            String optionalPath,
            String compilerVersion,
            Map<String, List<String>> parameters) {

        public PlutusData toPlutusData() {
            return ConstrPlutusData.of(complierType.getCompileId(),
                    BytesPlutusData.of(HexUtil.encodeHexString("cardano-foundation".getBytes())),
                    BytesPlutusData.of(HexUtil.encodeHexString("cip113-programmable-tokens".getBytes())),
                    BytesPlutusData.of(HexUtil.encodeHexString("".getBytes())),
                    );
        }

    }


    public void testSubmitPlutusScanTx() {


    }


}
