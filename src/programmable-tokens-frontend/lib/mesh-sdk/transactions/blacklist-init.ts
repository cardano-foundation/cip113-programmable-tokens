import {
  byteString,
  conStr0,
  IWallet,
  MeshTxBuilder,
} from "@meshsdk/core";
import { provider, getNetworkName } from "../config";
import { cip113_scripts_freezeAndSeize } from "../substandard/freeze-and-seize/deploy";
import type {
  ProtocolBootstrapParams,
  SubstandardBlueprint,
} from "../../../types/protocol";

/**
 * Check if a stake address is already registered on-chain.
 * Uses Blockfrost fetchAccountInfo — returns false on 404/error.
 */
async function isStakeRegistered(rewardAddress: string): Promise<boolean> {
  try {
    await provider.fetchAccountInfo(rewardAddress);
    return true;
  } catch {
    return false;
  }
}

/**
 * Build a blacklist initialization transaction for Freeze-and-Seize.
 *
 * This is the Mesh SDK port of Java FreezeAndSeizeHandler.buildBlacklistInitTransaction().
 * - Picks first wallet UTxO as one-shot bootstrap for blacklist_mint parameterization
 * - Mints 1 blacklist NFT (empty token name)
 * - Creates origin node at blacklist_spend address with sentinel datum
 * - Registers stake addresses for issuer_admin and transfer validators (if not yet registered)
 * - Outputs 40 ADA to fee payer (matching backend's chaining-ready output)
 */
const build_blacklist_init = async (
  adminPubKeyHash: string,
  Network_id: 0 | 1,
  wallet: IWallet,
  substandardBlueprint: SubstandardBlueprint,
  params: ProtocolBootstrapParams
) => {
  const changeAddress = await wallet.getChangeAddress();
  const walletUtxos = await wallet.getUtxos();
  const collateral = (await wallet.getCollateral())[0];

  if (!collateral) throw new Error("No collateral available");
  if (!walletUtxos || walletUtxos.length === 0)
    throw new Error("Wallet is empty");

  // Pick first UTxO as bootstrap for blacklist_mint parameterization (one-shot pattern)
  const bootstrapUtxo = walletUtxos[0];

  const fesScripts = new cip113_scripts_freezeAndSeize(
    Network_id,
    substandardBlueprint
  );

  // Parameterize blacklist_mint with bootstrap UTxO + admin pub key hash
  const blacklist_mint = await fesScripts.blacklist_mint(
    {
      txHash: bootstrapUtxo.input.txHash,
      txIndex: bootstrapUtxo.input.outputIndex,
    },
    adminPubKeyHash
  );
  const blacklistNodePolicyId = blacklist_mint.policy_id;

  // Build blacklist_spend address for the origin node output
  const blacklist_spend = await fesScripts.blacklist_spend(
    blacklistNodePolicyId
  );

  // Build issuer_admin and transfer scripts for stake registration
  const issuer_admin = await fesScripts.issuer_admin_withdraw(adminPubKeyHash);
  const transfer = await fesScripts.transfer_withdraw(
    params.programmableLogicBaseParams.scriptHash,
    blacklistNodePolicyId
  );

  // Check which stake addresses need registration
  const stakeAddressesToCheck = [
    issuer_admin.reward_address,
    transfer.reward_address,
  ];
  const needsRegistration: string[] = [];
  for (const addr of stakeAddressesToCheck) {
    const registered = await isStakeRegistered(addr);
    if (!registered) {
      needsRegistration.push(addr);
    }
  }

  // Origin node datum: key="" (sentinel), next="ff"*28 (max sentinel)
  const originNodeDatum = conStr0([
    byteString(""),
    byteString(
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    ),
  ]);

  const txBuilder = new MeshTxBuilder({
    fetcher: provider,
    submitter: provider,
    evaluator: provider,
    verbose: true,
  });

  // Spend the bootstrap UTxO (to make it unique / one-shot)
  txBuilder.txIn(
    bootstrapUtxo.input.txHash,
    bootstrapUtxo.input.outputIndex
  );

  // Mint 1 blacklist NFT (empty token name)
  txBuilder
    .mintPlutusScriptV3()
    .mint("1", blacklistNodePolicyId, "")
    .mintingScript(blacklist_mint.cbor)
    .mintRedeemerValue(conStr0([]), "JSON");

  // Output 1: 40 ADA to fee payer (matching backend's chaining-ready output)
  txBuilder.txOut(changeAddress, [
    { unit: "lovelace", quantity: "40000000" },
  ]);

  // Output 2: origin node at blacklist_spend address with datum + NFT
  txBuilder
    .txOut(blacklist_spend.address, [
      { unit: "lovelace", quantity: "2000000" },
      { unit: blacklistNodePolicyId, quantity: "1" },
    ])
    .txOutInlineDatumValue(originNodeDatum, "JSON");

  // Register stake addresses for issuer_admin and transfer (if not yet registered)
  for (const addr of needsRegistration) {
    txBuilder.registerStakeCertificate(addr);
  }

  txBuilder
    .requiredSignerHash(adminPubKeyHash)
    .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
    .selectUtxosFrom(walletUtxos)
    .setNetwork(getNetworkName())
    .changeAddress(changeAddress);

  const unsignedTx = await txBuilder.complete();

  return {
    unsignedTx,
    blacklistNodePolicyId,
    // Expose the consumed UTxO so the caller can exclude it from TX2's coin selection
    consumedUtxo: {
      txHash: bootstrapUtxo.input.txHash,
      outputIndex: bootstrapUtxo.input.outputIndex,
    },
  };
};

export { build_blacklist_init };
