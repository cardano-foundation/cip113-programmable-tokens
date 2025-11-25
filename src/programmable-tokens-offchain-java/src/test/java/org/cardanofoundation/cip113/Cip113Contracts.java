package org.cardanofoundation.cip113;

import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import lombok.Getter;
import org.cardanofoundation.cip113.contract.AbstractContract;

public class Cip113Contracts {

    // Contracts: https://github.com/easy1staking-com/wsc-poc/blob/main/src/examples/aiken/aiken/validators/transfer.ak
    // But rebuilt with Aiken 1.1.19

    private static final String ISSUE_CONTRACT = "585701010029800aba2aba1aab9eaab9dab9a4888896600264646644b30013370e900218031baa00289919b87375a6012008906400980418039baa0028a504014600c600e002600c004600c00260066ea801a29344d9590011";

    private static final String TRANSFER_CONTRACT = "585701010029800aba2aba1aab9eaab9dab9a4888896600264646644b30013370e900218031baa00289919b87375a6012008904801980418039baa0028a504014600c600e002600c004600c00260066ea801a29344d9590011";

    @Getter
    private final AbstractContract issueContract = new AbstractContract(ISSUE_CONTRACT, PlutusVersion.v3);

    @Getter
    private final AbstractContract transferContract = new AbstractContract(TRANSFER_CONTRACT, PlutusVersion.v3);



}
