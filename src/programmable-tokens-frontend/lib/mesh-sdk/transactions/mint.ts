import {
  Asset,
  byteString,
  conStr0,
  conStr1,
  integer,
  IWallet,
  MeshTxBuilder,
  stringToHex,
} from "@meshsdk/core";
import {
  buildBaseAddress,
  CredentialType,
  deserializeAddress,
  Hash28ByteBase16,
} from "@meshsdk/core-cst";

import { provider } from "../config";
import { Cip113_scripts_standard } from "../standard/deploy";
import { cip113_scripts_subStandard } from "../substandard/dummy/deploy";
import { ProtocolBootstrapParams } from "../../../types/protocol";

const mint_programmable_tokens = async (
  params: ProtocolBootstrapParams,
  assetName: string,
  quantity: string,
  Network_id: 0 | 1,
  wallet: IWallet,
  recipientAddress?: string | null
) => {
  const changeAddress = await wallet.getChangeAddress();
  const walletUtxos = await wallet.getUtxos();
  const collateral = (await wallet.getCollateral())[0];

  if (!collateral) {
    throw new Error("No collateral available");
  }

  if (!walletUtxos) {
    throw new Error("Issuer wallet is empty");
  }

  const standardScript = new Cip113_scripts_standard(Network_id);
  const substandardScript = new cip113_scripts_subStandard(Network_id);

  const substandard_issue = await substandardScript.transfer_issue_withdraw();

  if (!substandard_issue.address) {
    throw new Error("Substandard issuance address not found");
  }

  const issuance_mint = await standardScript.issuance_mint(
    params,
    substandard_issue.policy_id
  );
  const sender_cred = deserializeAddress(
    recipientAddress ? recipientAddress : changeAddress
  ).asBase();
  if (!sender_cred) {
    throw new Error("Sender credential not found");
  }
  const logic_base = await standardScript.programmable_logic_base(params);
  const logic_address = buildBaseAddress(
    0,
    logic_base.policyId as Hash28ByteBase16,
    sender_cred.getStakeCredential().hash,
    CredentialType.ScriptHash,
    CredentialType.KeyHash
  );
  const address = logic_address.toAddress().toBech32();

  const issuanceRedeemer = conStr0([
    conStr1([byteString(substandard_issue.policy_id)]),
  ]);

  const programmableTokenAssets: Asset[] = [
    { unit: "lovelace", quantity: "1500000" },
    {
      unit: issuance_mint.policy_id + stringToHex(assetName),
      quantity: quantity,
    },
  ];

  const programmableTokenDatum = conStr0([]);

  const txBuilder = new MeshTxBuilder({
    fetcher: provider,
    submitter: provider,
    verbose: true,
  });
  const unsignedTx = await txBuilder
    .withdrawalPlutusScriptV3()
    .withdrawal(substandard_issue.address, "0")
    .withdrawalScript(substandard_issue._cbor)
    .withdrawalRedeemerValue(integer(100), "JSON")

    .mintPlutusScriptV3()
    .mint(quantity, issuance_mint.policy_id, stringToHex(assetName))
    .mintingScript(issuance_mint.cbor)
    .mintRedeemerValue(issuanceRedeemer, "JSON")

    .txOut(address, programmableTokenAssets)
    .txOutInlineDatumValue(programmableTokenDatum, "JSON")

    .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
    .selectUtxosFrom(walletUtxos)
    .setNetwork("preview")
    .changeAddress(changeAddress)
    .complete();

  return unsignedTx;
};

export { mint_programmable_tokens };
