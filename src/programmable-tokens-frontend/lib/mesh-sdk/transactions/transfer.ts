import {
  Asset,
  conStr0,
  deserializeDatum,
  integer,
  IWallet,
  list,
  MeshTxBuilder,
  POLICY_ID_LENGTH,
  UTxO,
} from "@meshsdk/core";
import {
  buildBaseAddress,
  CredentialType,
  deserializeAddress,
  Hash28ByteBase16,
} from "@meshsdk/core-cst";

import { provider } from "../config";
import { Cip113_scripts_standard } from "../standard/deploy";
import cip113_scripts_subStandard from "../substandard/dummy/deploy";
import { ProtocolBootstrapParams } from "../../../types/protocol";
import { parseRegistryDatum } from "../../utils/script-utils";

const transfer_programmable_token = async (
  unit: string,
  quantity: string,
  recipientAddress: string,
  params: ProtocolBootstrapParams,
  Network_id: 0 | 1,
  wallet: IWallet
) => {
  const policyId = unit.substring(0, POLICY_ID_LENGTH);
  const changeAddress = await wallet.getChangeAddress();
  const walletUtxos = await wallet.getUtxos();
  const collateral = (await wallet.getCollateral())[0];

  if (!collateral) throw new Error("No collateral available");
  if (!walletUtxos) throw new Error("Issuer wallet is empty");

  const standardScript = new Cip113_scripts_standard(Network_id);
  const substandardScript = new cip113_scripts_subStandard(Network_id);
  const logic_base = await standardScript.programmable_logic_base(params);
  const logic_global = await standardScript.programmable_logic_global(params);
  const registry_spend = await standardScript.registry_spend(params);
  const substandard_transfer =
    await substandardScript.transfer_transfer_withdraw();

  const senderCredential = deserializeAddress(changeAddress)
    .asBase()
    ?.getStakeCredential().hash;

  const recipientCredential = deserializeAddress(recipientAddress)
    .asBase()
    ?.getStakeCredential().hash;

  const senderBaseAddress = buildBaseAddress(
    0,
    logic_base.policyId as Hash28ByteBase16,
    senderCredential!,
    CredentialType.ScriptHash,
    CredentialType.KeyHash
  );
  const recipientBaseAddress = buildBaseAddress(
    0,
    logic_base.policyId as Hash28ByteBase16,
    recipientCredential!,
    CredentialType.ScriptHash,
    CredentialType.KeyHash
  );
  const senderAddress = senderBaseAddress.toAddress().toBech32();
  const targetAddress = recipientBaseAddress.toAddress().toBech32();

  const registryUtxos = await provider.fetchAddressUTxOs(
    registry_spend.address
  );

  const progTokenRegistry = registryUtxos.find((utxo: UTxO) => {
    const datum = deserializeDatum(utxo.output.plutusData!);
    const parsedDatum = parseRegistryDatum(datum);
    return parsedDatum?.key === policyId;
  });

  if (!progTokenRegistry) {
    throw new Error("Could not find registry entry for token");
  }

  const protocolParamsUtxos = await provider.fetchUTxOs(params.txHash, 0);
  if (!protocolParamsUtxos)
    throw new Error("Could not resolve protocol params");
  const protocolParamsUtxo = protocolParamsUtxos[0];

  const senderProgTokenUtxos = await provider.fetchAddressUTxOs(senderAddress);
  if (!senderProgTokenUtxos) {
    throw new Error("No programmable tokens found at sender address");
  }

  let totalTokenBalance = 0;
  senderProgTokenUtxos.forEach((utxo: UTxO) => {
    const tokenAsset = utxo.output.amount.find((a) => a.unit === unit);
    if (tokenAsset) totalTokenBalance += Number(tokenAsset.quantity);
  });

  const transferAmount = Number(quantity);
  if (totalTokenBalance < transferAmount) throw new Error("Not enough funds");

  let selectedUtxos: UTxO[] = [];
  let selectedAmount = 0;
  for (const utxo of senderProgTokenUtxos) {
    if (selectedAmount >= transferAmount) break;
    const tokenAsset = utxo.output.amount.find((a) => a.unit === unit);
    if (tokenAsset) {
      selectedUtxos.push(utxo);
      selectedAmount += Number(tokenAsset.quantity);
    }
  }

  const returningAmount = selectedAmount - transferAmount;

  const registryProof = conStr0([integer(1)]);
  const programmableLogicGlobalRedeemer = conStr0([list([registryProof])]);
  const substandardTransferRedeemer = integer(200);
  const spendingRedeemer = conStr0([]);
  const tokenDatum = conStr0([]);

  const recipientAssets: Asset[] = [
    { unit: "lovelace", quantity: "1300000" },
    { unit: unit, quantity: transferAmount.toString() },
  ];

  const returningAssets: Asset[] = [{ unit: "lovelace", quantity: "1300000" }];
  if (returningAmount > 0) {
    returningAssets.push({
      unit: unit,
      quantity: returningAmount.toString(),
    });
  }

  const txBuilder = new MeshTxBuilder();

  for (const utxo of selectedUtxos) {
    txBuilder
      .spendingPlutusScriptV3()
      .txIn(utxo.input.txHash, utxo.input.outputIndex)
      .txInScript(logic_base.cbor)
      .txInRedeemerValue(spendingRedeemer, "JSON")
      .txInInlineDatumPresent();
  }

  txBuilder
    .withdrawalPlutusScriptV3()
    .withdrawal(substandard_transfer.reward_address, "0")
    .withdrawalScript(substandard_transfer._cbor)
    .withdrawalRedeemerValue(substandardTransferRedeemer, "JSON")

    .withdrawalPlutusScriptV3()
    .withdrawal(logic_global.reward_address, "0")
    .withdrawalScript(logic_global.cbor)
    .withdrawalRedeemerValue(programmableLogicGlobalRedeemer, "JSON")
    .requiredSignerHash(senderCredential!.toString())

    .txOut(changeAddress, [
      {
        unit: "lovelace",
        quantity: "1000000",
      },
    ]);

  if (returningAmount > 0) {
    txBuilder
      .txOut(senderAddress, returningAssets)
      .txOutInlineDatumValue(tokenDatum, "JSON");
  }

  txBuilder
    .txOut(targetAddress, recipientAssets)
    .txOutInlineDatumValue(tokenDatum, "JSON")

    .readOnlyTxInReference(
      protocolParamsUtxo.input.txHash,
      protocolParamsUtxo.input.outputIndex
    )
    .readOnlyTxInReference(
      progTokenRegistry.input.txHash,
      progTokenRegistry.input.outputIndex
    )

    .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
    .selectUtxosFrom(walletUtxos)
    .setNetwork("preview")
    .changeAddress(changeAddress);

  return await txBuilder.complete();
};

export { transfer_programmable_token };
