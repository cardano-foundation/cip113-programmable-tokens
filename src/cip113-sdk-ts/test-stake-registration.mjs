/**
 * Test: Stake address registration via Evolution SDK.
 *
 * Test 1: Register a key-based stake credential (sanity check)
 * Test 2: Register a script-based stake credential using RegCert + redeemer + attached script
 *         (uses the FES issuerAdmin validator which has publish handler → True)
 *
 * Run: node test-stake-registration.mjs
 */
import { readFileSync } from 'fs';
import {
  client as evoClient,
  Data,
  Bytes,
  Address,
  Transaction,
  Credential,
  ScriptHash,
  UPLC,
  TransactionHash,
} from '@evolution-sdk/evolution';
import { preview as previewChain } from '@evolution-sdk/evolution/sdk/client/Chain';
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

const evo = evoClient(previewChain)
  .withBlockfrost({ projectId: BF_KEY, baseUrl: BF_URL })
  .withSeed({ mnemonic: SEED, accountIndex: 0 });

const address = await evo.address();
const walletAddress = Address.toBech32(address);
const addrHex = Address.toHex(address);
const adminPkh = addrHex.slice(2, 58);
console.log('Wallet:', walletAddress);
console.log('Admin PKH:', adminPkh);

// Read FES blueprint from local Aiken build output
const fesBlueprint = JSON.parse(readFileSync('../substandards/freeze-and-seize/plutus.json', 'utf-8'));

function findValidator(title) {
  const v = fesBlueprint.validators.find(v => v.title === title);
  if (!v) throw new Error(`Validator not found: ${title}`);
  return v;
}

// Build the issuerAdmin script (parameterized with adminPkh + a dummy assetName)
const issuerAdminValidator = findValidator('example_transfer_logic.issuer_admin_contract.withdraw');
console.log('Using local blueprint, issuerAdmin base hash:', issuerAdminValidator.hash);
const assetNameHex = Buffer.from('StakeRegTest').toString('hex');

// Parameterize: [Credential(Key, adminPkh), bytes(assetNameHex)]
const issuerAdminCode = UPLC.applyParamsToScript(
  issuerAdminValidator.compiledCode,
  [
    Data.constr(0n, [Data.bytearray(adminPkh)]),  // Key credential
    Data.bytearray(assetNameHex),
  ]
);

// Build PlutusV3 script
function buildScript(compiledCode) {
  const level = UPLC.getCborEncodingLevel(compiledCode);
  if (level === 'double') {
    const raw = Bytes.fromHex(compiledCode);
    const ai = raw[0] & 0x1f;
    const skip = ai < 24 ? 1 : ai === 24 ? 2 : ai === 25 ? 3 : 5;
    return new PlutusV3({ bytes: raw.slice(skip) });
  }
  return new PlutusV3({ bytes: Bytes.fromHex(compiledCode) });
}

const issuerAdminScript = buildScript(issuerAdminCode);
const issuerAdminHash = ScriptHash.toHex(ScriptHash.fromScript(issuerAdminScript));
console.log('IssuerAdmin script hash:', issuerAdminHash);

// =====================================================================
// TEST: Script-based stake credential registration with RegCert
// =====================================================================
console.log('\n=== TEST: Script-based RegCert (redeemer + script attached) ===');
try {
  const scriptCred = Credential.makeScriptHash(Bytes.fromHex(issuerAdminHash));
  console.log('Credential:', scriptCred._tag, issuerAdminHash);

  const built = await evo.newTx()
    .registerStake({
      stakeCredential: scriptCred,
      redeemer: Data.constr(0n, []),
    })
    .attachScript({ script: issuerAdminScript })
    .build();

  const unsignedTx = await built.toTransaction();
  const unsignedCbor = Transaction.toCBORHex(unsignedTx);
  console.log('BUILD OK, CBOR length:', unsignedCbor.length);

  const txHash = await built.signAndSubmit();
  console.log('SUBMITTED! TxHash:', txHash);
} catch (e) {
  console.log('FAILED:', e?.message?.slice(0, 400));
  let cause = e?.cause;
  let depth = 0;
  while (cause && depth < 5) {
    console.log(`  cause[${depth}]:`, cause?.message?.slice(0, 300) ?? JSON.stringify(cause)?.slice(0, 300));
    cause = cause?.cause;
    depth++;
  }
}

console.log('\n=== Test Complete ===');
