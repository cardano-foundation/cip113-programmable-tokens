import {
  Asset,
  byteString,
  conStr0,
  conStr1,
  deserializeDatum,
  IWallet,
  MeshTxBuilder,
  stringToHex,
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
import type {
  ProtocolBootstrapParams,
  ProtocolBlueprint,
  SubstandardBlueprint,
} from "../../../types/protocol";

/**
 * Build a Freeze-and-Seize token registration transaction.
 *
 * This is the Mesh SDK port of Java FreezeAndSeizeHandler.buildRegistrationTransaction().
 * Key differences from dummy register:
 * - Issue script: issuer_admin_withdraw (parameterized with adminPubKeyHash as Key credential)
 * - Transfer script: transfer_withdraw (parameterized with progLogicBase + blacklistNodePolicyId)
 * - Registry node thirdPartyScriptHash = issuer_admin.policy_id
 * - Issuance mint uses issuer_admin.policy_id as minting logic credential
 * - Withdrawal from issuer_admin reward address
 * - Required signer: adminPubKeyHash
 */
const register_fes_token = async (
  assetName: string,
  quantity: string,
  adminPubKeyHash: string,
  blacklistNodePolicyId: string,
  params: ProtocolBootstrapParams,
  Network_id: 0 | 1,
  wallet: IWallet,
  protocolBlueprint: ProtocolBlueprint,
  substandardBlueprint: SubstandardBlueprint,
  recipientAddress?: string | null,
) => {
  console.log("[FES-REG] === Starting register_fes_token ===");

  console.log("[FES-REG] Step 1: Getting wallet data...");
  const changeAddress = await wallet.getChangeAddress();
  const walletUtxos = await wallet.getUtxos();
  const collateral = (await wallet.getCollateral())[0];

  if (!collateral) throw new Error("No collateral available");
  if (!walletUtxos || walletUtxos.length === 0) throw new Error("Issuer wallet is empty");

  // Log wallet UTxOs for debugging coin selection issues
  const totalLovelace = walletUtxos.reduce((sum, u) => {
    const ada = u.output.amount.find((a: { unit: string }) => a.unit === "lovelace");
    return sum + BigInt(ada?.quantity || "0");
  }, 0n);
  console.log("[FES-REG] Step 1 OK: changeAddress=%s, utxos=%d, totalADA=%s, collateral=%s#%d",
    changeAddress.slice(0, 20) + "...", walletUtxos.length,
    (totalLovelace / 1_000_000n).toString() + " ADA",
    collateral.input.txHash.slice(0, 16), collateral.input.outputIndex);
  walletUtxos.forEach((u, i) => {
    const amounts = u.output.amount.map((a: { unit: string; quantity: string }) =>
      a.unit === "lovelace" ? `${(BigInt(a.quantity) / 1_000_000n).toString()} ADA` : `${a.quantity} ${a.unit.slice(0, 16)}...`
    ).join(", ");
    console.log("[FES-REG]   utxo[%d]: %s#%d → %s", i, u.input.txHash.slice(0, 16), u.input.outputIndex, amounts);
  });

  console.log("[FES-REG] Step 2: Building scripts...");
  // Build standard protocol scripts
  const standardScript = new Cip113_scripts_standard(
    Network_id,
    protocolBlueprint
  );
  const fesScripts = new cip113_scripts_freezeAndSeize(
    Network_id,
    substandardBlueprint
  );

  const registry_spend = await standardScript.registry_spend(params);
  const registry_mint = await standardScript.registry_mint(params);

  // Build FES-specific scripts
  const issuer_admin = await fesScripts.issuer_admin_withdraw(adminPubKeyHash);
  const substandard_transfer = await fesScripts.transfer_withdraw(
    params.programmableLogicBaseParams.scriptHash,
    blacklistNodePolicyId
  );

  // Parameterize issuance_mint with issuer_admin as the minting logic credential
  const issuance_mint = await standardScript.issuance_mint(
    params,
    issuer_admin.policy_id
  );
  const prog_token_policyId = issuance_mint.policy_id;
  console.log("[FES-REG] Step 2 OK: prog_token_policyId=%s, issuer_admin=%s, transfer=%s",
    prog_token_policyId.slice(0, 16), issuer_admin.policy_id.slice(0, 16), substandard_transfer.policy_id.slice(0, 16));

  console.log("[FES-REG] Step 3: Fetching protocol reference UTxOs...");
  // Fetch protocol reference UTxOs
  const bootstrapTxHash = params.txHash;
  const protocolParamsUtxos = await provider.fetchUTxOs(bootstrapTxHash, 0);
  if (!protocolParamsUtxos || protocolParamsUtxos.length === 0)
    throw new Error("Protocol parameters UTXO not found");

  const issuanceUtxos = await provider.fetchUTxOs(bootstrapTxHash, 2);
  if (!issuanceUtxos || issuanceUtxos.length === 0) throw new Error("Issuance UTXO not found");

  const protocolParamsUtxo = protocolParamsUtxos[0];
  const issuanceUtxo = issuanceUtxos[0];
  console.log("[FES-REG] Step 3 OK: protocolParams=%s#%d, issuance=%s#%d",
    protocolParamsUtxo.input.txHash.slice(0, 16), protocolParamsUtxo.input.outputIndex,
    issuanceUtxo.input.txHash.slice(0, 16), issuanceUtxo.input.outputIndex);

  console.log("[FES-REG] Step 4: Building recipient address...");
  // Build recipient address (programmable logic base + stake credential)
  const sender_cred = deserializeAddress(
    recipientAddress ? recipientAddress : changeAddress
  ).asBase();
  if (!sender_cred) throw new Error("Sender credential not found");

  const logic_base = await standardScript.programmable_logic_base(params);
  const logic_address = buildBaseAddress(
    Network_id,
    logic_base.policyId as Hash28ByteBase16,
    sender_cred.getStakeCredential().hash,
    CredentialType.ScriptHash,
    CredentialType.KeyHash
  );
  const targetAddress = logic_address.toAddress().toBech32();
  console.log("[FES-REG] Step 4 OK: targetAddress=%s", targetAddress.slice(0, 30) + "...");

  console.log("[FES-REG] Step 5: Fetching registry entries...");
  // Find existing registry entries and check for duplicates
  const registryEntries = await provider.fetchAddressUTxOs(
    registry_spend.address
  );
  console.log("[FES-REG] Step 5: Found %d registry entries at %s", registryEntries.length, registry_spend.address.slice(0, 30) + "...");

  // Parse each datum to at least key+next (minimum 2 fields) for linked list navigation
  const parsedEntries = registryEntries.map((utxo: UTxO) => {
    const datum = deserializeDatum(utxo.output.plutusData!);
    if (!datum?.fields || datum.fields.length < 2) return null;
    return {
      utxo,
      datum,  // keep the raw datum for later reconstruction
      key: datum.fields[0].bytes as string,
      next: datum.fields[1].bytes as string,
    };
  }).filter((e): e is NonNullable<typeof e> => e !== null);

  // Check for duplicate registration
  const existingEntry = parsedEntries.find((e) => e.key === prog_token_policyId);
  if (existingEntry) {
    throw new Error(`Token policy ${prog_token_policyId} already registered`);
  }

  // Find node to replace in the linked list (insertion point)
  const nodeToReplace = parsedEntries.find((e) => {
    const after = e.key.localeCompare(prog_token_policyId) < 0;
    const before = prog_token_policyId.localeCompare(e.next) < 0;
    return after && before;
  });

  if (!nodeToReplace) throw new Error("Could not find node to replace");
  console.log("[FES-REG] Step 5 OK: nodeToReplace key=%s, next=%s, fields=%d",
    nodeToReplace.key.slice(0, 16) || "(empty)", nodeToReplace.next.slice(0, 16),
    nodeToReplace.datum.fields.length);

  // Build redeemers
  // Directory mint redeemer: Insert(prog_token_policyId, issuer_admin.policy_id)
  const directoryMintRedeemer = conStr1([
    byteString(prog_token_policyId),
    byteString(issuer_admin.policy_id),
  ]);

  // Issuance redeemer: MintTokens(Script(issuer_admin.policy_id))
  const issuanceRedeemer = conStr0([
    conStr1([byteString(issuer_admin.policy_id)]),
  ]);

  // Build registry node datums
  // Updated previous node: clone original datum, only change field[1] (next → new policy)
  // This preserves the exact datum structure regardless of field count (2-field sentinel or 5-field full node)
  const previousNodeFields = [...nodeToReplace.datum.fields];
  previousNodeFields[1] = { bytes: prog_token_policyId };
  const previous_node_datum = {
    constructor: 0,
    fields: previousNodeFields,
  };

  // New node: FES-specific — transferScriptHash=transfer, thirdPartyScriptHash=issuer_admin
  const new_node_datum = conStr0([
    byteString(prog_token_policyId),
    byteString(nodeToReplace.next),
    conStr1([byteString(substandard_transfer.policy_id)]),
    conStr1([byteString(issuer_admin.policy_id)]),
    byteString(""),
  ]);

  // Build output assets
  const directorySpendAssets: Asset[] = [
    { unit: "lovelace", quantity: "2000000" },
    { unit: registry_mint.policy_id + nodeToReplace.key, quantity: "1" },
  ];

  const directoryMintAssets: Asset[] = [
    { unit: "lovelace", quantity: "2000000" },
    { unit: registry_mint.policy_id + prog_token_policyId, quantity: "1" },
  ];

  const programmableTokenAssets: Asset[] = [
    { unit: "lovelace", quantity: "2000000" },
    {
      unit: prog_token_policyId + stringToHex(assetName),
      quantity: quantity,
    },
  ];

  console.log("[FES-REG] Step 6: Building MeshTxBuilder...");
  // Build transaction
  const txBuilder = new MeshTxBuilder({
    fetcher: provider,
    submitter: provider,
    evaluator: provider,
    verbose: true,
  });

  txBuilder
    // Spend existing registry node
    .spendingPlutusScriptV3()
    .txIn(nodeToReplace.utxo.input.txHash, nodeToReplace.utxo.input.outputIndex)
    .txInScript(registry_spend.cbor)
    .txInRedeemerValue(conStr0([]), "JSON")
    .txInInlineDatumPresent()

    // Withdrawal from issuer_admin (FES issue logic)
    .withdrawalPlutusScriptV3()
    .withdrawal(issuer_admin.reward_address, "0")
    .withdrawalScript(issuer_admin.cbor)
    .withdrawalRedeemerValue(conStr0([]), "JSON")

    // Mint programmable tokens
    .mintPlutusScriptV3()
    .mint(quantity, prog_token_policyId, stringToHex(assetName))
    .mintingScript(issuance_mint.cbor)
    .mintRedeemerValue(issuanceRedeemer, "JSON")

    // Mint new directory NFT
    .mintPlutusScriptV3()
    .mint("1", registry_mint.policy_id, prog_token_policyId)
    .mintingScript(registry_mint.cbor)
    .mintRedeemerValue(directoryMintRedeemer, "JSON")

    // Output: programmable tokens to recipient
    .txOut(targetAddress, programmableTokenAssets)
    .txOutInlineDatumValue(conStr0([]), "JSON")

    // Output: updated previous registry node
    .txOut(registry_spend.address, directorySpendAssets)
    .txOutInlineDatumValue(previous_node_datum, "JSON")

    // Output: new registry node
    .txOut(registry_spend.address, directoryMintAssets)
    .txOutInlineDatumValue(new_node_datum, "JSON")

    // Reference inputs
    .readOnlyTxInReference(
      protocolParamsUtxo.input.txHash,
      protocolParamsUtxo.input.outputIndex
    )
    .readOnlyTxInReference(
      issuanceUtxo.input.txHash,
      issuanceUtxo.input.outputIndex
    )

    .requiredSignerHash(adminPubKeyHash)
    .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
    .selectUtxosFrom(walletUtxos)
    .setNetwork(getNetworkName())
    .changeAddress(changeAddress);

  console.log("[FES-REG] Step 6 OK: TX body assembled, calling complete()...");

  try {
    const unsignedTx = await txBuilder.complete();
    console.log("[FES-REG] Step 7 OK: complete() returned, unsignedTx length=%d, type=%s",
      unsignedTx?.length, typeof unsignedTx);
    return { unsignedTx, policy_Id: prog_token_policyId };
  } catch (err) {
    console.error("[FES-REG] Step 7 FAILED: complete() threw:", err);
    throw err;
  }
};

export { register_fes_token };
