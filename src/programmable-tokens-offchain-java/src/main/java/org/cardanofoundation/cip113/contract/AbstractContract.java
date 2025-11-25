package org.cardanofoundation.cip113.contract;


import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.common.model.Network;
import com.bloxbean.cardano.client.common.model.Networks;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.PlutusScript;
import com.bloxbean.cardano.client.util.HexUtil;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
@Slf4j
public class AbstractContract {

    @Getter
    private byte[] scriptHashBytes;

    @Getter
    private String scriptHash;

    @Getter
    private PlutusScript plutusScript;

    public AbstractContract(String script, PlutusVersion version) {
        try {
            plutusScript = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(script, version);
            scriptHashBytes = plutusScript.getScriptHash();
            scriptHash = HexUtil.encodeHexString(plutusScript.getScriptHash());
            log.info("INIT - Contract: {}, hash: {}", this.getClass(), scriptHash);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    public String getAddress() {
        return getAddress(Networks.mainnet());
    }

    public String getAddress(Network network) {
        return AddressProvider.getEntAddress(plutusScript, network).getAddress();
    }

}
