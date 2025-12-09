/**
 * Simple Node.js script to test script parameterization
 * Run with: node test-parameterization.js
 */

const fs = require('fs');
const path = require('path');

// Import MeshSDK functions
const { applyCborEncoding, applyParamsToScript, resolveScriptHash, mConStr1, byteString } = require('@meshsdk/core');

// Load test fixtures
const protocolBootstrap = JSON.parse(
  fs.readFileSync(path.join(__dirname, '__tests__/fixtures/protocol-bootstrap.json'), 'utf8')
);
const protocolBlueprint = JSON.parse(
  fs.readFileSync(path.join(__dirname, '__tests__/fixtures/protocol-blueprint.json'), 'utf8')
);
const dummySubstandard = JSON.parse(
  fs.readFileSync(path.join(__dirname, '__tests__/fixtures/dummy-substandard.json'), 'utf8')
);

// Expected hashes from backend
const EXPECTED_SUBSTANDARD_ISSUE_HASH = '0f8107a024cfbc7e5e787d67acddcec748ceb280fcc4b14c305e6a2d';
const EXPECTED_ISSUANCE_HASH = '8428ae12aba2b64dc79b1c09d49b753852fe5bb544d1f4104eeb0c6c';

console.log('=== Testing Script Parameterization ===\n');

// Test 1: Substandard issue contract hash
console.log('Test 1: Substandard Issue Contract Hash');
console.log('----------------------------------------');

const substandardIssueValidator = dummySubstandard.validators.find(
  v => v.title === 'transfer.issue.withdraw'
);

if (!substandardIssueValidator) {
  console.error('ERROR: Substandard issue validator not found');
  process.exit(1);
}

console.log('Raw script bytes (first 100 chars):', substandardIssueValidator.script_bytes.substring(0, 100));

// Apply CBOR encoding to raw script
const substandardIssueScriptEncoded = applyCborEncoding(substandardIssueValidator.script_bytes);
console.log('CBOR encoded (first 100 chars):', substandardIssueScriptEncoded.substring(0, 100));

// Get script hash
const substandardIssueScriptHash = resolveScriptHash(substandardIssueScriptEncoded, 'V3');
console.log('Computed hash:', substandardIssueScriptHash);
console.log('Expected hash:', EXPECTED_SUBSTANDARD_ISSUE_HASH);
console.log('Match:', substandardIssueScriptHash === EXPECTED_SUBSTANDARD_ISSUE_HASH ? '✅' : '❌');

// Test 2: Parameterized issuance mint contract hash
console.log('\nTest 2: Parameterized Issuance Mint Contract Hash');
console.log('--------------------------------------------------');

const programmableLogicBaseScriptHash = protocolBootstrap.programmableLogicBaseParams.scriptHash;
console.log('Programmable logic base hash:', programmableLogicBaseScriptHash);
console.log('Substandard issue script hash:', substandardIssueScriptHash);

// Build parameters using MeshSDK helper functions
const params = [
  mConStr1([programmableLogicBaseScriptHash]),
  mConStr1([substandardIssueScriptHash])
];

console.log('Parameters (using mConStr1):', JSON.stringify(params, null, 2));

// Get issuance mint contract from blueprint
const issuanceMintValidator = protocolBlueprint.validators.find(
  v => v.title === 'issuance_mint.issuance_mint.mint'
);

if (!issuanceMintValidator) {
  console.error('ERROR: Issuance mint validator not found');
  process.exit(1);
}

console.log('Issuance mint script (first 100 chars):', issuanceMintValidator.compiledCode.substring(0, 100));

try {
  // Apply CBOR encoding first
  const issuanceScriptEncoded = applyCborEncoding(issuanceMintValidator.compiledCode);
  console.log('CBOR encoded issuance script (first 100 chars):', issuanceScriptEncoded.substring(0, 100));

  // Apply parameters
  const parameterizedScript = applyParamsToScript(issuanceScriptEncoded, params);
  console.log('Parameterized script (first 100 chars):', parameterizedScript.substring(0, 100));

  // Get hash of parameterized script
  const issuanceScriptHash = resolveScriptHash(parameterizedScript, 'V3');
  console.log('Computed hash:', issuanceScriptHash);
  console.log('Expected hash:', EXPECTED_ISSUANCE_HASH);
  console.log('Match:', issuanceScriptHash === EXPECTED_ISSUANCE_HASH ? '✅' : '❌');

  console.log('\n=== Test Complete ===');

  if (substandardIssueScriptHash === EXPECTED_SUBSTANDARD_ISSUE_HASH &&
      issuanceScriptHash === EXPECTED_ISSUANCE_HASH) {
    console.log('✅ All tests passed!');
    process.exit(0);
  } else {
    console.log('❌ Some tests failed');
    process.exit(1);
  }
} catch (error) {
  console.error('\nERROR during parameterization:', error.message);
  console.error(error.stack);
  process.exit(1);
}
