package org.cardanofoundation.cip113.config;

import com.bloxbean.cardano.aiken.AikenTransactionEvaluator;
import com.bloxbean.cardano.client.api.ProtocolParamsSupplier;
import com.bloxbean.cardano.client.api.TransactionEvaluator;
import com.bloxbean.cardano.client.api.TransactionProcessor;
import com.bloxbean.cardano.client.api.exception.ApiException;
import com.bloxbean.cardano.client.api.model.EvaluationResult;
import com.bloxbean.cardano.client.api.model.Result;
import com.bloxbean.cardano.client.api.model.Utxo;
import com.bloxbean.cardano.client.backend.api.DefaultProtocolParamsSupplier;
import com.bloxbean.cardano.client.backend.api.DefaultScriptSupplier;
import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.service.HybridUtxoSupplier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;
import java.util.Set;

@Configuration
@Slf4j
public class YaciConfiguration {


    @Bean
    public HybridUtxoSupplier hybridUtxoSupplier(BFBackendService bfBackendService) {
        return new HybridUtxoSupplier(bfBackendService.getUtxoService());
    }

    @Bean
    public ProtocolParamsSupplier protocolParamsSupplier(BFBackendService bfBackendService) {
        return new DefaultProtocolParamsSupplier(bfBackendService.getEpochService());
    }

    //    @Bean
//    public TransactionEvaluator scalusTransactionEvaluator(HybridUtxoSupplier hybridUtxoSupplier,
//                                                     ProtocolParamsSupplier protocolParamsSupplier,
//                                                     BFBackendService bfBackendService) {
//
//        var scriptSupplier = new ScriptSupplier() {
//            @Override
//            public PlutusScript getScript(String scriptHash) {
//                if (scriptHash != null) {
//                    try {
//                        var result = bfBackendService.getScriptService().getPlutusScript(scriptHash);
//                        if (result.isSuccessful()) {
//                            return result.getValue();
//                        } else {
//                            log.warn("could not find script for {}", scriptHash);
//                            return null;
//                        }
//                    } catch (ApiException e) {
//                        log.warn("could not find script for {}", scriptHash);
//                        return null;
//                    }
//                } else {
//                    return null;
//                }
//            }
//        };
//
//        return new ScalusTransactionEvaluator(protocolParamsSupplier.getProtocolParams(),
//                hybridUtxoSupplier,
//                scriptSupplier);
//
//    }
    @Bean
    public TransactionEvaluator aikenTransactionEvaluator(HybridUtxoSupplier hybridUtxoSupplier,
                                                          ProtocolParamsSupplier protocolParamsSupplier,
                                                          BFBackendService bfBackendService) {

        var scriptSupplier = new DefaultScriptSupplier(bfBackendService.getScriptService());

        return new AikenTransactionEvaluator(hybridUtxoSupplier, protocolParamsSupplier, scriptSupplier);

    }

    @Bean
    public QuickTxBuilder quickTxBuilder(HybridUtxoSupplier hybridUtxoSupplier,
                                         ProtocolParamsSupplier protocolParamsSupplier,
                                         TransactionEvaluator transactionEvaluator,
                                         BFBackendService bfBackendService) {


        var transactionProcessor = new TransactionProcessor() {
            @Override
            public Result<String> submitTransaction(byte[] cborData) throws ApiException {
                return null;
            }

            @Override
            public Result<List<EvaluationResult>> evaluateTx(byte[] cbor, Set<Utxo> inputUtxos) throws ApiException {
                return transactionEvaluator.evaluateTx(cbor, inputUtxos);
            }
        };
        var scriptSupplier = new DefaultScriptSupplier(bfBackendService.getScriptService());

        return new QuickTxBuilder(hybridUtxoSupplier,
                protocolParamsSupplier,
                scriptSupplier,
                transactionProcessor);

    }


}
