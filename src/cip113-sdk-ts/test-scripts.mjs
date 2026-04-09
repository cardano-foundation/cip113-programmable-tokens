/**
 * Test: verify SDK script bytes match Java backend's cborHex.
 *
 * The Java backend's "cborHex" field for scripts in the witness set is the
 * double-CBOR-encoded script bytes — what PlutusV3.bytes should contain.
 *
 * Run: node test-scripts.mjs
 */

import { UPLC, Data, Bytes, Script, ScriptHash } from '@evolution-sdk/evolution';
import { PlutusV3 } from '@evolution-sdk/evolution/PlutusV3';

const API_BASE = 'http://localhost:8080/api/v1';

async function fetchJson(path) {
  const res = await fetch(`${API_BASE}${path}`);
  return res.json();
}

async function main() {
  const bootstrap = await fetchJson('/protocol/bootstrap');
  const blueprint = await fetchJson('/protocol/blueprint');

  const plbValidator = blueprint.validators.find(v => v.title === 'programmable_logic_base.programmable_logic_base.spend');
  const plgValidator = blueprint.validators.find(v => v.title === 'programmable_logic_global.programmable_logic_global.withdraw');

  // Parameterize PLG
  const plgParam = Data.bytearray(bootstrap.protocolParams.scriptHash);
  const plgParameterized = UPLC.applyParamsToScript(plgValidator.compiledCode, [plgParam]);

  // Parameterize PLB
  const plbParam = Data.constr(1n, [Data.bytearray(bootstrap.programmableLogicGlobalPrams.scriptHash)]);
  const plbParameterized = UPLC.applyParamsToScript(plbValidator.compiledCode, [plbParam]);

  console.log('=== Encoding levels ===');
  console.log('PLG blueprint:', UPLC.getCborEncodingLevel(plgValidator.compiledCode));
  console.log('PLG parameterized:', UPLC.getCborEncodingLevel(plgParameterized));
  console.log('PLB blueprint:', UPLC.getCborEncodingLevel(plbValidator.compiledCode));
  console.log('PLB parameterized:', UPLC.getCborEncodingLevel(plbParameterized));

  // Expected: applyParamsToScript returns double-CBOR
  // The Java cborHex IS double-CBOR
  // So PlutusV3.bytes should be the double-CBOR bytes
  // When the witness set serializes PlutusV3, it should NOT add another layer

  console.log('\n=== PLG parameterized output ===');
  console.log('Starts:', plgParameterized.slice(0, 30));
  console.log('Length:', plgParameterized.length);

  // The Java expected cborHex for PLG (from user's paste):
  const expectedPLGcborHex = '590a25590a220101003229800aba2aba1aba0aab9faab9eaab9dab9a9bae0024888888896600264653001300900198049805000cdc3a4009300900248889660026004601';
  console.log('\nExpected PLG cborHex starts:', expectedPLGcborHex.slice(0, 30));
  console.log('PLG parameterized starts:    ', plgParameterized.slice(0, 30));
  console.log('MATCH:', plgParameterized.startsWith(expectedPLGcborHex.slice(0, 30)));

  // The expected PLB cborHex:
  const expectedPLBcborHex = '58b458b20101003229800aba2aba1aab9eaab9dab9a4888896600264646644b30013370e900118031baa0018994c004c02400660126014003225980099baf3009300b00100e8a51';
  console.log('\nExpected PLB cborHex starts:', expectedPLBcborHex.slice(0, 30));
  console.log('PLB parameterized starts:    ', plbParameterized.slice(0, 30));
  console.log('MATCH:', plbParameterized.startsWith(expectedPLBcborHex.slice(0, 30)));

  if (plgParameterized.startsWith(expectedPLGcborHex.slice(0, 30)) &&
      plbParameterized.startsWith(expectedPLBcborHex.slice(0, 30))) {
    console.log('\n✅ applyParamsToScript output matches expected cborHex!');
    console.log('PlutusV3.bytes should contain the applyParamsToScript output AS-IS.');
    console.log('The witness set serialization should NOT add another CBOR layer.');
  } else {
    console.log('\n❌ Mismatch — need to investigate further.');
  }

  // Now test: what does new PlutusV3({ bytes }) produce?
  console.log('\n=== PlutusV3 construction ===');
  const plgScript = new PlutusV3({ bytes: Bytes.fromHex(plgParameterized) });
  console.log('PLG PlutusV3.bytes hex starts:', Bytes.toHex(plgScript.bytes).slice(0, 30));
  console.log('PLG PlutusV3.bytes length:', plgScript.bytes.length);

  // The witness set stores PlutusV3 scripts as CBOR bytestrings.
  // So the serialization does: CBOR.encode(PlutusV3.bytes) which adds one CBOR layer.
  // If PlutusV3.bytes = double-CBOR, then serialized = triple-CBOR ← WRONG
  // If PlutusV3.bytes = single-CBOR, then serialized = double-CBOR ← CORRECT (matches Java)

  // Strip one layer from the double-CBOR parameterized output
  const raw = Bytes.fromHex(plgParameterized);
  const ai = raw[0] & 0x1f;
  const skip = ai < 24 ? 1 : ai === 24 ? 2 : ai === 25 ? 3 : 5;
  const singleCborBytes = raw.slice(skip);
  const singleCborHex = Bytes.toHex(singleCborBytes);

  console.log('\nSingle-CBOR (stripped outer) starts:', singleCborHex.slice(0, 30));
  console.log('Expected inner starts:              ', expectedPLGcborHex.slice(6, 36));
  // expectedPLGcborHex = "590a25" + "590a22..." = outer(inner)
  // After stripping outer "590a25", inner = "590a22..."
  const expectedInner = expectedPLGcborHex.slice(6);
  console.log('Match inner:', singleCborHex.startsWith(expectedInner.slice(0, 20)));

  // Conclusion: PlutusV3.bytes should be the SINGLE-CBOR version
  // The witness set adds one more layer → producing double-CBOR → matches Java
  const plgCorrect = new PlutusV3({ bytes: singleCborBytes });
  console.log('\n=== Correct PlutusV3 (single-CBOR bytes) ===');
  console.log('bytes hex starts:', Bytes.toHex(plgCorrect.bytes).slice(0, 30));

  // Verify: Script.toCBORHex should now match [3, doubleCbor]
  const cddl = Script.toCBORHex(plgCorrect);
  console.log('Script.toCBORHex starts:', cddl.slice(0, 30));
  // Expected CDDL: "8203" + expectedPLGcborHex (= [3, double-CBOR])
  const expectedCDDL = '8203' + expectedPLGcborHex;
  console.log('Expected CDDL starts:    ', expectedCDDL.slice(0, 30));
  console.log('CDDL MATCH:', cddl.startsWith(expectedCDDL.slice(0, 30)));
}

main().catch(console.error);
