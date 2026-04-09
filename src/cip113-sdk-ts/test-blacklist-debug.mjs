/**
 * Bare-metal blacklist init test — uses Evolution SDK directly, no CIP-113 SDK layer.
 * This isolates the issue to: script parameterization, tx construction, or evaluation.
 *
 * Run: node test-blacklist-debug.mjs
 */
import { readFileSync } from 'fs';
import {
  client as evoClient,
  Data,
  Bytes,
  Address,
  AddressEras,
  Transaction,
  ScriptHash,
  UPLC,
  Assets,
  InlineDatum,
  EnterpriseAddress,
  TransactionHash,
} from '@evolution-sdk/evolution';
import {
  preview as previewChain,
} from '@evolution-sdk/evolution/sdk/client/Chain';
import { PlutusV3 } from '@evolution-sdk/evolution/PlutusV3';

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

console.log('=== Blacklist Init — Bare-Metal Evolution SDK Test ===\n');

// =====================================================================
// 1. Create Evolution client
// =====================================================================
const evo = evoClient(previewChain)
  .withBlockfrost({ projectId: BF_KEY, baseUrl: BF_URL })
  .withSeed({ mnemonic: SEED, accountIndex: 0 });

const address = await evo.address();
const walletAddress = Address.toBech32(address);
console.log('Wallet:', walletAddress);

// Get wallet UTxOs
const utxos = await evo.getWalletUtxos();
console.log('UTxOs:', utxos.length);
if (utxos.length === 0) {
  console.error('No UTxOs! Fund the wallet first.');
  process.exit(1);
}

// Admin PKH from address
const addrHex = Address.toHex(address);
// Payment credential starts at byte 1 (after header byte), 28 bytes = 56 hex chars
const adminPkh = addrHex.slice(2, 58);
console.log('Admin PKH:', adminPkh);

// =====================================================================
// 2. Fetch blueprint from backend
// =====================================================================
const fesRes = await fetch(`${BACKEND}/substandards/freeze-and-seize`);
const fesBlueprint = await fesRes.json();
console.log('FES validators:', fesBlueprint.validators.length);

// Find validator by title
function findValidator(title) {
  const v = fesBlueprint.validators.find(v => v.title === title);
  if (!v) throw new Error(`Validator not found: ${title}`);
  return v;
}

const blacklistMintValidator = findValidator('blacklist_mint.blacklist_mint.mint');
const blacklistSpendValidator = findValidator('blacklist_spend.blacklist_spend.spend');
console.log('Blacklist mint code length:', blacklistMintValidator.script_bytes.length);
console.log('Blacklist spend code length:', blacklistSpendValidator.script_bytes.length);

// =====================================================================
// 3. Parameterize scripts
// =====================================================================
const bootstrapUtxo = utxos[0];
const bootstrapTxHashHex = TransactionHash.toHex(bootstrapUtxo.transactionId);
const bootstrapIdx = bootstrapUtxo.index;
console.log('\nBootstrap UTxO:', bootstrapTxHashHex, '#', bootstrapIdx);

// Build OutputReference: Constr(0, [bytes(txHash), int(idx)])
const outputRef = Data.constr(0n, [
  Data.bytearray(bootstrapTxHashHex),
  Data.int(BigInt(bootstrapIdx)),
]);

// Build admin_pkh: just raw bytes
const adminPkhData = Data.bytearray(adminPkh);

// Apply params to blacklist_mint
const parameterizedMintCode = UPLC.applyParamsToScript(
  blacklistMintValidator.script_bytes,
  [outputRef, adminPkhData]
);
console.log('Parameterized mint code CBOR level:', UPLC.getCborEncodingLevel(parameterizedMintCode));

// Build PlutusV3 script for the mint policy
function buildScript(compiledCode) {
  const level = UPLC.getCborEncodingLevel(compiledCode);
  if (level === 'double') {
    const raw = Bytes.fromHex(compiledCode);
    const ai = raw[0] & 0x1f;
    const skip = ai < 24 ? 1 : ai === 24 ? 2 : ai === 25 ? 3 : 5;
    const innerBytes = raw.slice(skip);
    return new PlutusV3({ bytes: innerBytes });
  }
  return new PlutusV3({ bytes: Bytes.fromHex(compiledCode) });
}

const mintScript = buildScript(parameterizedMintCode);
const mintPolicyId = ScriptHash.fromScript(mintScript);
const mintPolicyIdHex = ScriptHash.toHex(mintPolicyId);
console.log('Blacklist mint policy ID:', mintPolicyIdHex);

// Parameterize blacklist_spend with mint policy ID
const parameterizedSpendCode = UPLC.applyParamsToScript(
  blacklistSpendValidator.script_bytes,
  [Data.bytearray(mintPolicyIdHex)]
);
const spendScript = buildScript(parameterizedSpendCode);
const spendScriptHash = ScriptHash.fromScript(spendScript);
const spendScriptHashHex = ScriptHash.toHex(spendScriptHash);
console.log('Blacklist spend script hash:', spendScriptHashHex);

// Compute blacklist spend address (enterprise/script address)
const spendEntAddr = new EnterpriseAddress.EnterpriseAddress({ networkId: 0, paymentCredential: spendScriptHash });
const spendAddressBech32 = AddressEras.toBech32(spendEntAddr);
const spendAddress = Address.fromBech32(spendAddressBech32);
console.log('Blacklist spend address:', spendAddressBech32);

// =====================================================================
// 4. Build origin node datum
// =====================================================================
const MAX_NEXT = 'ff'.repeat(30);
const originDatum = Data.constr(0n, [
  Data.bytearray(''),        // key = empty
  Data.bytearray(MAX_NEXT),  // next = max
]);
console.log('\nOrigin datum:', JSON.stringify(originDatum, (_, v) => typeof v === 'bigint' ? v.toString() : v));

// =====================================================================
// 5. Build mint redeemer
// =====================================================================
const initRedeemer = Data.constr(0n, []); // BlacklistInit

// =====================================================================
// 6. Build mint assets
// =====================================================================
// Origin NFT: policyId + empty asset name, qty = 1
let mintAssets = Assets.fromLovelace(0n);
mintAssets = Assets.addByHex(mintAssets, mintPolicyIdHex, '', 1n);
mintAssets = Assets.withoutLovelace(mintAssets);
console.log('Mint assets units:', Assets.getUnits(mintAssets));

// =====================================================================
// 7. Build output value for origin node
// =====================================================================
let originValue = Assets.fromLovelace(1_300_000n);
originValue = Assets.addByHex(originValue, mintPolicyIdHex, '', 1n);
console.log('Origin output units:', Assets.getUnits(originValue));

// =====================================================================
// 8. Build transaction
// =====================================================================
console.log('\n--- Building transaction ---');
try {
  const tx = evo
    .newTx()
    .collectFrom({ inputs: utxos.slice(0, 3) })
    .mintAssets({ assets: mintAssets, redeemer: initRedeemer })
    .payToAddress({
      address,
      assets: Assets.fromLovelace(40_000_000n),
    })
    .payToAddress({
      address: spendAddress,
      assets: originValue,
      datum: new InlineDatum.InlineDatum({ data: originDatum }),
    })
    .attachScript({ script: mintScript })
    .build({ changeAddress: address, availableUtxos: utxos });

  const built = await tx;
  const txObj = await built.toTransaction();
  const cbor = Transaction.toCBORHex(txObj);
  console.log('TX CBOR length:', cbor.length);
  console.log('TX CBOR (first 200):', cbor.slice(0, 200));

  // Sign and submit
  console.log('\n--- Signing ---');
  const signed = await built.sign.withWallet().complete();
  const signedTx = await signed.toTransaction();
  const signedCbor = Transaction.toCBORHex(signedTx);
  console.log('Signed CBOR length:', signedCbor.length);

  console.log('\n--- Submitting ---');
  const hash = await signed.submit();
  console.log('Submitted! TxHash:', hash);

} catch (e) {
  console.error('Build/submit FAILED:', e?.message);

  // Walk the error cause chain
  let cause = e?.cause;
  let depth = 0;
  while (cause && depth < 10) {
    console.error(`  cause[${depth}]:`, cause?.message ?? JSON.stringify(cause));
    // Check for Blockfrost response body
    if (cause?.body) console.error('  body:', JSON.stringify(cause.body)?.slice(0, 500));
    if (cause?.response) console.error('  response:', JSON.stringify(cause.response)?.slice(0, 500));
    cause = cause?.cause;
    depth++;
  }

  // Try with dummy evaluator to get CBOR
  console.log('\n--- Retrying with dummy evaluator ---');
  try {
    const { Effect } = await import('effect');

    const tx = evo
      .newTx()
      .collectFrom({ inputs: utxos.slice(0, 3) })
      .mintAssets({ assets: mintAssets, redeemer: initRedeemer })
      .payToAddress({
        address,
        assets: Assets.fromLovelace(40_000_000n),
      })
      .payToAddress({
        address: spendAddress,
        assets: originValue,
        datum: new InlineDatum.InlineDatum({ data: originDatum }),
      })
      .attachScript({ script: mintScript });

    const either = await tx.buildEither({
      changeAddress: address,
      availableUtxos: utxos,
      evaluator: {
        evaluate: (rawTx) => {
          try {
            console.log('Dummy eval tx CBOR:', Transaction.toCBORHex(rawTx));
          } catch {}
          // Return dummy redeemer for the mint
          return Effect.succeed([{
            redeemer_tag: 'mint',
            redeemer_index: 0,
            ex_units: { mem: 14000000n, steps: 10000000000n },
          }]);
        },
      },
    });

    if (either._tag === 'Right') {
      const txObj = await either.right.toTransaction();
      const cbor = Transaction.toCBORHex(txObj);
      console.log('Dummy-eval CBOR length:', cbor.length);

      // Now evaluate via Blockfrost directly
      console.log('\n--- Evaluating CBOR via Blockfrost API ---');
      const evalRes = await fetch(`${BF_URL}/utils/txs/evaluate`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/cbor',
          'project_id': BF_KEY,
        },
        body: Buffer.from(cbor, 'hex'),
      });
      const evalResult = await evalRes.json();
      console.log('Blockfrost evaluate:', JSON.stringify(evalResult, null, 2));
    } else {
      console.error('Dummy-eval build also failed:', either.left?.message);
    }
  } catch (e2) {
    console.error('Dummy evaluator failed:', e2?.message);
  }
}

console.log('\n=== Test Complete ===');
