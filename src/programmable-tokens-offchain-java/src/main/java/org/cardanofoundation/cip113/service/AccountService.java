package org.cardanofoundation.cip113.service;

import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.model.Utxo;
import com.easy1staking.util.Pair;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.math.BigInteger;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.function.Function;
import java.util.stream.Stream;

@Service
@Slf4j
@RequiredArgsConstructor
public class AccountService {

    private final UtxoProvider utxoProvider;

    public List<Utxo> findAdaOnlyUtxo(String address, Long minAdaBalance) {
        return this.findAdaOnlyUtxo(address, minAdaBalance, utxoProvider::findUtxos);
    }

    public List<Utxo> findAdaOnlyUtxoByPaymentPubKeyHash(String paymentPkh, Long minAdaBalance) {
        return this.findAdaOnlyUtxo(paymentPkh, minAdaBalance, utxoProvider::findUtxosByPaymentPkh);
    }

    public List<Utxo> findAdaOnlyUtxo(String address, Long minAdaBalance, Function<String, List<Utxo>> utxoFinder) {
        return utxoFinder.apply(address)
                .stream()
                .flatMap(utxo -> {
                    if (utxo.getAmount().size() == 1) {
                        return Stream.of(new Pair<>(utxo, utxo.getAmount().getFirst()));
                    } else {
                        return Stream.empty();
                    }
                })
                .sorted(Comparator.comparingLong(pair -> -1 * pair.second().getQuantity().longValue()))
                .reduce(new ArrayList<Utxo>(), (utxos, addressUtxoEntityAmtPair) -> {
                    var currentAmount = utxos.stream()
                            .flatMap(utxo -> utxo.getAmount().stream())
                            .map(Amount::getQuantity)
                            .reduce(BigInteger::add)
                            .orElse(BigInteger.ZERO);
                    if (currentAmount.longValue() < minAdaBalance) {
                        utxos.add(addressUtxoEntityAmtPair.first());
                    }

                    return utxos;
                }, (utxos, utxos2) -> {
                    utxos.addAll(utxos2);
                    return utxos;
                })
                .stream()
                .toList();
    }




}
