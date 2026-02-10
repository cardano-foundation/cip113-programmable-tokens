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
import { cip113_scripts_freezeAndSeize } from "../substandard/freeze-and-seize/deploy";
import {
  ProtocolBootstrapParams,
  ProtocolBlueprint,
  SubstandardBlueprint,
} from "../../../types/protocol";
import {
  parseRegistryDatum,
  parseBlacklistNodeDatum,
  sortTxInputRefs,
} from "../../utils/script-utils";

/**
 * Build a freeze-and-seize transfer transaction.
 *
 * This is the Mesh SDK port of Java FreezeAndSeizeHandler.buildTransferTransaction().
 * Key differences from dummy transfer:
 * - Transfer script is parameterized with progLogicBaseScriptHash + blacklistNodePolicyId
 * - Must build blacklist non-membership proofs (sender NOT on blacklist)
 * - Extra reference inputs for blacklist proof UTxOs
 * - Transfer redeemer is a list of proof indices (not integer(200))
 */
const transfer_freeze_and_seize_token = async (
  unit: string,
  quantity: string,
  recipientAddress: string,
  params: ProtocolBootstrapParams,
  Network_id: 0 | 1,
  wallet: IWallet,
  protocolBlueprint: ProtocolBlueprint,
  substandardBlueprint: SubstandardBlueprint,
  blacklistNodePolicyId: string
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

  // Build parameterized freeze-and-seize scripts
  const fesScripts = new cip113_scripts_freezeAndSeize(
    Network_id,
    substandardBlueprint
  );
  const substandard_transfer = await fesScripts.transfer_withdraw(
    params.programmableLogicBaseParams.scriptHash,
    blacklistNodePolicyId
  );
  const blacklist_spend = await fesScripts.blacklist_spend(
    blacklistNodePolicyId
  );

  // Extract sender credentials
  const senderDeserialized = deserializeAddress(changeAddress);
  const senderBase = senderDeserialized.asBase();

  if (!senderBase) {
    throw new Error(
      `Sender changeAddress is not a base address: ${changeAddress}`
    );
  }
  const senderStakeCred = senderBase.getStakeCredential();
  const senderCredential = senderStakeCred.hash;

  if (!senderCredential) {
    throw new Error(
      `Could not extract staking credential from sender address: ${changeAddress}`
    );
  }

  // Extract recipient credentials
  const recipientDeserialized = deserializeAddress(recipientAddress);
  const recipientBase = recipientDeserialized.asBase();

  if (!recipientBase) {
    throw new Error(
      `Recipient address is not a base address: ${recipientAddress}`
    );
  }
  const recipientStakeCred = recipientBase.getStakeCredential();
  const recipientCredential = recipientStakeCred.hash;

  if (!recipientCredential) {
    throw new Error(
      `Could not extract staking credential from recipient address: ${recipientAddress}`
    );
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

  // Fetch protocol params UTxO
  const protocolParamsUtxos = await provider.fetchUTxOs(params.txHash, 0);
  if (!protocolParamsUtxos)
    throw new Error("Could not resolve protocol params");
  const protocolParamsUtxo = protocolParamsUtxos[0];

  // Fetch sender's programmable token UTxOs
  const senderProgTokenUtxos = await provider.fetchAddressUTxOs(senderAddress);
  if (!senderProgTokenUtxos || senderProgTokenUtxos.length === 0) {
    throw new Error("No programmable tokens found at sender address");
  }

  // Calculate total balance and select UTxOs
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

  // Fetch blacklist UTxOs for non-membership proofs
  const blacklistUtxos = await provider.fetchAddressUTxOs(
    blacklist_spend.address
  );

  // Build blacklist non-membership proofs
  // For each selected prog-token UTxO, find a blacklist node proving sender is NOT blacklisted
  const stakingPkh = senderCredential.toString();
  const proofs: { tokenUtxo: UTxO; blacklistUtxo: UTxO }[] = [];

  for (const utxo of selectedUtxos) {
    const proof = blacklistUtxos.find((blUtxo) => {
      if (!blUtxo.output.plutusData) return false;
      const datum = deserializeDatum(blUtxo.output.plutusData);
      const node = parseBlacklistNodeDatum(datum);
      if (!node) return false;
      // Non-membership proof: node.key < stakingPkh < node.next
      // Head node has key="" (less than any hash), tail has next="ff..ff" (greater than any hash)
      return node.key < stakingPkh && stakingPkh < node.next;
    });

    if (!proof) {
      throw new Error(
        "Could not resolve blacklist exemption - sender may be blacklisted"
      );
    }
    proofs.push({ tokenUtxo: utxo, blacklistUtxo: proof });
  }

  // Deduplicate blacklist UTxOs (same node may prove multiple inputs)
  const uniqueBlacklistInputs: { txHash: string; outputIndex: number }[] = [];
  const seenBlacklist = new Set<string>();
  for (const p of proofs) {
    const key = `${p.blacklistUtxo.input.txHash}#${p.blacklistUtxo.input.outputIndex}`;
    if (!seenBlacklist.has(key)) {
      seenBlacklist.add(key);
      uniqueBlacklistInputs.push({
        txHash: p.blacklistUtxo.input.txHash,
        outputIndex: p.blacklistUtxo.input.outputIndex,
      });
    }
  }

  // Build sorted reference inputs (blacklist proofs + protocol params + registry)
  const allRefInputs = [
    ...uniqueBlacklistInputs,
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

  // Compute proof indices: position of each blacklist proof in sorted ref inputs
  const proofIndices = proofs.map((p) => {
    const idx = sortedRefInputs.findIndex(
      (ri) =>
        ri.txHash === p.blacklistUtxo.input.txHash &&
        ri.outputIndex === p.blacklistUtxo.input.outputIndex
    );
    return idx;
  });

  // Compute registry index for global redeemer
  const registryIndex = sortedRefInputs.findIndex(
    (ri) =>
      ri.txHash === progTokenRegistry.input.txHash &&
      ri.outputIndex === progTokenRegistry.input.outputIndex
  );

  // Build redeemers
  // FES transfer redeemer: list of ConStr(0, [index]) - blacklist non-membership proofs
  const fesRedeemer = list(
    proofIndices.map((idx) => conStr(0, [integer(idx)]))
  );

  // Global redeemer: ConStr(0, [list([ConStr(0, [registryIndex])])])
  const registryProof = conStr0([integer(registryIndex)]);
  const programmableLogicGlobalRedeemer = conStr0([list([registryProof])]);

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

  // Withdrawal validators: global logic first, then substandard transfer
  // (swapped order — Cardano sorts withdrawals by reward address,
  //  Mesh may not re-sort redeemers to match)
  txBuilder
    .withdrawalPlutusScriptV3()
    .withdrawal(logic_global.reward_address, "0")
    .withdrawalScript(logic_global.cbor)
    .withdrawalRedeemerValue(programmableLogicGlobalRedeemer, "JSON")

    .withdrawalPlutusScriptV3()
    .withdrawal(substandard_transfer.reward_address, "0")
    .withdrawalScript(substandard_transfer.cbor)
    .withdrawalRedeemerValue(fesRedeemer, "JSON")
    .requiredSignerHash(senderCredential!.toString())

    .txOut(changeAddress, [
      {
        unit: "lovelace",
        quantity: "1000000",
      },
    ]);

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

export { transfer_freeze_and_seize_token };
