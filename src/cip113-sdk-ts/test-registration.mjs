/**
 * Integration test: FES registration flow on Preview testnet.
 *
 * Tests: initCompliance → register → verify on-chain
 *
 * Run: node test-registration.mjs
 *
 * Requires:
 * - .env.test with TEST_SEED_PHRASE, BLOCKFROST_API_KEY
 * - Backend running on localhost:8080 (for blueprint/bootstrap fetch)
 * - Funded wallet on Preview testnet
 */

import { readFileSync } from 'fs';
import {
  client as evoClient,
  Data,
  Bytes,
  Address,
  Transaction,
  ScriptHash,
  UPLC,
} from '@evolution-sdk/evolution';
import {
  preview as previewChain,
} from '@evolution-sdk/evolution/sdk/client/Chain';

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

if (!SEED) throw new Error('TEST_SEED_PHRASE not set in .env.test');
if (!BF_KEY) throw new Error('BLOCKFROST_API_KEY not set in .env.test');

console.log('=== CIP-113 FES Registration Test ===\n');

// 1. Create Evolution SDK client
console.log('1. Creating Evolution SDK client...');
const evoClientInstance = evoClient(previewChain)
  .withBlockfrost({ projectId: BF_KEY, baseUrl: BF_URL })
  .withSeed({ mnemonic: SEED, accountIndex: 0 });

const address = await evoClientInstance.address();
console.log('   Wallet address:', Address.toBech32(address));

// Check balance
const utxos = await evoClientInstance.getWalletUtxos();
console.log('   UTxOs:', utxos.length);
if (utxos.length === 0) {
  console.error('   ❌ No UTxOs! Fund this address from the Preview faucet:');
  console.error('   https://docs.cardano.org/cardano-testnets/tools/faucet/');
  process.exit(1);
}

const totalLovelace = utxos.reduce((acc, u) => {
  // Try to get lovelace from assets
  let lovelace = 0n;
  try {
    // Evolution v2 assets format
    if (typeof u.assets === 'bigint') lovelace = u.assets;
    else if (u.assets?.lovelace) lovelace = BigInt(u.assets.lovelace);
  } catch {}
  return acc + lovelace;
}, 0n);
console.log('   Total lovelace: ~', Number(totalLovelace) / 1_000_000, 'ADA');

// 2. Fetch protocol data from backend
console.log('\n2. Fetching protocol data from backend...');
let bootstrap, blueprint;
try {
  const bpRes = await fetch(`${BACKEND}/protocol/blueprint`);
  blueprint = await bpRes.json();
  console.log('   Blueprint validators:', blueprint.validators.length);

  const bsRes = await fetch(`${BACKEND}/protocol/bootstrap`);
  bootstrap = await bsRes.json();
  console.log('   Bootstrap txHash:', bootstrap.txHash);
  console.log('   PLB hash:', bootstrap.programmableLogicBaseParams.scriptHash);
} catch (e) {
  console.error('   ❌ Backend not reachable:', e.message);
  console.error('   Make sure the Java backend is running on localhost:8080');
  process.exit(1);
}

// 3. Test: Build a simple tx to verify the wallet works
console.log('\n3. Testing simple tx build...');
try {
  const simpleTx = await evoClientInstance
    .newTx()
    .payToAddress({
      address,
      assets: { lovelace: 2_000_000n },
    })
    .build();

  const simpleCbor = Transaction.toCBORHex(await simpleTx.toTransaction());
  console.log('   ✅ Simple tx built successfully, CBOR length:', simpleCbor.length);
} catch (e) {
  console.error('   ❌ Simple tx build failed:', e.message?.slice(0, 100));
}

// 4. Test: Initialize the CIP-113 SDK via the adapter
console.log('\n4. Initializing CIP-113 SDK...');

// Import our SDK
const { CIP113 } = await import('./dist/index.js');
const { evolutionAdapter } = await import('./dist/provider/evolution-adapter.js');
const { freezeAndSeizeSubstandard } = await import('./dist/substandards/freeze-and-seize/index.js');

// Fetch FES blueprint
const fesRes = await fetch(`${BACKEND}/substandards/freeze-and-seize`);
const fesBlueprint = await fesRes.json();
console.log('   FES blueprint validators:', fesBlueprint.validators.length);

// Create adapter
const adapter = evolutionAdapter({
  network: 'preview',
  provider: { type: 'blockfrost', projectId: BF_KEY, baseUrl: BF_URL },
  wallet: { type: 'seed', mnemonic: SEED, accountIndex: 0 },
});

const walletAddress = Address.toBech32(address);
console.log('   Adapter created for:', walletAddress);

// Get wallet UTxOs via adapter
const adapterUtxos = await adapter.getUtxos(walletAddress);
console.log('   Adapter UTxOs:', adapterUtxos.length);

// Get admin PKH
const adminPkh = adapter.paymentCredentialHash(walletAddress);
console.log('   Admin PKH:', adminPkh);

// Build deployment params from bootstrap
function toDeploymentParams(bp) {
  return {
    txHash: bp.txHash,
    protocolParams: {
      txInput: bp.protocolParams.txInput,
      policyId: bp.protocolParams.scriptHash,
      alwaysFailScriptHash: bp.protocolParams.alwaysFailScriptHash,
    },
    programmableLogicGlobal: {
      policyId: bp.programmableLogicGlobalPrams.scriptHash,
      scriptHash: bp.programmableLogicGlobalPrams.scriptHash,
    },
    programmableLogicBase: {
      scriptHash: bp.programmableLogicBaseParams.scriptHash,
    },
    issuance: {
      txInput: bp.issuanceParams.txInput,
      policyId: bp.issuanceParams.scriptHash,
      alwaysFailScriptHash: bp.issuanceParams.alwaysFailScriptHash,
    },
    directoryMint: {
      txInput: bp.directoryMintParams.txInput,
      issuanceScriptHash: bp.directoryMintParams.issuanceScriptHash,
      scriptHash: bp.directoryMintParams.scriptHash,
    },
    directorySpend: {
      policyId: bp.directorySpendParams.scriptHash,
      scriptHash: bp.directorySpendParams.scriptHash,
    },
    programmableBaseRefInput: bp.programmableBaseRefInput,
    programmableGlobalRefInput: bp.programmableGlobalRefInput,
  };
}

function toSdkBlueprint(bp) {
  return {
    preamble: bp.preamble ?? { title: "standard", version: "0.3.0" },
    validators: bp.validators.map(v => ({
      title: v.title,
      compiledCode: v.compiledCode,
      hash: v.hash,
    })),
  };
}

function substandardToSdkBlueprint(bp) {
  return {
    preamble: { title: bp.id, version: "0.1.0" },
    validators: bp.validators.map(v => ({
      title: v.title,
      compiledCode: v.script_bytes,
      hash: v.script_hash,
    })),
  };
}

const deploymentParams = toDeploymentParams(bootstrap);
const standardBp = toSdkBlueprint(blueprint);
const fesSdkBp = substandardToSdkBlueprint(fesBlueprint);

// Create a temp FES substandard with bootstrap UTxO
const bootstrapUtxo = adapterUtxos[0];
const blacklistInitTxInput = {
  txHash: bootstrapUtxo.txHash,
  outputIndex: bootstrapUtxo.outputIndex,
};

const assetName = 'TestFES' + Date.now().toString(36); // Unique name
const assetNameHex = Buffer.from(assetName).toString('hex');
console.log('   Asset name:', assetName, '(hex:', assetNameHex, ')');

// Initialize protocol first (needed for standardScripts)
const protocol = CIP113.init({
  adapter,
  standard: {
    blueprint: standardBp,
    deployment: deploymentParams,
  },
  substandards: [],
});

// Pre-compute blacklistNodePolicyId (deterministic from bootstrap UTxO + admin PKH)
const { createFESScripts } = await import('./dist/substandards/freeze-and-seize/scripts.js');
const tempFesScripts = createFESScripts(fesSdkBp, adapter);
const blacklistMintScript = tempFesScripts.buildBlacklistMint(blacklistInitTxInput, adminPkh);
const blacklistNodePolicyId = blacklistMintScript.hash;
console.log('   Blacklist policy (pre-computed):', blacklistNodePolicyId);

// Create FES substandard with the CORRECT blacklistNodePolicyId
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
  adapter,
  standardScripts: protocol.scripts,
  deployment: deploymentParams,
  network: 'preview',
});

console.log('   ✅ SDK initialized');

// 5. Build blacklist init tx
console.log('\n5. Building blacklist init tx...');
try {
  const initResult = await fes.initCompliance({
    feePayerAddress: walletAddress,
    adminAddress: walletAddress,
    assetName,
    skipStakeRegistration: true, // Handle separately — Conway-era requires separate cert tx
  });

  console.log('   ✅ Blacklist init tx built!');
  console.log('   CBOR length:', initResult.cbor.length);
  console.log('   Blacklist policy:', initResult.metadata?.blacklistNodePolicyId);

  // 6. Sign and submit
  console.log('\n6. Signing blacklist init tx...');
  const signedInit = await evoClientInstance.signTx(initResult.cbor);
  console.log('   ✅ Signed, witness length:', signedInit.length);

  // Assemble
  const { assembleSignedTx } = await import('./dist/provider/tx-utils.js');
  const assembledInit = assembleSignedTx(initResult.cbor, signedInit);
  console.log('   Assembled tx length:', assembledInit.length);

  console.log('\n7. Submitting blacklist init tx...');
  const initHash = await evoClientInstance.submitTx(assembledInit);
  console.log('   ✅ Submitted! TxHash:', initHash);

} catch (e) {
  console.error('   ❌ Failed:', e.message);
  if (e.cause) console.error('   Cause:', e.cause?.message?.slice(0, 200));
  if (e.issue) console.error('   Issue:', JSON.stringify(e.issue, null, 2)?.slice(0, 500));
}

console.log('\n=== Test Complete ===');
