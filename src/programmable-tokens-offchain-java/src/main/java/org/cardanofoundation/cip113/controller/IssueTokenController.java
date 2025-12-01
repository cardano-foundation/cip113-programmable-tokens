package org.cardanofoundation.cip113.controller;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.address.Credential;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.util.ValueUtil;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.spec.*;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.bloxbean.cardano.client.quicktx.ScriptTx;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.MultiAsset;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.transaction.spec.Value;
import com.bloxbean.cardano.client.util.HexUtil;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.model.UtxoId;
import com.bloxbean.cardano.yaci.store.utxo.storage.impl.repository.UtxoRepository;
import com.easy1staking.cardano.util.UtxoUtil;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.cardanofoundation.cip113.config.AppConfig;
import org.cardanofoundation.cip113.model.DirectorySetNode;
import org.cardanofoundation.cip113.model.IssueTokenRequest;
import org.cardanofoundation.cip113.model.MintTokenRequest;
import org.cardanofoundation.cip113.model.RegisterTokenRequest;
import org.cardanofoundation.cip113.service.ProtocolBootstrapService;
import org.cardanofoundation.cip113.service.SubstandardService;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import jakarta.validation.Valid;
import org.cardanofoundation.cip113.exception.ApiException;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigInteger;
import java.util.List;
import java.util.Optional;

@RestController
@RequestMapping("${apiPrefix}/issue-token")
@RequiredArgsConstructor
@Slf4j
public class IssueTokenController {

    private final ObjectMapper objectMapper;

    private final AppConfig.Network network;

    private final UtxoRepository utxoRepository;

    private final ProtocolBootstrapService protocolBootstrapService;

    private final SubstandardService substandardService;

    private final QuickTxBuilder quickTxBuilder;

    @PostMapping("/register")
    public ResponseEntity<?> register(@Valid @RequestBody RegisterTokenRequest registerTokenRequest) {

        try {

            var protocolBootstrapParams = protocolBootstrapService.getProtocolBootstrapParams();

            var protocolParamsUtxoRef = protocolBootstrapParams.protocolParamsUtxo();
            var protocolParamsUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(protocolParamsUtxoRef.txHash())
                    .outputIndex(protocolParamsUtxoRef.outputIndex())
                    .build());
            if (protocolParamsUtxoOpt.isEmpty()) {
                throw ApiException.internalError("Could not resolve protocol params UTxO");
            }

            var protocolParamsUtxo = protocolParamsUtxoOpt.get();
            log.info("protocolParamsUtxo: {}", protocolParamsUtxo);

            var issuanceUtxoRef = protocolBootstrapParams.issuanceUtxo();
            var issuanceUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(issuanceUtxoRef.txHash())
                    .outputIndex(issuanceUtxoRef.outputIndex())
                    .build());
            if (issuanceUtxoOpt.isEmpty()) {
                throw ApiException.internalError("Could not resolve issuance UTxO");
            }
            var issuanceUtxo = issuanceUtxoOpt.get();
            log.info("issuanceUtxo: {}", issuanceUtxo);

            var issuanceDatum = issuanceUtxo.getInlineDatum();
            var issuanceData = PlutusData.deserialize(HexUtil.decodeHexString(issuanceDatum));
            var issuance = objectMapper.writeValueAsString(issuanceData);
            log.info("issuance: {}", issuance);

            var programmableLogicBaseScriptHash = protocolBootstrapParams.programmableLogicBaseParams().scriptHash();

            var issuerUtxosOpt = utxoRepository.findUnspentByOwnerAddr(registerTokenRequest.issuerBaseAddress(), Pageable.unpaged());
            if (issuerUtxosOpt.isEmpty()) {
                throw ApiException.badRequest("Issuer wallet is empty");
            }
            var issuerUtxos = issuerUtxosOpt.get().stream().map(UtxoUtil::toUtxo).toList();

            var directoryUtxoRef = protocolBootstrapParams.directoryUtxo();
            var directoryUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(directoryUtxoRef.txHash())
                    .outputIndex(directoryUtxoRef.outputIndex())
                    .build());
            if (directoryUtxoOpt.isEmpty()) {
                throw ApiException.internalError("Could not resolve directory UTxO");
            }

            var directoryUtxo = UtxoUtil.toUtxo(directoryUtxoOpt.get());
            log.info("directoryUtxo: {}", directoryUtxo);

            var directorySetNode = DirectorySetNode.fromInlineDatum(directoryUtxo.getInlineDatum());
            if (directorySetNode.isEmpty()) {
                log.error("could not deserialise directorySetNode for utxo: {}", directoryUtxo);
                throw ApiException.internalError("Could not deserialize directory set node");
            }
            log.info("directorySetNode: {}", directorySetNode);

            var substandardIssuanceContractOpt = substandardService.getSubstandardValidator(registerTokenRequest.substandardName(), registerTokenRequest.substandardIssueContractName());
            var substandardTransferContractOpt = substandardService.getSubstandardValidator(registerTokenRequest.substandardName(), registerTokenRequest.substandardTransferContractName());

            if (substandardIssuanceContractOpt.isEmpty() || substandardTransferContractOpt.isEmpty()) {
                log.warn("substandard issuance or transfer contract are empty");
                throw ApiException.badRequest("Substandard issuance or transfer contract not found");
            }

            var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardIssuanceContractOpt.get().scriptBytes(), PlutusVersion.v3);
            log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

            var substandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardTransferContractOpt.get().scriptBytes(), PlutusVersion.v3);

            // Issuance Parameterization
            var issuanceParameters = ListPlutusData.of(
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(HexUtil.decodeHexString(programmableLogicBaseScriptHash))
                    ),
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(substandardIssueContract.getScriptHash())
                    )
            );

            var issuanceMintOpt = protocolBootstrapService.getProtocolContract("issuance_mint.issuance_mint.mint");
            if (issuanceMintOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not find issuance mint contract");
            }

            var issuanceContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(issuanceParameters, issuanceMintOpt.get()), PlutusVersion.v3);
            log.info("issuanceContract: {}", issuanceContract.getPolicyId());

            var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));
//        var issuanceRedeemer = ConstrPlutusData.of(0, BytesPlutusData.of(substandardIssueContract.getScriptHash()));


            var directoryMintOpt = protocolBootstrapService.getProtocolContract("registry_mint.registry_mint.mint");
            if (directoryMintOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not find directory mint contract");
            }

            // Directory MINT parameterization
            log.info("protocolBootstrapParams.directoryMintParams(): {}", protocolBootstrapParams.directoryMintParams());
            var directoryMintParameters = ListPlutusData.of(
                    ConstrPlutusData.of(0,
                            BytesPlutusData.of(HexUtil.decodeHexString(protocolBootstrapParams.directoryMintParams().txInput().txHash())),
                            BigIntPlutusData.of(protocolBootstrapParams.directoryMintParams().txInput().outputIndex())),
                    BytesPlutusData.of(HexUtil.decodeHexString(protocolBootstrapParams.directoryMintParams().issuanceScriptHash()))
            );
            var directoryMintContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(directoryMintParameters, directoryMintOpt.get()), PlutusVersion.v3);
            log.info("directoryMintContract: {}", directoryMintContract.getPolicyId());

            //        PROGRAMMABLE_LOGIC_BASE_CONTRACT = getCompiledCodeFor("programmable_logic_base.programmable_logic_base.spend", validators);

            var directorySpentOpt = protocolBootstrapService.getProtocolContract("registry_spend.registry_spend.spend");
            if (directorySpentOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not find directory spend contract");
            }

            // Directory SPEND parameterization
            var directorySpendParameters = ListPlutusData.of(
                    BytesPlutusData.of(HexUtil.decodeHexString(protocolBootstrapParams.protocolParams().scriptHash()))
            );
            var directorySpendContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(directorySpendParameters, directorySpentOpt.get()), PlutusVersion.v3);
            log.info("directorySpendContract, policy: {}", directorySpendContract.getPolicyId());
            log.info("directorySpendContract, script hash: {}", HexUtil.encodeHexString(directorySpendContract.getScriptHash()));
            var directorySpendContractAddress = AddressProvider.getEntAddress(Credential.fromScript(directorySpendContract.getScriptHash()), network.getCardanoNetwork());
            log.info("directorySpendContractAddress: {}", directorySpendContractAddress.getAddress());


            // Directory MINT - NFT, address, datum and value
            var directoryMintRedeemer = ConstrPlutusData.of(1,
                    BytesPlutusData.of(issuanceContract.getScriptHash()),
                    BytesPlutusData.of(substandardIssueContract.getScriptHash())
            );

            var directoryMintNft = Asset.builder()
                    .name("0x" + issuanceContract.getPolicyId())
//                .name("0x01" + HexUtil.encodeHexString(issuanceContract.getScriptHash()))
                    .value(BigInteger.ONE)
                    .build();

            var directorySpendNft = Asset.builder()
                    .name("0x")
                    .value(BigInteger.ONE)
                    .build();

            var directorySpendDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(""),
                    BytesPlutusData.of(issuanceContract.getScriptHash()),
                    ConstrPlutusData.of(0, BytesPlutusData.of("")),
                    ConstrPlutusData.of(0, BytesPlutusData.of("")),
                    BytesPlutusData.of(""));

            var directoryMintDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(issuanceContract.getScriptHash()),
                    BytesPlutusData.of(HexUtil.decodeHexString("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")),
                    ConstrPlutusData.of(1, BytesPlutusData.of(substandardTransferContract.getScriptHash())),
                    ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())),
                    BytesPlutusData.of(""));

            Value directoryMintValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(
                            MultiAsset.builder()
                                    .policyId(directoryMintContract.getPolicyId())
                                    .assets(List.of(directoryMintNft))
                                    .build()
                    ))
                    .build();

            Value directorySpendValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(
                            MultiAsset.builder()
                                    .policyId(directoryMintContract.getPolicyId())
                                    .assets(List.of(directorySpendNft))
                                    .build()
                    ))
                    .build();


            var tx = new ScriptTx()
                    .collectFrom(issuerUtxos)
                    .collectFrom(directoryUtxo, ConstrPlutusData.of(0))
                    .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, BigIntPlutusData.of(100))
                    // Redeemer is DirectoryInit (constr(0))
                    .mintAsset(directoryMintContract, directoryMintNft, directoryMintRedeemer)
                    // Directory Params
                    .payToContract(directorySpendContractAddress.getAddress(), ValueUtil.toAmountList(directorySpendValue), directorySpendDatum)
                    // Directory Params
                    .payToContract(directorySpendContractAddress.getAddress(), ValueUtil.toAmountList(directoryMintValue), directoryMintDatum)
                    .readFrom(TransactionInput.builder()
                                    .transactionId(protocolParamsUtxo.getTxHash())
                                    .index(protocolParamsUtxo.getOutputIndex())
                                    .build(),
                            TransactionInput.builder()
                                    .transactionId(issuanceUtxo.getTxHash())
                                    .index(issuanceUtxo.getOutputIndex())
                                    .build())
                    .attachSpendingValidator(directorySpendContract)
                    .attachRewardValidator(substandardIssueContract)
                    .withChangeAddress(registerTokenRequest.issuerBaseAddress());

            var transaction = quickTxBuilder.compose(tx)
//                    .withSigner(SignerProviders.signerFrom(adminAccount))
//                    .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                    .feePayer(registerTokenRequest.issuerBaseAddress())
                    .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                    .preBalanceTx((txBuilderContext, transaction1) -> {
                        var outputs = transaction1.getBody().getOutputs();
                        if (outputs.getFirst().getAddress().equals(registerTokenRequest.issuerBaseAddress())) {
                            log.info("found dummy input, moving it...");
                            var first = outputs.removeFirst();
                            outputs.addLast(first);
                        }
                        try {
                            log.info("pre tx: {}", objectMapper.writeValueAsString(transaction1));
                        } catch (JsonProcessingException e) {
                            throw new RuntimeException(e);
                        }
                    })
                    .postBalanceTx((txBuilderContext, transaction1) -> {
                        try {
                            log.info("post tx: {}", objectMapper.writeValueAsString(transaction1));
                        } catch (JsonProcessingException e) {
                            throw new RuntimeException(e);
                        }
                    })
                    .build();

            log.info("tx: {}", transaction.serializeToHex());
            log.info("tx: {}", objectMapper.writeValueAsString(transaction));

            return ResponseEntity.ok(transaction.serializeToHex());

        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }


    @PostMapping("/mint")
    public ResponseEntity<?> mint(@Valid @RequestBody MintTokenRequest mintTokenRequest) {

        try {

            var protocolBootstrapParams = protocolBootstrapService.getProtocolBootstrapParams();

            var protocolParamsUtxoRef = protocolBootstrapParams.protocolParamsUtxo();
            var protocolParamsUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(protocolParamsUtxoRef.txHash())
                    .outputIndex(protocolParamsUtxoRef.outputIndex())
                    .build());
            if (protocolParamsUtxoOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve protocol params");
            }

            var protocolParamsUtxo = protocolParamsUtxoOpt.get();
            log.info("protocolParamsUtxo: {}", protocolParamsUtxo);

            var issuanceUtxoRef = protocolBootstrapParams.issuanceUtxo();
            var issuanceUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(issuanceUtxoRef.txHash())
                    .outputIndex(issuanceUtxoRef.outputIndex())
                    .build());
            if (issuanceUtxoOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve issuance params");
            }
            var issuanceUtxo = issuanceUtxoOpt.get();
            log.info("issuanceUtxo: {}", issuanceUtxo);

            var issuanceDatum = issuanceUtxo.getInlineDatum();
            var issuanceData = PlutusData.deserialize(HexUtil.decodeHexString(issuanceDatum));
            var issuance = objectMapper.writeValueAsString(issuanceData);
            log.info("issuance: {}", issuance);

            var programmableLogicBaseScriptHash = protocolBootstrapParams.programmableLogicBaseParams().scriptHash();

            var issuerUtxosOpt = utxoRepository.findUnspentByOwnerAddr(mintTokenRequest.issuerBaseAddress(), Pageable.unpaged());
            if (issuerUtxosOpt.isEmpty()) {
                return ResponseEntity.badRequest().body("issuer wallet is empty");
            }
            var issuerUtxos = issuerUtxosOpt.get().stream().map(UtxoUtil::toUtxo).toList();

            var substandardIssuanceContractOpt = substandardService.getSubstandardValidator(mintTokenRequest.substandardName(), mintTokenRequest.substandardIssueContractName());

            var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardIssuanceContractOpt.get().scriptBytes(), PlutusVersion.v3);
            log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

            // Issuance Parameterization
            var issuanceParameters = ListPlutusData.of(
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(HexUtil.decodeHexString(programmableLogicBaseScriptHash))
                    ),
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(substandardIssueContract.getScriptHash())
                    )
            );

            var issuanceMintOpt = protocolBootstrapService.getProtocolContract("issuance_mint.issuance_mint.mint");
            if (issuanceMintOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not find issuance mint contract");
            }

            var issuanceContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(issuanceParameters, issuanceMintOpt.get()), PlutusVersion.v3);
            log.info("issuanceContract: {}", issuanceContract.getPolicyId());

            var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));

            // Programmable Token Mint
            var pintToken = Asset.builder()
                    .name("0x" + mintTokenRequest.assetName())
                    .value(new BigInteger(mintTokenRequest.quantity()))
                    .build();

            Value pintTokenValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(
                            MultiAsset.builder()
                                    .policyId(issuanceContract.getPolicyId())
                                    .assets(List.of(pintToken))
                                    .build()
                    ))
                    .build();

            var recipient = Optional.ofNullable(mintTokenRequest.recipientAddress())
                    .orElse(mintTokenRequest.issuerBaseAddress());

            var recipientAddress = new Address(recipient);

            var targetAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                    recipientAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            var tx = new ScriptTx()
                    .collectFrom(issuerUtxos)
                    .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, BigIntPlutusData.of(100))
                    // Redeemer is DirectoryInit (constr(0))
                    .mintAsset(issuanceContract, pintToken, issuanceRedeemer)
                    .payToContract(targetAddress.getAddress(), ValueUtil.toAmountList(pintTokenValue), ConstrPlutusData.of(0))
                    .attachRewardValidator(substandardIssueContract)
                    .withChangeAddress(mintTokenRequest.issuerBaseAddress());

            var transaction = quickTxBuilder.compose(tx)
                    .feePayer(mintTokenRequest.issuerBaseAddress())
                    .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                    .preBalanceTx((txBuilderContext, transaction1) -> {
                        var outputs = transaction1.getBody().getOutputs();
                        if (outputs.getFirst().getAddress().equals(mintTokenRequest.issuerBaseAddress())) {
                            log.info("found dummy input, moving it...");
                            var first = outputs.removeFirst();
                            outputs.addLast(first);
                        }
                        try {
                            log.info("pre tx: {}", objectMapper.writeValueAsString(transaction1));
                        } catch (JsonProcessingException e) {
                            throw new RuntimeException(e);
                        }
                    })
                    .postBalanceTx((txBuilderContext, transaction1) -> {
                        try {
                            log.info("post tx: {}", objectMapper.writeValueAsString(transaction1));
                        } catch (JsonProcessingException e) {
                            throw new RuntimeException(e);
                        }
                    })
                    .build();

            log.info("tx: {}", transaction.serializeToHex());
            log.info("tx: {}", objectMapper.writeValueAsString(transaction));

            return ResponseEntity.ok(transaction.serializeToHex());

        } catch (Exception e) {
            log.warn("Failed to mint token: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

    @PostMapping("/issue")
    public ResponseEntity<?> issueToken(@Valid @RequestBody IssueTokenRequest issueTokenRequest) {

        try {

            var protocolBootstrapParams = protocolBootstrapService.getProtocolBootstrapParams();

            var protocolParamsUtxoRef = protocolBootstrapParams.protocolParamsUtxo();
            var protocolParamsUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(protocolParamsUtxoRef.txHash())
                    .outputIndex(protocolParamsUtxoRef.outputIndex())
                    .build());
            if (protocolParamsUtxoOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve protocol params");
            }

            var protocolParamsUtxo = protocolParamsUtxoOpt.get();
            log.info("protocolParamsUtxo: {}", protocolParamsUtxo);

            var issuanceUtxoRef = protocolBootstrapParams.issuanceUtxo();
            var issuanceUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(issuanceUtxoRef.txHash())
                    .outputIndex(issuanceUtxoRef.outputIndex())
                    .build());
            if (issuanceUtxoOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve issuance params");
            }
            var issuanceUtxo = issuanceUtxoOpt.get();
            log.info("issuanceUtxo: {}", issuanceUtxo);

            var issuanceDatum = issuanceUtxo.getInlineDatum();
            var issuanceData = PlutusData.deserialize(HexUtil.decodeHexString(issuanceDatum));
            var issuance = objectMapper.writeValueAsString(issuanceData);
            log.info("issuance: {}", issuance);

            var programmableLogicBaseScriptHash = protocolBootstrapParams.programmableLogicBaseParams().scriptHash();

            var issuerUtxosOpt = utxoRepository.findUnspentByOwnerAddr(issueTokenRequest.issuerBaseAddress(), Pageable.unpaged());
            if (issuerUtxosOpt.isEmpty()) {
                return ResponseEntity.badRequest().body("issuer wallet is empty");
            }
            var issuerUtxos = issuerUtxosOpt.get().stream().map(UtxoUtil::toUtxo).toList();

            var directoryUtxoRef = protocolBootstrapParams.directoryUtxo();
            var directoryUtxoOpt = utxoRepository.findById(UtxoId.builder()
                    .txHash(directoryUtxoRef.txHash())
                    .outputIndex(directoryUtxoRef.outputIndex())
                    .build());
            if (directoryUtxoOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not resolve directories");
            }

            var directoryUtxo = UtxoUtil.toUtxo(directoryUtxoOpt.get());
            log.info("directoryUtxo: {}", directoryUtxo);

            var directorySetNode = DirectorySetNode.fromInlineDatum(directoryUtxo.getInlineDatum());
            if (directorySetNode.isEmpty()) {
                log.error("could not deserialise directorySetNode for utxo: {}", directoryUtxo);
                return ResponseEntity.internalServerError().body("could not deserialise directorySetNode");
            }
            log.info("directorySetNode: {}", directorySetNode);

            var substandardIssuanceContractOpt = substandardService.getSubstandardValidator(issueTokenRequest.substandardName(), issueTokenRequest.substandardIssueContractName());
            var substandardTransferContractOpt = substandardService.getSubstandardValidator(issueTokenRequest.substandardName(), issueTokenRequest.substandardTransferContractName());

            if (substandardIssuanceContractOpt.isEmpty() || substandardTransferContractOpt.isEmpty()) {
                log.warn("substandard issuance or transfer contract are empty");
                return ResponseEntity.badRequest().body("substandard issuance or transfer contract are empty");
            }

            var substandardIssueContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardIssuanceContractOpt.get().scriptBytes(), PlutusVersion.v3);
            log.info("substandardIssueContract: {}", substandardIssueContract.getPolicyId());

            var substandardIssueAddress = AddressProvider.getRewardAddress(substandardIssueContract, network.getCardanoNetwork());
            log.info("substandardIssueAddress: {}", substandardIssueAddress.getAddress());

            var substandardTransferContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(substandardTransferContractOpt.get().scriptBytes(), PlutusVersion.v3);

            // Issuance Parameterization
            var issuanceParameters = ListPlutusData.of(
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(HexUtil.decodeHexString(programmableLogicBaseScriptHash))
                    ),
                    ConstrPlutusData.of(1,
                            BytesPlutusData.of(substandardIssueContract.getScriptHash())
                    )
            );

            var issuanceMintOpt = protocolBootstrapService.getProtocolContract("issuance_mint.issuance_mint.mint");
            if (issuanceMintOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not find issuance mint contract");
            }

            var issuanceContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(issuanceParameters, issuanceMintOpt.get()), PlutusVersion.v3);
            log.info("issuanceContract: {}", issuanceContract.getPolicyId());

            var issuanceRedeemer = ConstrPlutusData.of(0, ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())));
//        var issuanceRedeemer = ConstrPlutusData.of(0, BytesPlutusData.of(substandardIssueContract.getScriptHash()));


            var directoryMintOpt = protocolBootstrapService.getProtocolContract("registry_mint.registry_mint.mint");
            if (directoryMintOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not find directory mint contract");
            }

            // Directory MINT parameterization
            log.info("protocolBootstrapParams.directoryMintParams(): {}", protocolBootstrapParams.directoryMintParams());
            var directoryMintParameters = ListPlutusData.of(
                    ConstrPlutusData.of(0,
                            BytesPlutusData.of(HexUtil.decodeHexString(protocolBootstrapParams.directoryMintParams().txInput().txHash())),
                            BigIntPlutusData.of(protocolBootstrapParams.directoryMintParams().txInput().outputIndex())),
                    BytesPlutusData.of(HexUtil.decodeHexString(protocolBootstrapParams.directoryMintParams().issuanceScriptHash()))
            );
            var directoryMintContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(directoryMintParameters, directoryMintOpt.get()), PlutusVersion.v3);
            log.info("directoryMintContract: {}", directoryMintContract.getPolicyId());

            //        PROGRAMMABLE_LOGIC_BASE_CONTRACT = getCompiledCodeFor("programmable_logic_base.programmable_logic_base.spend", validators);

            var directorySpentOpt = protocolBootstrapService.getProtocolContract("registry_spend.registry_spend.spend");
            if (directorySpentOpt.isEmpty()) {
                return ResponseEntity.internalServerError().body("could not find directory spend contract");
            }

            // Directory SPEND parameterization
            var directorySpendParameters = ListPlutusData.of(
                    BytesPlutusData.of(HexUtil.decodeHexString(protocolBootstrapParams.protocolParams().scriptHash()))
            );
            var directorySpendContract = PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(AikenScriptUtil.applyParamToScript(directorySpendParameters, directorySpentOpt.get()), PlutusVersion.v3);
            log.info("directorySpendContract, policy: {}", directorySpendContract.getPolicyId());
            log.info("directorySpendContract, script hash: {}", HexUtil.encodeHexString(directorySpendContract.getScriptHash()));
            var directorySpendContractAddress = AddressProvider.getEntAddress(Credential.fromScript(directorySpendContract.getScriptHash()), network.getCardanoNetwork());
            log.info("directorySpendContractAddress: {}", directorySpendContractAddress.getAddress());


            // Directory MINT - NFT, address, datum and value
            var directoryMintRedeemer = ConstrPlutusData.of(1,
                    BytesPlutusData.of(issuanceContract.getScriptHash()),
                    BytesPlutusData.of(substandardIssueContract.getScriptHash())
            );

            var directoryMintNft = Asset.builder()
                    .name("0x" + issuanceContract.getPolicyId())
//                .name("0x01" + HexUtil.encodeHexString(issuanceContract.getScriptHash()))
                    .value(BigInteger.ONE)
                    .build();

            var directorySpendNft = Asset.builder()
                    .name("0x")
                    .value(BigInteger.ONE)
                    .build();

            var directorySpendDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(""),
                    BytesPlutusData.of(issuanceContract.getScriptHash()),
                    ConstrPlutusData.of(0, BytesPlutusData.of("")),
                    ConstrPlutusData.of(0, BytesPlutusData.of("")),
                    BytesPlutusData.of(""));

            var directoryMintDatum = ConstrPlutusData.of(0,
                    BytesPlutusData.of(issuanceContract.getScriptHash()),
                    BytesPlutusData.of(HexUtil.decodeHexString("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")),
                    ConstrPlutusData.of(1, BytesPlutusData.of(substandardTransferContract.getScriptHash())),
                    ConstrPlutusData.of(1, BytesPlutusData.of(substandardIssueContract.getScriptHash())),
                    BytesPlutusData.of(""));

            Value directoryMintValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(
                            MultiAsset.builder()
                                    .policyId(directoryMintContract.getPolicyId())
                                    .assets(List.of(directoryMintNft))
                                    .build()
                    ))
                    .build();

            Value directorySpendValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(
                            MultiAsset.builder()
                                    .policyId(directoryMintContract.getPolicyId())
                                    .assets(List.of(directorySpendNft))
                                    .build()
                    ))
                    .build();

            // Programmable Token Mint
            var pintToken = Asset.builder()
                    .name(HexUtil.encodeHexString("PINT".getBytes(), true))
                    .value(BigInteger.valueOf(1_000_000_000L))
                    .build();

            Value pintTokenValue = Value.builder()
                    .coin(Amount.ada(1).getQuantity())
                    .multiAssets(List.of(
                            MultiAsset.builder()
                                    .policyId(issuanceContract.getPolicyId())
                                    .assets(List.of(pintToken))
                                    .build()
                    ))
                    .build();

            var recipient = Optional.ofNullable(issueTokenRequest.recipientAddress())
                    .orElse(issueTokenRequest.issuerBaseAddress());

            var recipientAddress = new Address(recipient);

            var targetAddress = AddressProvider.getBaseAddress(Credential.fromScript(protocolBootstrapParams.programmableLogicBaseParams().scriptHash()),
                    recipientAddress.getDelegationCredential().get(),
                    network.getCardanoNetwork());

            var tx = new ScriptTx()
                    .collectFrom(issuerUtxos)
                    .collectFrom(directoryUtxo, ConstrPlutusData.of(0))
                    .withdraw(substandardIssueAddress.getAddress(), BigInteger.ZERO, BigIntPlutusData.of(100))
                    // Redeemer is DirectoryInit (constr(0))
                    .mintAsset(issuanceContract, pintToken, issuanceRedeemer)
                    .mintAsset(directoryMintContract, directoryMintNft, directoryMintRedeemer)
                    .payToContract(targetAddress.getAddress(), ValueUtil.toAmountList(pintTokenValue), ConstrPlutusData.of(0))
                    // Directory Params
                    .payToContract(directorySpendContractAddress.getAddress(), ValueUtil.toAmountList(directorySpendValue), directorySpendDatum)
                    // Directory Params
                    .payToContract(directorySpendContractAddress.getAddress(), ValueUtil.toAmountList(directoryMintValue), directoryMintDatum)
                    .readFrom(TransactionInput.builder()
                                    .transactionId(protocolParamsUtxo.getTxHash())
                                    .index(protocolParamsUtxo.getOutputIndex())
                                    .build(),
                            TransactionInput.builder()
                                    .transactionId(issuanceUtxo.getTxHash())
                                    .index(issuanceUtxo.getOutputIndex())
                                    .build())
                    .attachSpendingValidator(directorySpendContract)
                    .attachRewardValidator(substandardIssueContract)
                    .withChangeAddress(issueTokenRequest.issuerBaseAddress());

            var transaction = quickTxBuilder.compose(tx)
//                    .withSigner(SignerProviders.signerFrom(adminAccount))
//                    .withTxEvaluator(new AikenTransactionEvaluator(bfBackendService))
                    .feePayer(issueTokenRequest.issuerBaseAddress())
                    .mergeOutputs(false) //<-- this is important! or directory tokens will go to same address
                    .preBalanceTx((txBuilderContext, transaction1) -> {
                        var outputs = transaction1.getBody().getOutputs();
                        if (outputs.getFirst().getAddress().equals(issueTokenRequest.issuerBaseAddress())) {
                            log.info("found dummy input, moving it...");
                            var first = outputs.removeFirst();
                            outputs.addLast(first);
                        }
                        try {
                            log.info("pre tx: {}", objectMapper.writeValueAsString(transaction1));
                        } catch (JsonProcessingException e) {
                            throw new RuntimeException(e);
                        }
                    })
                    .postBalanceTx((txBuilderContext, transaction1) -> {
                        try {
                            log.info("post tx: {}", objectMapper.writeValueAsString(transaction1));
                        } catch (JsonProcessingException e) {
                            throw new RuntimeException(e);
                        }
                    })
                    .build();

            log.info("tx: {}", transaction.serializeToHex());
            log.info("tx: {}", objectMapper.writeValueAsString(transaction));

            return ResponseEntity.ok(transaction.serializeToHex());

        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(e.getMessage());
        }
    }

}
