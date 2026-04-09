/**
 * Integration test: FES blacklist init + token registration via CIP-113 SDK.
 *
 * Uses tx chaining: build both txs, sign both, submit in order.
 * Follows Evolution SDK docs: build() → SignBuilder → chainResult() → sign() → submit()
 *
 * Run: node test-fes-init.mjs
 */
import { readFileSync, writeFileSync } from 'fs';
import {
  CIP113,
  evoClient,
  previewChain,
  EvoAddress,
  EvoTransactionHash,
  paymentCredentialHash,
  stringToHex,
} from './dist/index.js';
import { Assets } from '@evolution-sdk/evolution';
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

console.log('=== FES Registration — SDK Integration Test ===\n');

// =====================================================================
// 1. Create Evolution SDK signing client
// =====================================================================
const client = evoClient(previewChain)
  .withBlockfrost({ projectId: BF_KEY, baseUrl: BF_URL })
  .withSeed({ mnemonic: SEED, accountIndex: 0 });

const address = await client.address();
const walletAddress = EvoAddress.toBech32(address);
const adminPkh = paymentCredentialHash(walletAddress);
console.log('Wallet:', walletAddress);
console.log('Admin PKH:', adminPkh);

// =====================================================================
// 2. Fetch blueprints + bootstrap from backend
// =====================================================================
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

// =====================================================================
// 3. Init CIP-113 protocol
// =====================================================================
const protocol = CIP113.init({
  client,
  standard: { blueprint: standardBp, deployment },
  substandards: [],
});
console.log('Protocol initialized');

// =====================================================================
// 4. Get bootstrap UTxO — pick largest ADA UTxO
// =====================================================================
const walletUtxos = await client.getWalletUtxos();
console.log('Wallet UTxOs:', walletUtxos.length);
for (const u of walletUtxos) {
  console.log('  ', EvoTransactionHash.toHex(u.transactionId), '#', Number(u.index),
    ' ADA:', Number(Assets.lovelaceOf(u.assets)) / 1_000_000);
}
if (walletUtxos.length === 0) {
  console.error('No UTxOs! Fund the wallet.');
  process.exit(1);
}

const bootstrapUtxo = walletUtxos.reduce((best, u) =>
  Assets.lovelaceOf(u.assets) > Assets.lovelaceOf(best.assets) ? u : best
);
const blacklistInitTxInput = {
  txHash: EvoTransactionHash.toHex(bootstrapUtxo.transactionId),
  outputIndex: Number(bootstrapUtxo.index),
};
console.log('Bootstrap UTxO:', blacklistInitTxInput.txHash, '#', blacklistInitTxInput.outputIndex);

// =====================================================================
// 5. Pre-compute blacklistNodePolicyId + create FES substandard
// =====================================================================
const assetName = 'TestFES' + Date.now().toString(36);
const assetNameHex = stringToHex(assetName);
const tempFesScripts = createFESScripts(fesSdkBp);
const blacklistMintScript = tempFesScripts.buildBlacklistMint(blacklistInitTxInput, adminPkh);
const blacklistNodePolicyId = blacklistMintScript.hash;
console.log('Asset name:', assetName);
console.log('Blacklist policy ID:', blacklistNodePolicyId);

const fes = freezeAndSeizeSubstandard({
  blueprint: fesSdkBp,
  deployment: { adminPkh, assetName: assetNameHex, blacklistNodePolicyId, blacklistInitTxInput },
});

fes.init({
  client,
  standardScripts: protocol.scripts,
  deployment,
  network: 'preview',
  checkStakeRegistration: async (stakeAddress) => {
    try {
      const res = await fetch(`${BACKEND}/script-registration/check?stakeAddress=${encodeURIComponent(stakeAddress)}`);
      if (!res.ok) return false;
      const data = await res.json();
      return data.isRegistered === true;
    } catch {
      return false;
    }
  },
});
console.log('FES substandard initialized\n');

// =====================================================================
// 6. BUILD blacklist init tx
// =====================================================================
console.log('--- Step 1: Build blacklist init tx ---');
const initResult = await fes.initCompliance({
  feePayerAddress: walletAddress,
  adminAddress: walletAddress,
  assetName,
  bootstrapUtxo,
});

console.log('Init tx built successfully');
console.log('  CBOR length:', initResult.cbor.length);
console.log('  txHash:', initResult.txHash);
console.log('  blacklistNodePolicyId:', initResult.metadata?.blacklistNodePolicyId);
console.log('  chainAvailable UTxOs:', initResult.chainAvailable?.length ?? 0);
writeFileSync('test-output-init-cbor.hex', initResult.cbor);
console.log('  CBOR written to test-output-init-cbor.hex');

// =====================================================================
// 7. BUILD registration tx — chained from init
// =====================================================================
console.log('\n--- Step 2: Build registration tx (chained from init) ---');
const regResult = await fes.register({
  feePayerAddress: walletAddress,
  assetName,
  quantity: 1_000_000_000n,
  config: { adminPkh, blacklistNodePolicyId },
  chainedUtxos: initResult.chainAvailable,
});

console.log('Registration tx built successfully');
console.log('  CBOR length:', regResult.cbor.length);
console.log('  txHash:', regResult.txHash);
console.log('  tokenPolicyId:', regResult.tokenPolicyId);
writeFileSync('test-output-reg-cbor.hex', regResult.cbor);
console.log('  CBOR written to test-output-reg-cbor.hex');

// =====================================================================
// 8. SIGN both txs (before any submission)
// =====================================================================
console.log('\n--- Step 3: Sign both transactions ---');
const initSubmitBuilder = await initResult._signBuilder.sign();
console.log('Init tx signed');

const regSubmitBuilder = await regResult._signBuilder.sign();
console.log('Registration tx signed');

// =====================================================================
// 9. SUBMIT init tx
// =====================================================================
console.log('\n--- Step 4: Submit init tx ---');
const initTxId = await initSubmitBuilder.submit();
const initTxHash = typeof initTxId === 'string' ? initTxId
  : initTxId?.hash ? Array.from(initTxId.hash).map(b => b.toString(16).padStart(2, '0')).join('')
  : String(initTxId);
console.log('Init tx submitted to network. TxHash:', initTxHash);

// =====================================================================
// 10. Wait for init tx confirmation
// =====================================================================
console.log('\n--- Step 5: Waiting for init tx on-chain confirmation ---');
for (let attempt = 1; attempt <= 30; attempt++) {
  try {
    const res = await fetch(`${BF_URL}/txs/${initTxHash}`, {
      headers: { 'project_id': BF_KEY },
    });
    if (res.ok) {
      console.log(`Init tx confirmed on-chain (attempt ${attempt})`);
      break;
    }
  } catch {}
  if (attempt === 30) {
    console.error('Init tx not confirmed after 5 minutes. Aborting.');
    process.exit(1);
  }
  process.stdout.write(`  Polling ${attempt}/30...`);
  await new Promise(r => setTimeout(r, 10000));
  process.stdout.write(' done\n');
}

// =====================================================================
// 11. SUBMIT registration tx
// =====================================================================
console.log('\n--- Step 6: Submit registration tx ---');
try {
  const regTxId = await regSubmitBuilder.submit();
  const regTxHash = typeof regTxId === 'string' ? regTxId
    : regTxId?.hash ? Array.from(regTxId.hash).map(b => b.toString(16).padStart(2, '0')).join('')
    : String(regTxId);
  console.log('Registration tx submitted to network. TxHash:', regTxHash);

  // Wait for reg tx confirmation
  console.log('\n--- Step 7: Waiting for registration tx on-chain confirmation ---');
  for (let attempt = 1; attempt <= 30; attempt++) {
    try {
      const res = await fetch(`${BF_URL}/txs/${regTxHash}`, {
        headers: { 'project_id': BF_KEY },
      });
      if (res.ok) {
        console.log(`Registration tx confirmed on-chain (attempt ${attempt})`);
        break;
      }
    } catch {}
    if (attempt === 30) {
      console.log('Registration tx not confirmed after 5 minutes (may still be pending).');
      break;
    }
    process.stdout.write(`  Polling ${attempt}/30...`);
    await new Promise(r => setTimeout(r, 10000));
    process.stdout.write(' done\n');
  }

  console.log('\n=== SUCCESS ===');
  console.log('Token registered!');
  console.log('  Token policy ID:', regResult.tokenPolicyId);
  console.log('  Blacklist policy ID:', blacklistNodePolicyId);
  console.log('  Init tx:', initTxHash);
  console.log('  Reg tx:', regTxHash);

} catch (e) {
  console.error('Registration tx submission FAILED:', e?.message);
  let cause = e?.cause;
  let depth = 0;
  while (cause && depth < 10) {
    console.error(`  cause[${depth}]:`, cause?.message?.slice(0, 500) ?? JSON.stringify(cause)?.slice(0, 500));
    cause = cause?.cause;
    depth++;
  }

  // Fallback: submit the reg tx CBOR directly to Blockfrost for raw error
  console.log('\n--- Fallback: direct Blockfrost submit for raw error ---');
  try {
    // regResult.cbor is the unsigned CBOR — we need to submit the SIGNED version
    // The signBuilder was already consumed by sign() above, but the signed CBOR
    // should be available from the regSubmitBuilder
    // SubmitBuilder converts internally — let's just re-submit the regResult.cbor
    // after manually signing
    const submitRes = await fetch(`${BF_URL}/tx/submit`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/cbor', 'project_id': BF_KEY },
      body: Buffer.from(regResult.cbor, 'hex'),
    });
    console.log('Blockfrost status:', submitRes.status);
    console.log('Blockfrost response:', await submitRes.text());
  } catch (e2) {
    console.error('Fallback also failed:', e2?.message?.slice(0, 300));
  }
}

console.log('\n=== Test Complete ===');
