package org.cardanofoundation.cip113.contract;


import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Component
@Slf4j
public class ProgrammableLogicBaseContract extends AbstractContract {

    private static final String CONTRACT = "58ac010100229800aba2aba1aab9faab9eaab9dab9a48888896600264646644b30013370e900118031baa0018994c004c028006601460160033756601460166016601660166016601660106ea8c0280152225980099baf300a300d0010108a51899198008009807801112cc00400629422b30013375e6018601e00202514a31330020023010001402c80710090c01cdd5000c59005180380098039804000980380098019baa0078a4d1365640041";

    public ProgrammableLogicBaseContract() {
        this(CONTRACT, PlutusVersion.v3);
    }

    private ProgrammableLogicBaseContract(String script, PlutusVersion version) {
        super(script, version);
    }

}
