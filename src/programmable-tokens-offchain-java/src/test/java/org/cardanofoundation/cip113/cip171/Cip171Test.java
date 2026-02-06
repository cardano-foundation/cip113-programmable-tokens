package org.cardanofoundation.cip113.cip171;

import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.exception.CborSerializationException;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.metadata.MetadataBuilder;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.BigIntPlutusData;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.PlutusScript;
import com.bloxbean.cardano.client.quicktx.Tx;
import com.bloxbean.cardano.client.util.HexUtil;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.AbstractPreviewTest;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

@Slf4j
public class Cip171Test extends AbstractPreviewTest {

    private final ProtocolBootstrapService protocolBootstrapService = new ProtocolBootstrapService(OBJECT_MAPPER, new AppConfig.Network("preview"));

    @Test
    public void test() throws CborSerializationException {

        protocolBootstrapService.init();
        var protocolBootstrapParams = protocolBootstrapService.getProtocolBootstrapParams();
        var protocolParams = protocolBootstrapParams.protocolParams();
        var ppTxInput = protocolParams.txInput();
        var ppParameters = ConstrPlutusData.of(0,
                BytesPlutusData.of(HexUtil.decodeHexString(ppTxInput.txHash())),
                BigIntPlutusData.of(ppTxInput.outputIndex()));
        log.info("ppParameters.serializeToHex(): {}", ppParameters.serializeToHex());

        var issuanceParams = protocolBootstrapParams.issuanceParams();
        var ipTxInput = issuanceParams.txInput();
        var ipParameters = ConstrPlutusData.of(0,
                BytesPlutusData.of(HexUtil.decodeHexString(ipTxInput.txHash())),
                BigIntPlutusData.of(ipTxInput.outputIndex()));
        log.info("ipParameters.serializeToHex(): {}", ipParameters.serializeToHex());

        var programmableLogicGlobalParams = protocolBootstrapParams.programmableLogicGlobalPrams();
        var plgParameters = BytesPlutusData.of(HexUtil.decodeHexString(programmableLogicGlobalParams.protocolParamsScriptHash()));
        log.info("plgParameters.serializeToHex(): {}", plgParameters.serializeToHex());
        log.info("programmableLogicGlobalParams.scriptHash(): {}", programmableLogicGlobalParams.scriptHash());

        var programmableLogicBaseParams = protocolBootstrapParams.programmableLogicBaseParams();
        var plbParameters = ConstrPlutusData.of(1,
                BytesPlutusData.of(HexUtil.decodeHexString(programmableLogicBaseParams.programmableLogicGlobalScriptHash()))
        );
        log.info("plbParameters.serializeToHex(): {}", plbParameters.serializeToHex());
        log.info("programmableLogicBaseParams.scriptHash(): {}", programmableLogicBaseParams.scriptHash());

        var directorySpendParams = protocolBootstrapParams.directorySpendParams();
        var dspParameters = BytesPlutusData.of(HexUtil.decodeHexString(programmableLogicGlobalParams.protocolParamsScriptHash()));
        log.info("dspParameters.serializeToHex(): {}", dspParameters.serializeToHex());
        log.info("directorySpendParams.scriptHash(): {}", directorySpendParams.scriptHash());

        var directoryMintParams = protocolBootstrapParams.directoryMintParams();
        var dsmTxInputParam = ConstrPlutusData.of(0,
                BytesPlutusData.of(HexUtil.decodeHexString(directoryMintParams.txInput().txHash())),
                BigIntPlutusData.of(directoryMintParams.txInput().outputIndex()));
        var dsmParameters = BytesPlutusData.of(HexUtil.decodeHexString(directoryMintParams.issuanceScriptHash()));
        log.info("dsmTxInputParam.serializeToHex(): {}", dsmTxInputParam.serializeToHex());
        log.info("dsmParameters.serializeToHex(): {}", dsmParameters.serializeToHex());
        log.info("directoryMintParams.scriptHash(): {}", directoryMintParams.scriptHash());


        var protocolParamsRawScriptHash = protocolBootstrapService.getProtocolContract("protocol_params_mint.protocol_params_mint.mint")
                .map(this::parseScript)
                .get();

        var issuanceCborHexMint = protocolBootstrapService.getProtocolContract("issuance_cbor_hex_mint.issuance_cbor_hex_mint.mint")
                .map(this::parseScript)
                .get();

        var programmableLogicGlobalWithdraw = protocolBootstrapService.getProtocolContract("programmable_logic_global.programmable_logic_global.withdraw")
                .map(this::parseScript)
                .get();

        var programmableLogicBaseSpend = protocolBootstrapService.getProtocolContract("programmable_logic_base.programmable_logic_base.spend")
                .map(this::parseScript)
                .get();

        var registrySpend = protocolBootstrapService.getProtocolContract("registry_spend.registry_spend.spend")
                .map(this::parseScript)
                .get();

        log.info("protocolParamsRawScriptHash: {}", protocolParamsRawScriptHash);
        Assertions.assertEquals("35af7fe099c1ec2ebe9a9ab9078b0516fcd19a430fc973774c586aaf", protocolParamsRawScriptHash.getPolicyId());
        Assertions.assertEquals("bee64a4bff628e9f2b12a3f9374b76e094084932f1243eff123d987b", issuanceCborHexMint.getPolicyId());
        Assertions.assertEquals("d4b5722a4900a53e359dfff23bc4017330dea0a475f58f4602aeebc2", programmableLogicGlobalWithdraw.getPolicyId());
        Assertions.assertEquals("02d99634f91ec58f17903d274b8a51e06212fa0862de5569ae4a38d4", programmableLogicBaseSpend.getPolicyId());
        Assertions.assertEquals("bcf996465f1cdccd7d94068eabc9a7c1213e7b471592fdf5d79b6ec8", registrySpend.getPolicyId());

        var list = UplcLinkRequest.builder()
                .compilerType(CompilerType.AIKEN)
                .sourceUrl("https://github.com/cardano-foundation/cip113-programmable-tokens")
                .commitHash("d219afd65aba0d2a3ce795eda140705c2ab263da")
                .sourcePath("src/programmable-tokens-onchain-aiken")
                .compilerVersion("v1.1.17")
                .parameters(Map.of(
                        // Protocol Params Init
                        protocolParamsRawScriptHash.getPolicyId(), List.of(ppParameters.serializeToHex()),
                        // Issuance
                        issuanceCborHexMint.getPolicyId(), List.of(ipParameters.serializeToHex()),
                        // Programmable Logic Global
                        programmableLogicGlobalWithdraw.getPolicyId(), List.of(plgParameters.serializeToHex()),
                        // Programmable Logic Base
                        programmableLogicBaseSpend.getPolicyId(), List.of(plbParameters.serializeToHex()),
                        // Registry Spend
                        registrySpend.getPolicyId(), List.of(dspParameters.serializeToHex())
                ))
                .build()
                .toMetadataChunkList();

        var metadata = MetadataBuilder.createMetadata().put(1984L, list);


        var tx = new Tx()
                .from(adminAccount.baseAddress())
                .payToAddress(adminAccount.baseAddress(), Amount.ada(1))
                .attachMetadata(metadata);

        quickTxBuilder.compose(tx)
                .feePayer(adminAccount.baseAddress())
                .withSigner(SignerProviders.signerFrom(adminAccount))
                .completeAndWait();

    }

    public PlutusScript parseScript(String scriptCborEncoded) {
        return this.parseScript(scriptCborEncoded, PlutusVersion.v3);
    }

    public PlutusScript parseScript(String scriptCborEncoded, PlutusVersion plutusVersion) {
        return PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
                scriptCborEncoded,
                plutusVersion
        );
    }

}
