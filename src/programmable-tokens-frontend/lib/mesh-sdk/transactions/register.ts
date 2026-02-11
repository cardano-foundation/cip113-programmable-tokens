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
import { provider, getNetworkName } from "../config";
import { Cip113_scripts_standard } from "../standard/deploy";
import { cip113_scripts_subStandard } from "../substandard/dummy/deploy";
import {
  ProtocolBootstrapParams,
  ProtocolBlueprint,
  SubstandardBlueprint,
  RegistryDatum,
} from "../../../types/protocol";
import { parseRegistryDatum } from "../../utils/script-utils";
import {
  buildBaseAddress,
  CredentialType,
  deserializeAddress,
  Hash28ByteBase16,
} from "@meshsdk/core-cst";

const register_programmable_tokens = async (
  assetName: string,
  quantity: string,
  params: ProtocolBootstrapParams,
  subStandardName: "issuance" | "transfer",
  Network_id: 0 | 1,
  wallet: IWallet,
  protocolBlueprint: ProtocolBlueprint,
  substandardBlueprint: SubstandardBlueprint,
  recipientAddress?: string | null
) => {
  // Get wallet details
  const changeAddress = await wallet.getChangeAddress();
  const walletUtxos = await wallet.getUtxos();
  const collateral = (await wallet.getCollateral())[0];
  let thirdPartyScriptHash: string;

  if (!collateral) {
    throw new Error("No collateral available");
  }
  if (!walletUtxos) {
    throw new Error("Issuer wallet is empty");
  }

  const standardScript = new Cip113_scripts_standard(Network_id, protocolBlueprint);
  const substandardScript = new cip113_scripts_subStandard(Network_id, substandardBlueprint);

  const registry_spend = await standardScript.registry_spend(params);
  const registry_mint = await standardScript.registry_mint(params);

  const bootstrapTxHash = params.txHash;
  const protocolParamsUtxos = await provider.fetchUTxOs(bootstrapTxHash, 0);

  if (!protocolParamsUtxos) {
    throw new Error("Protocol parameters UTXO not found");
  }

  const issuanceUtxos = await provider.fetchUTxOs(bootstrapTxHash, 2);
  if (!issuanceUtxos) {
    throw new Error("Issuance UTXO not found");
  }

  const protocolParamsUtxo = protocolParamsUtxos[0];
  const issuanceUtxo = issuanceUtxos[0];
  const substandard_issue = await substandardScript.transfer_issue_withdraw();

  const substandard_transfer =
    await substandardScript.transfer_transfer_withdraw();

  if (!substandard_transfer._cbor) {
    throw new Error("Substandard transfer contract not found");
  }

  if (subStandardName === "issuance") {
    thirdPartyScriptHash = substandard_issue.policy_id;
  } else if (subStandardName === "transfer") {
    thirdPartyScriptHash = substandard_transfer.policy_id;
  } else {
    thirdPartyScriptHash = "";
  }

  const issuance_mint = await standardScript.issuance_mint(
    params,
    substandard_issue.policy_id
  );
  const prog_token_policyId = issuance_mint.policy_id;

  const sender_cred = deserializeAddress(
    recipientAddress ? recipientAddress : changeAddress
  ).asBase();
  if (!sender_cred) {
    throw new Error("Sender credential not found");
  }
  const logic_base = await standardScript.programmable_logic_base(params);
  const logic_address = buildBaseAddress(
    Network_id,
    logic_base.policyId as Hash28ByteBase16,
    sender_cred.getStakeCredential().hash,
    CredentialType.ScriptHash,
    CredentialType.KeyHash
  );
  const targetAddress = logic_address.toAddress().toBech32();
  const registryEntries = await provider.fetchAddressUTxOs(
    registry_spend.address
  );

  const registryEntriesDatums = registryEntries.flatMap((utxo: UTxO) =>
    deserializeDatum(utxo.output.plutusData!)
  );

  const existingEntry = registryEntriesDatums
    .map(parseRegistryDatum)
    .filter((d: any): d is RegistryDatum => d !== null)
    .find((d: any) => d.key === prog_token_policyId);

  if (existingEntry) {
    throw new Error(`Token policy ${prog_token_policyId} already registered`);
  }

  // Find node to replace in the linked list
  const nodeToReplaceUtxo = registryEntries.find((utxo: UTxO) => {
    const datum = deserializeDatum(utxo.output.plutusData!);
    const parsedDatum = parseRegistryDatum(datum);

    if (!parsedDatum) {
      return false;
    }

    const after = parsedDatum.key.localeCompare(prog_token_policyId) < 0;
    const before = prog_token_policyId.localeCompare(parsedDatum.next) < 0;

    return after && before;
  });

  if (!nodeToReplaceUtxo) {
    throw new Error("Could not find node to replace");
  }

  const existingRegistryNodeDatum = parseRegistryDatum(
    deserializeDatum(nodeToReplaceUtxo.output.plutusData!)
  );

  if (!existingRegistryNodeDatum) {
    throw new Error("Could not parse current registry node");
  }

  const directoryMintRedeemer = conStr1([
    byteString(prog_token_policyId),
    byteString(substandard_issue.policy_id),
  ]);

  const issuanceRedeemer = conStr0([
    conStr1([byteString(substandard_issue.policy_id)]),
  ]);

  const previous_node_datum = conStr0([
    byteString(existingRegistryNodeDatum.key),
    byteString(prog_token_policyId),
    byteString(existingRegistryNodeDatum.transferScriptHash),
    byteString(existingRegistryNodeDatum.thirdPartyScriptHash),
    byteString(existingRegistryNodeDatum.metadata),
  ]);

  const new_node_datum = conStr0([
    byteString(prog_token_policyId),
    byteString(existingRegistryNodeDatum.next),
    byteString(substandard_transfer.policy_id),
    byteString(thirdPartyScriptHash),
    byteString(""),
  ]);

  const directorySpendAssets: Asset[] = [
    { unit: "lovelace", quantity: "1000000" },
    { unit: registry_mint.policy_id, quantity: "1" },
  ];

  const directoryMintAssets: Asset[] = [
    { unit: "lovelace", quantity: "1000000" },
    { unit: registry_mint.policy_id + prog_token_policyId, quantity: "1" },
  ];

  const programmableTokenAssets: Asset[] = [
    { unit: "lovelace", quantity: "1000000" },
    { unit: prog_token_policyId + stringToHex(assetName), quantity: quantity },
  ];

  const txBuilder = new MeshTxBuilder({
    fetcher: provider,
    submitter: provider,
    evaluator: provider,
    verbose: true,
  });

  const unsignedTx = await txBuilder
    .spendingPlutusScriptV3()
    .txIn(nodeToReplaceUtxo.input.txHash, nodeToReplaceUtxo.input.outputIndex)
    .txInScript(registry_spend.cbor)
    .txInRedeemerValue(conStr0([]), "JSON")
    .txInInlineDatumPresent()

    .withdrawalPlutusScriptV3()
    .withdrawal(substandard_issue.address, "0")
    .withdrawalScript(substandard_issue._cbor)
    .withdrawalRedeemerValue(conStr0([]), "JSON")

    .mintPlutusScriptV3()
    .mint(quantity, prog_token_policyId, stringToHex(assetName))
    .mintingScript(issuance_mint.cbor)
    .mintRedeemerValue(issuanceRedeemer, "JSON")

    .mintPlutusScriptV3()
    .mint("1", registry_mint.policy_id, prog_token_policyId)
    .mintingScript(registry_mint.cbor)
    .mintRedeemerValue(directoryMintRedeemer, "JSON")

    .txOut(targetAddress, programmableTokenAssets)
    .txOutInlineDatumValue(conStr0([]), "JSON")

    .txOut(registry_spend.address, directorySpendAssets)
    .txOutInlineDatumValue(previous_node_datum, "JSON")

    .txOut(registry_spend.address, directoryMintAssets)
    .txOutInlineDatumValue(new_node_datum, "JSON")

    .readOnlyTxInReference(
      protocolParamsUtxo!.input.txHash,
      protocolParamsUtxo!.input.outputIndex
    )
    .readOnlyTxInReference(
      issuanceUtxo!.input.txHash,
      issuanceUtxo!.input.outputIndex
    )
    .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
    .selectUtxosFrom(walletUtxos)
    .setNetwork(getNetworkName())
    .changeAddress(changeAddress)
    .complete();

  return { unsignedTx, policy_Id: prog_token_policyId };
};

export { register_programmable_tokens };
