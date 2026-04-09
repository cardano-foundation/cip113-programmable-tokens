/**
 * Integration test: FES blacklist init via CIP-113 SDK.
 *
 * Uses the SDK directly — no custom code, no frontend context.
 *
 * Run: node test-fes-init.mjs
 */
import { readFileSync } from 'fs';
import {
  CIP113,
  evoClient,
  previewChain,
  EvoAddress,
  EvoTransactionHash,
  EvoTransaction,
  paymentCredentialHash,
  stringToHex,
} from './dist/index.js';
import { freezeAndSeizeSubstandard, createFESScripts } from './dist/substandards/freeze-and-seize/index.js';

// Load env
const env = Object.fromEntries(
  readFileSync('.env.test', 'utf-8')
    .split('\n')
    .filter(l => l && !l.startsWith('#'))
    .map(l => {
      const [k, ...v] = l.split('=');
      return [k.trim(), v.join('=').trim().replace(/^"|"$/g, '')];
    })
);

const SEED = env.TEST_SEED_PHRASE;
const BF_KEY = env.BLOCKFROST_API_KEY;
const BF_URL = env.BLOCKFROST_URL;
const BACKEND = env.BACKEND_API;

console.log('=== FES Blacklist Init — SDK Integration Test ===\n');

// 1. Create Evolution SDK signing client
const client = evoClient(previewChain)
  .withBlockfrost({ projectId: BF_KEY, baseUrl: BF_URL })
  .withSeed({ mnemonic: SEED, accountIndex: 0 });

const address = await client.address();
const walletAddress = EvoAddress.toBech32(address);
const adminPkh = paymentCredentialHash(walletAddress);
console.log('Wallet:', walletAddress);
console.log('Admin PKH:', adminPkh);

// 2. Fetch blueprints + bootstrap from backend
const [bpRes, bsRes, fesRes] = await Promise.all([
  fetch(`${BACKEND}/protocol/blueprint`),
  fetch(`${BACKEND}/protocol/bootstrap`),
  fetch(`${BACKEND}/substandards/freeze-and-seize`),
]);
const blueprint = await bpRes.json();
const bootstrap = await bsRes.json();
const fesBlueprint = await fesRes.json();

function toDeploymentParams(bp) {
  return {
    txHash: bp.txHash,
    protocolParams: { txInput: bp.protocolParams.txInput, policyId: bp.protocolParams.scriptHash, alwaysFailScriptHash: bp.protocolParams.alwaysFailScriptHash },
    programmableLogicGlobal: { policyId: bp.programmableLogicGlobalPrams.scriptHash, scriptHash: bp.programmableLogicGlobalPrams.scriptHash },
    programmableLogicBase: { scriptHash: bp.programmableLogicBaseParams.scriptHash },
    issuance: { txInput: bp.issuanceParams.txInput, policyId: bp.issuanceParams.scriptHash, alwaysFailScriptHash: bp.issuanceParams.alwaysFailScriptHash },
    directoryMint: { txInput: bp.directoryMintParams.txInput, issuanceScriptHash: bp.directoryMintParams.issuanceScriptHash, scriptHash: bp.directoryMintParams.scriptHash },
    directorySpend: { policyId: bp.directorySpendParams.scriptHash, scriptHash: bp.directorySpendParams.scriptHash },
    programmableBaseRefInput: bp.programmableBaseRefInput,
    programmableGlobalRefInput: bp.programmableGlobalRefInput,
  };
}

function toSdkBlueprint(bp) {
  return {
    preamble: bp.preamble ?? { title: 'standard', version: '0.3.0' },
    validators: bp.validators.map(v => ({ title: v.title, compiledCode: v.compiledCode, hash: v.hash })),
  };
}

function substandardToSdkBlueprint(bp) {
  return {
    preamble: { title: bp.id, version: '0.1.0' },
    validators: bp.validators.map(v => ({ title: v.title, compiledCode: v.script_bytes, hash: v.script_hash })),
  };
}

const deployment = toDeploymentParams(bootstrap);
const standardBp = toSdkBlueprint(blueprint);
const fesSdkBp = substandardToSdkBlueprint(fesBlueprint);

// 3. Init CIP-113 protocol
const protocol = CIP113.init({
  client,
  standard: { blueprint: standardBp, deployment },
  substandards: [],
});
console.log('Protocol initialized');

// 4. Get bootstrap UTxO (first wallet UTxO)
const walletUtxos = await client.getWalletUtxos();
console.log('Wallet UTxOs:', walletUtxos.length);
if (walletUtxos.length === 0) {
  console.error('No UTxOs! Fund the wallet.');
  process.exit(1);
}

const bootstrapUtxo = walletUtxos[0];
const blacklistInitTxInput = {
  txHash: EvoTransactionHash.toHex(bootstrapUtxo.transactionId),
  outputIndex: Number(bootstrapUtxo.index),
};
console.log('Bootstrap UTxO:', blacklistInitTxInput.txHash, '#', blacklistInitTxInput.outputIndex);

// 5. Pre-compute blacklistNodePolicyId
const assetName = 'TestFES' + Date.now().toString(36);
const assetNameHex = stringToHex(assetName);
const tempFesScripts = createFESScripts(fesSdkBp);
const blacklistMintScript = tempFesScripts.buildBlacklistMint(blacklistInitTxInput, adminPkh);
const blacklistNodePolicyId = blacklistMintScript.hash;
console.log('Asset name:', assetName);
console.log('Blacklist policy ID:', blacklistNodePolicyId);

// 6. Create FES substandard
const fes = freezeAndSeizeSubstandard({
  blueprint: fesSdkBp,
  deployment: {
    adminPkh,
    assetName: assetNameHex,
    blacklistNodePolicyId,
    blacklistInitTxInput,
  },
});

fes.init({
  client,
  standardScripts: protocol.scripts,
  deployment,
  network: 'preview',
});
console.log('FES substandard initialized');

// 7. Build blacklist init tx
console.log('\n--- Building blacklist init tx ---');
try {
  const initResult = await fes.initCompliance({
    feePayerAddress: walletAddress,
    adminAddress: walletAddress,
    assetName,
    bootstrapUtxo,
  });

  console.log('Init CBOR length:', initResult.cbor.length);
  console.log('Init txHash:', initResult.txHash);
  console.log('Blacklist policy:', initResult.metadata?.blacklistNodePolicyId);
  console.log('Chain available UTxOs:', initResult.chainAvailable?.length ?? 0);

  // 8. Sign and submit — use signBuilder if available, otherwise manual
  console.log('\n--- Signing and submitting ---');
  if (initResult._signBuilder) {
    // Direct sign+submit via Evolution SDK SignBuilder
    const txHash = await initResult._signBuilder.signAndSubmit();
    console.log('SUBMITTED! TxHash:', txHash);
  } else {
    // Manual: sign CBOR hex, assemble, submit
    const witnessSet = await client.signTx(initResult.cbor);
    // signTx returns TransactionWitnessSet — need to serialize and assemble
    console.log('signTx returned:', typeof witnessSet, witnessSet?._tag);
    console.log('TODO: need signBuilder flow for seed wallets');
  }

} catch (e) {
  console.error('FAILED:', e?.message);
  let cause = e?.cause;
  let depth = 0;
  while (cause && depth < 5) {
    console.error(`  cause[${depth}]:`, cause?.message?.slice(0, 300) ?? JSON.stringify(cause)?.slice(0, 300));
    cause = cause?.cause;
    depth++;
  }
}

console.log('\n=== Test Complete ===');
