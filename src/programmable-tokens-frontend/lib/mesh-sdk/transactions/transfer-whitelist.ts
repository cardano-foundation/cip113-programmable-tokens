import {
  Asset,
  conStr,
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

import { provider, getNetworkName } from "../config";
import { Cip113_scripts_standard } from "../standard/deploy";
import { cip113_scripts_whitelistSendReceiveMultiAdmin } from "../substandard/whitelist-send-receive-multiadmin/deploy";
import {
  ProtocolBootstrapParams,
  ProtocolBlueprint,
  SubstandardBlueprint,
} from "../../../types/protocol";
import {
  parseRegistryDatum,
  sortTxInputRefs,
} from "../../utils/script-utils";

interface WhitelistNode {
  key: string;
  next: string;
}

function parseWhitelistNodeDatum(datum: any): WhitelistNode | null {
  if (!datum?.fields || datum.fields.length < 2) return null;
  return {
    key: datum.fields[0].bytes,
    next: datum.fields[1].bytes,
  };
}

/**
 * Build a whitelist-send-receive-multiadmin transfer transaction.
 *
 * Key difference from FES:
 * - FES: non-membership proof (node.key < credential < node.next)
 * - Whitelist: membership proof (node.key == credential)
 * - Transfer redeemer: ConStr(0, [senderProofs, receiverProofs])
 */
const transfer_whitelist_token = async (
  unit: string,
  quantity: string,
  recipientAddress: string,
  params: ProtocolBootstrapParams,
  Network_id: 0 | 1,
  wallet: IWallet,
  protocolBlueprint: ProtocolBlueprint,
  substandardBlueprint: SubstandardBlueprint,
  whitelistPolicyId: string
) => {
  const policyId = unit.substring(0, POLICY_ID_LENGTH);
  const changeAddress = await wallet.getChangeAddress();
  const walletUtxos = await wallet.getUtxos();
  const collateral = (await wallet.getCollateral())[0];

  if (!collateral) throw new Error("No collateral available");
  if (!walletUtxos) throw new Error("Issuer wallet is empty");

  // Build standard protocol scripts
  const standardScript = new Cip113_scripts_standard(
    Network_id,
    protocolBlueprint
  );
  const logic_base = await standardScript.programmable_logic_base(params);
  const logic_global = await standardScript.programmable_logic_global(params);
  const registry_spend = await standardScript.registry_spend(params);

  // Build whitelist scripts
  const wlScripts = new cip113_scripts_whitelistSendReceiveMultiAdmin(
    Network_id,
    substandardBlueprint
  );
  const substandard_transfer = await wlScripts.transfer_withdraw(
    params.programmableLogicBaseParams.scriptHash,
    whitelistPolicyId
  );
  const whitelist_spend = await wlScripts.whitelist_spend(whitelistPolicyId);

  // Extract sender credentials
  const senderDeserialized = deserializeAddress(changeAddress);
  const senderBase = senderDeserialized.asBase();
  if (!senderBase) {
    throw new Error(`Sender changeAddress is not a base address: ${changeAddress}`);
  }
  const senderStakeCred = senderBase.getStakeCredential();
  const senderCredential = senderStakeCred.hash;
  if (!senderCredential) {
    throw new Error(`Could not extract staking credential from sender address`);
  }

  // Extract recipient credentials
  const recipientDeserialized = deserializeAddress(recipientAddress);
  const recipientBase = recipientDeserialized.asBase();
  if (!recipientBase) {
    throw new Error(`Recipient address is not a base address: ${recipientAddress}`);
  }
  const recipientStakeCred = recipientBase.getStakeCredential();
  const recipientCredential = recipientStakeCred.hash;
  if (!recipientCredential) {
    throw new Error(`Could not extract staking credential from recipient address`);
  }

  // Build sender and recipient programmable token addresses
  const senderBaseAddress = buildBaseAddress(
    Network_id,
    logic_base.policyId as Hash28ByteBase16,
    senderCredential,
    CredentialType.ScriptHash,
    CredentialType.KeyHash
  );
  const recipientBaseAddress = buildBaseAddress(
    Network_id,
    logic_base.policyId as Hash28ByteBase16,
    recipientCredential,
    CredentialType.ScriptHash,
    CredentialType.KeyHash
  );
  const senderAddress = senderBaseAddress.toAddress().toBech32();
  const targetAddress = recipientBaseAddress.toAddress().toBech32();

  // Find registry entry for this token
  const registryUtxos = await provider.fetchAddressUTxOs(registry_spend.address);
  const progTokenRegistry = registryUtxos.find((utxo: UTxO) => {
    const datum = deserializeDatum(utxo.output.plutusData!);
    const parsedDatum = parseRegistryDatum(datum);
    return parsedDatum?.key === policyId;
  });
  if (!progTokenRegistry) {
    throw new Error("Could not find registry entry for token");
  }

  // Fetch protocol params UTxO
  const protocolParamsUtxos = await provider.fetchUTxOs(params.txHash, 0);
  if (!protocolParamsUtxos) throw new Error("Could not resolve protocol params");
  const protocolParamsUtxo = protocolParamsUtxos[0];

  // Fetch sender's programmable token UTxOs
  const senderProgTokenUtxos = await provider.fetchAddressUTxOs(senderAddress);
  if (!senderProgTokenUtxos || senderProgTokenUtxos.length === 0) {
    throw new Error("No programmable tokens found at sender address");
  }

  // Select UTxOs with enough tokens
  const transferAmount = Number(quantity);
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
  if (selectedAmount < transferAmount) throw new Error("Not enough funds");
  const returningAmount = selectedAmount - transferAmount;

  // Fetch whitelist UTxOs for MEMBERSHIP proofs
  const whitelistUtxos = await provider.fetchAddressUTxOs(whitelist_spend.address);

  // Build sender membership proofs
  const stakingPkh = senderCredential.toString();
  const senderProofs: { tokenUtxo: UTxO; whitelistUtxo: UTxO }[] = [];

  for (const utxo of selectedUtxos) {
    const proof = whitelistUtxos.find((wlUtxo) => {
      if (!wlUtxo.output.plutusData) return false;
      const datum = deserializeDatum(wlUtxo.output.plutusData);
      const node = parseWhitelistNodeDatum(datum);
      if (!node) return false;
      // Membership proof: node.key == credential
      return node.key === stakingPkh;
    });

    if (!proof) {
      throw new Error("Sender address not whitelisted");
    }
    senderProofs.push({ tokenUtxo: utxo, whitelistUtxo: proof });
  }

  // Build receiver membership proof
  const receiverPkh = recipientCredential.toString();
  const receiverWhitelistUtxo = whitelistUtxos.find((wlUtxo) => {
    if (!wlUtxo.output.plutusData) return false;
    const datum = deserializeDatum(wlUtxo.output.plutusData);
    const node = parseWhitelistNodeDatum(datum);
    if (!node) return false;
    return node.key === receiverPkh;
  });

  if (!receiverWhitelistUtxo) {
    throw new Error("Receiver address not whitelisted");
  }

  // Deduplicate whitelist UTxOs
  const uniqueWhitelistInputs: { txHash: string; outputIndex: number }[] = [];
  const seenWhitelist = new Set<string>();
  const allProofUtxos = [
    ...senderProofs.map((p) => p.whitelistUtxo),
    receiverWhitelistUtxo,
  ];
  for (const utxo of allProofUtxos) {
    const key = `${utxo.input.txHash}#${utxo.input.outputIndex}`;
    if (!seenWhitelist.has(key)) {
      seenWhitelist.add(key);
      uniqueWhitelistInputs.push({
        txHash: utxo.input.txHash,
        outputIndex: utxo.input.outputIndex,
      });
    }
  }

  // Build sorted reference inputs
  const allRefInputs = [
    ...uniqueWhitelistInputs,
    {
      txHash: protocolParamsUtxo.input.txHash,
      outputIndex: protocolParamsUtxo.input.outputIndex,
    },
    {
      txHash: progTokenRegistry.input.txHash,
      outputIndex: progTokenRegistry.input.outputIndex,
    },
  ];
  const sortedRefInputs = sortTxInputRefs(allRefInputs);

  // Compute sender proof indices
  const senderProofIndices = senderProofs.map((p) => {
    const idx = sortedRefInputs.findIndex(
      (ri) =>
        ri.txHash === p.whitelistUtxo.input.txHash &&
        ri.outputIndex === p.whitelistUtxo.input.outputIndex
    );
    return idx;
  });

  // Compute receiver proof index
  const receiverProofIndex = sortedRefInputs.findIndex(
    (ri) =>
      ri.txHash === receiverWhitelistUtxo.input.txHash &&
      ri.outputIndex === receiverWhitelistUtxo.input.outputIndex
  );

  // Compute registry index for global redeemer
  const registryIndex = sortedRefInputs.findIndex(
    (ri) =>
      ri.txHash === progTokenRegistry.input.txHash &&
      ri.outputIndex === progTokenRegistry.input.outputIndex
  );

  // Build redeemers
  // Transfer redeemer: ConStr(0, [senderProofs, receiverProofs])
  const senderProofsList = list(
    senderProofIndices.map((idx) => conStr(0, [integer(idx)]))
  );
  const receiverProofsList = list([conStr(0, [integer(receiverProofIndex)])]);
  const transferRedeemer = conStr0([senderProofsList, receiverProofsList]);

  // Global redeemer: ConStr(0, [list([ConStr(0, [registryIndex])])])
  const programmableLogicGlobalRedeemer = conStr0([
    list([conStr0([integer(registryIndex)])]),
  ]);

  const spendingRedeemer = conStr0([]);
  const tokenDatum = conStr0([]);

  // Build output assets
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

  // Build transaction
  const txBuilder = new MeshTxBuilder({
    fetcher: provider,
    submitter: provider,
    evaluator: provider,
    verbose: true,
  });

  // Spend selected prog-token UTxOs
  for (const utxo of selectedUtxos) {
    txBuilder
      .spendingPlutusScriptV3()
      .txIn(utxo.input.txHash, utxo.input.outputIndex)
      .txInScript(logic_base.cbor)
      .txInRedeemerValue(spendingRedeemer, "JSON")
      .txInInlineDatumPresent();
  }

  // Withdrawal validators
  txBuilder
    .withdrawalPlutusScriptV3()
    .withdrawal(logic_global.reward_address, "0")
    .withdrawalScript(logic_global.cbor)
    .withdrawalRedeemerValue(programmableLogicGlobalRedeemer, "JSON")

    .withdrawalPlutusScriptV3()
    .withdrawal(substandard_transfer.reward_address, "0")
    .withdrawalScript(substandard_transfer.cbor)
    .withdrawalRedeemerValue(transferRedeemer, "JSON")
    .requiredSignerHash(senderCredential!.toString())

    .txOut(changeAddress, [{ unit: "lovelace", quantity: "1000000" }]);

  // Return change to sender if needed
  if (returningAmount > 0) {
    txBuilder
      .txOut(senderAddress, returningAssets)
      .txOutInlineDatumValue(tokenDatum, "JSON");
  }

  // Recipient output
  txBuilder
    .txOut(targetAddress, recipientAssets)
    .txOutInlineDatumValue(tokenDatum, "JSON");

  // Add all sorted reference inputs
  for (const ref of sortedRefInputs) {
    txBuilder.readOnlyTxInReference(ref.txHash, ref.outputIndex);
  }

  txBuilder
    .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
    .selectUtxosFrom(walletUtxos)
    .setNetwork(getNetworkName())
    .changeAddress(changeAddress);

  const result = await txBuilder.complete();
  return result;
};

export { transfer_whitelist_token };
