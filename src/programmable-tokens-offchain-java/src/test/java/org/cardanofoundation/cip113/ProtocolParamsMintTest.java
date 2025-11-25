package org.cardanofoundation.cip113;

import com.bloxbean.cardano.aiken.AikenTransactionEvaluator;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.contract.AbstractContract;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.util.List;

@Slf4j
public class ProtocolParamsMintTest extends AbstractPreviewTest {

    private static final String PROTOCOL_PARAMS_CONTRACT = "5904f20101003229800aba4aba2aba1aba0aab9faab9eaab9dab9cab9a4888888888c96600264653001300a00198051805800cdc3a4001300a0024888966002600460146ea800e33001375c601c60166ea800e64660020026eb0c03cc030dd5001112cc00400629422b30013375e6020601a6ea8c04000405229462660040046022002805100e4dc3a4005374a900048c03cc040c0400052222232332259800980518091baa0018992cc004cdc3a400860266ea8006264b30010018992cc004c034c054dd500144c9660020030138992cc00400602901480a405226644b300100180b44c966002003159800980f80144c966002602600313259800800c066264b300100180d406a03501a8992cc004c08c00e01501b40806eb80050231810000a03c301c37540051598009807800c4c9660020030198992cc00400603501a80d406a264b30013023003805406d0201bae001408c604000280f0c070dd500140610192032301a3754003017407101780bc05e02e8100c07400501b1bae001301c0024074603400280c0c058dd500140490130acc0056600201314a3153301349113696e7075745f7370656e74203f2046616c73650014a080922b300130080048a518a99809a4811a616d6f756e745f6d696e746564203d3d2031203f2046616c73650014a0809229410124046023011808a034301730143754003153301249012865787065637420496e6c696e65446174756d28646174756d29203d206f75747075742e646174756d00164044600860266ea8c058c04cdd5000c54cc0452401b565787065637420536f6d65286f757470757429203d0a2020202020206c6973742e66696e64280a202020202020202073656c662e6f7574707574732c0a2020202020202020666e286f757470757429207b0a202020202020202020206173736574732e7175616e746974795f6f66286f75747075742e76616c75652c20706f6c6963795f69642c2070726f746f636f6c5f706172616d735f746f6b656e29203e20300a20202020202020207d2c0a2020202020202900164041300137566028602a602a602a602a60226ea801e00d48810e50726f746f636f6c506172616d7300400464660020026eb0c00cc048dd5004112cc0040062980103d87a80008992cc004cdc42400130013756602e603060286ea800601348810e50726f746f636f6c506172616d7300401113006330160014bd7044cc00c00cc060009011180b000a0282223259800980398099baa0018a40011375a602e60286ea8005011192cc004c01cc04cdd5000c530103d87a8000899198008009bab30183015375400444b30010018a6103d87a8000899192cc004cdc8803000c56600266e3c0180062601466034603000497ae08a60103d87a80004055133004004301c00340546eb8c058004c064005017202232330010010042259800800c5300103d87a8000899192cc004cdc8803000c56600266e3c0180062601266032602e00497ae08a60103d87a80004051133004004301b00340506eb8c054004c06000501622c80406014002600a6ea802e293454cc00d2411856616c696461746f722072657475726e65642066616c7365001365640082a66004920135657870656374205f706172616d733a2050726f6772616d6d61626c654c6f676963476c6f62616c506172616d73203d20646174756d0016260127d8799f58202ad9a8a937482bd7243aa5b806335add3fc4731ced9a6cb12d2509667ab1160e00ff0001";

    private final AbstractContract protocolParamsContract = new AbstractContract(PROTOCOL_PARAMS_CONTRACT, PlutusVersion.v3);

    @Test
    public void test() throws Exception {
        var slot = bfBackendService.getBlockService().getLatestBlock().getValue().getSlot();
        log.info("slot: {}", slot);

        var utxosOpt = bfBackendService.getUtxoService().getUtxos(adminAccount.baseAddress(), 100, 1);
        if (!utxosOpt.isSuccessful()) {
            Assertions.fail("no utxos available");
        }
        var walletUtxos = utxosOpt.getValue();

        walletUtxos.forEach(utxo -> log.info("wallet utxo: {}", utxo));

        var protocolParamNft = Asset.builder()
                .name(HexUtil.encodeHexString("ProtocolParams".getBytes(), true))
                .value(BigInteger.ONE)
                .build();

        // Unnecessary but for simplicity paying into the nft address matching policy id
        var nftAddress = AddressProvider.getEntAddress(Credential.fromScript(protocolParamsContract.getScriptHash()), network);
        log.info("nftAddress: {}", nftAddress.getAddress());

        var protocolParamsDatum = ConstrPlutusData.of(0,
                // FIXME: these are NOT the correct one, just testing if it passes validation
                BytesPlutusData.of(protocolParamsContract.getScriptHashBytes()), // policy id of the nft of the directory (programmable token registry)
                ConstrPlutusData.of(0,
                        BytesPlutusData.of(adminAccount.getBaseAddress().getPaymentCredentialHash().get()) // script hash of the substandard?
                )
        );

        Value protocolParamsValue = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(protocolParamsContract.getScriptHash())
                                .assets(List.of(protocolParamNft))
                                .build()
                ))
                .build();

        var tx = new ScriptTx()
                //spend all wallets (coz we need to burn the bootstrap utxo)
                .collectFrom(walletUtxos)
                .mintAsset(protocolParamsContract.getPlutusScript(), protocolParamNft, ConstrPlutusData.of(0))
                .payToContract(nftAddress.getAddress(), ValueUtil.toAmountList(protocolParamsValue), protocolParamsDatum)
                .withChangeAddress(adminAccount.baseAddress());

        var transaction = quickTxBuilder.compose(tx)
                .withSigner(SignerProviders.signerFrom(adminAccount))
                .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                .feePayer(adminAccount.baseAddress())
                .build();

        log.info("tx: {}", transaction.serializeToHex());
        log.info("tx: {}", OBJECT_MAPPER.writeValueAsString(transaction));


    }


}
