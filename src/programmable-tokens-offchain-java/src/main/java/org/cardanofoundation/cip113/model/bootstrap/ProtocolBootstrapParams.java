package org.cardanofoundation.cip113.model.bootstrap;

public record ProtocolBootstrapParams(ProtocolParams protocolParams,
                                      ProgrammableLogicGlobalParams programmableLogicGlobalPrams,
                                      ProgrammableLogicBaseParams programmableLogicBaseParams,
                                      IssuanceParams issuanceParams,
                                      DirectoryMintParams directoryMintParams,
                                      DirectorySpendParams directorySpendParams,
                                      TxInput programmableBaseRefInput,
                                      TxInput programmableGlobalRefInput,
                                      TxInput protocolParamsUtxo,
                                      TxInput directoryUtxo,
                                      TxInput issuanceUtxo,
                                      String txHash) {

}
