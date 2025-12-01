package org.cardanofoundation.cip113;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.aiken.AikenTransactionEvaluator;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BigIntPlutusData;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;

import java.math.BigInteger;
import java.util.List;

import org.junit.jupiter.api.Disabled;

@Slf4j
@Disabled("Integration test - requires Blockfrost API key and Preview network access")
public class DirectoryMintTest extends AbstractPreviewTest {

    private static final String DIRECTORY_MINT_CONTRACT = "59084a0101002229800aba2aba1aba0aab9faab9eaab9dab9a9bae0024888888896600264653001300900198049805000cdc3a400130090024888966002600460126ea800e266446644b300130060018acc004c038dd5004400a2c807a2b300130030018991919912cc004c05800e00d16404c6eb8c04c004dd71809801180980098071baa0088b20184030264b30013300137586020601a6ea80108cdd7980898071baa0010158cc0048c044c0480066e9520009b804800a4602260246024003232330010010022259800800c52f5c113233223322330020020012259800800c400e264660306e9ccc060dd48029980c180a8009980c180b000a5eb80cc00c00cc068008c0600050161bab3013003375c602000266006006602a0046026002808a4464b30013008001899192cc004c05800a00916404c6eb8c050004c040dd5001c566002600a0031323259800980b00140122c8098dd7180a00098081baa0038b201c4038601c6ea800a6e1d2004918089809180918091809000a4444444530012232330010010032259800800c5300103d87a8000899192cc004cdc8802800c56600266e3c0140062601a6603a603600497ae08a60103d87a80004065133004004301f00340646eb8c064004c07000501a489660020031480022601066004004603600280c244b30010018a40011300833002002301b0014061232598009802180b1baa0018980d180b9baa0018b202a30063016375400322598009807980b1baa002899191919194c004dd7180f800cdd7180f802cdd7180f8024c07c0092222598009812002c4cc038c08c01c4cc03800402a2c8108603e002603c002603a0026038002602e6ea800a2c80a922222980091192cc004c048c070dd5000c52f5bded8c1137566040603a6ea800501b19803801000cc010012600600722232598009809980e9baa0018a40011375a6042603c6ea800501c192cc004c04cc074dd5000c530103d87a8000899198008009bab3022301f375400444b30010018a6103d87a8000899192cc004cdc8803000c56600266e3c0180062602866048604400497ae08a60103d87a80004081133004004302600340806eb8c080004c08c00502120383300800300248888c8ca60026eb0c08c0066eb0c08cc0900064464b30013010300730120018992cc004c064c018006264660180022b3001337206eb8c0a0c094dd50009bae301830253754003159800981480144c8c96600260386eb4c09c00a2b30015980099b8f00133714911010100375c6054604e6ea800e2946266e3c0052201010000409510038b204a8b204a375c604a002605000516409916408c6018009164088660120020051640846eacc054c088dd50012444b3001301b3022375403b159800981380144c966002b30010048a518a50409515980099b8f375c604e60486ea80052201008acc004cdc79bae3017302437540029101008980ccc004dd5980818121baa01b80d52201010000401d14a081122941022452820443300130260020198b204889919912cc004c078c094dd5000c4c966002603e604c6ea8006264646644b3001302f0038992cc004c0c003226466028002264b30010038acc004cdc39b8d00a480e22b3001337206eb8c0c4c0b8dd5001005456600266e40028dd7181098171baa0028acc004c96600260493001001812ccdc524501010000b4049130243011330150010258a5040b46eacc068c0b8dd5012c5660026036646600200200444b30010018a40011302133002002303400140c51598009981100092cc004cdc79bae3032302f37540026eb8c0c8c0bcdd5001c4cdc79bae3022302f375400201714a0816a266044002464b30013371e6eb8c0ccc0c0dd5001006456600266e3cdd7181198181baa002375c604660606ea80122b30013375e604060606ea8008c080c0c0dd5002456600266ebcc004c0c0dd5001180098181baa004899b8f375c603860606ea8008dd7180e18181baa0048a5040b914a08172294102e4528205c230333034303430340018a5040b114a08162294102c452820588a5040b114a08162294102c1919800800806912cc004006297ae0899818998069819000812998010011819800a0603014301f302c3754605e0191640b4b30013233001001301b3756603060586ea808c896600200314a1159800992cc004cdc79bae303100100a899b8848000dd6981898191819000c52820583758606000314a3133002002303100140ac8172266e3cde419b8a489010300337146eb8c0b8c0acdd500299b8a375c605c605e0106eb8c078c0acdd5002803c52820528b2058375c60580026eb8c0b0008c0b0004c09cdd5000c590251807180c98131baa3029302637540031640906eb8c09c004c8cc004004dd6180c18129baa01c2259800800c530103d87a80008992cc0066002b30013300d37566034604e6ea8c068c09cdd50008124528c5282050a50a51409513019330290014bd7044cc00c00cc0ac0090251814800a04e3023375403a810866446644b3001002899812a60101800033025374e00297ae08992cc004c8cc00400400c896600200314a315980099baf3029302637546052002007133002002302a0018a504090813a26604c6e9c00ccc098dd380125eb822c8110c098c08cdd5180b18119baa30260024090660046eb0c090c084dd500c1198011bab301530223754602a60446ea8004060cc008dd6180898109baa0182330023756602a60446ea800406088c8cc00400400c896600200314bd7044cc8966002600a00513302700233004004001899802002000a0463026001302700140904466e21200030033300700200123004001116402c44646600200200644b30010018a508acc004c00cc04c00629462660040046028002807101118059baa006375c601a60146ea800cdc3a4005164020300900130043754013149a26cac80101";

    private final Cip113Contracts cip113Contracts = new Cip113Contracts();

    @Test
    public void initDirectory() throws Exception {

        var utxosOpt = bfBackendService.getUtxoService().getUtxos(adminAccount.baseAddress(), 100, 1);
        if (!utxosOpt.isSuccessful() || utxosOpt.getValue().isEmpty()) {
            Assertions.fail("no utxos available");
        }
        var walletUtxos = utxosOpt.getValue();

        var walletUtxo = walletUtxos.getFirst();

        var outputRef = ConstrPlutusData.of(0,
                BytesPlutusData.of(HexUtil.decodeHexString(walletUtxo.getTxHash())),
                BigIntPlutusData.of(walletUtxo.getOutputIndex()));

        var params = ListPlutusData.of(outputRef);

        String applyParamCompiledCode = AikenScriptUtil.applyParamToScript(params, DIRECTORY_MINT_CONTRACT);

        var parameterisedDirectoryMintScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(applyParamCompiledCode, PlutusVersion.v3);

        walletUtxos.forEach(utxo -> log.info("wallet utxo: {}", utxo));

        var protocolParamNft = Asset.builder()
                .name(HexUtil.encodeHexString(new byte[]{0, 0}, true))
                .value(BigInteger.ONE)
                .build();

        // Unnecessary but for simplicity paying into the nft address matching policy id
        var nftAddress = AddressProvider.getEntAddress(Credential.fromScript(parameterisedDirectoryMintScript.getScriptHash()), network);
        log.info("nftAddress: {}", nftAddress.getAddress());

        var protocolParamsDatum = ConstrPlutusData.of(0,
                // Registry node datum structure:
                // key: empty for initial node
                // next: empty for initial node (end of list)
                // transfer_logic_script: using test transfer contract hash
                // issuer_logic_script: using test issue contract hash
                // global_state_cs: empty for initial setup
                BytesPlutusData.of(""),
                BytesPlutusData.of(""),
                BytesPlutusData.of(cip113Contracts.getTransferContract().getScriptHashBytes()),
                BytesPlutusData.of(cip113Contracts.getIssueContract().getScriptHashBytes()),
                BytesPlutusData.of("")
        );

        Value protocolParamsValue = Value.builder()
                .coin(Amount.ada(1).getQuantity())
                .multiAssets(List.of(
                        MultiAsset.builder()
                                .policyId(parameterisedDirectoryMintScript.getPolicyId())
                                .assets(List.of(protocolParamNft))
                                .build()
                ))
                .build();

        var tx = new ScriptTx()
                //spend all wallets (coz we need to burn the bootstrap utxo)
                .collectFrom(walletUtxos)
                .mintAsset(parameterisedDirectoryMintScript, protocolParamNft, ConstrPlutusData.of(0))
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
