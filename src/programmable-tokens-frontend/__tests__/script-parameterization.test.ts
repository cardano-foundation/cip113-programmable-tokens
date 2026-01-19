/**
 * Unit test for script parameterization
 * Verifies that we can correctly parameterize Plutus scripts and get expected hashes
 */

import { createPlutusScript, getScriptHash } from '../lib/script-utils';
import { buildIssuanceMintScript } from '../lib/protocol-script-builder';
import type { ProtocolBootstrapParams, ProtocolBlueprint, SubstandardBlueprint } from '../types/protocol';
import protocolBootstrapData from './fixtures/protocol-bootstrap.json';
import protocolBlueprintData from './fixtures/protocol-blueprint.json';
import dummySubstandardData from './fixtures/dummy-substandard.json';

describe('Script Parameterization', () => {
  const protocolBootstrap = protocolBootstrapData as ProtocolBootstrapParams;
  const protocolBlueprint = protocolBlueprintData as ProtocolBlueprint;
  const dummySubstandard = dummySubstandardData as SubstandardBlueprint;

  // Expected hashes from backend
  const EXPECTED_SUBSTANDARD_ISSUE_HASH = '0f8107a024cfbc7e5e787d67acddcec748ceb280fcc4b14c305e6a2d';
  const EXPECTED_SUBSTANDARD_ISSUE_ADDRESS = 'stake_test17q8czpaqyn8mclj70p7k0txaemr53n4jsr7vfv2vxp0x5tgnq7hem';
  const EXPECTED_ISSUANCE_HASH = '8428ae12aba2b64dc79b1c09d49b753852fe5bb544d1f4104eeb0c6c';

  test('substandard issue contract hash matches backend', () => {
    // Get the substandard issue validator from dummy substandard
    const substandardIssueValidator = dummySubstandard.validators.find(
      v => v.title === 'transfer.issue.withdraw'
    );

    expect(substandardIssueValidator).toBeDefined();

    // Create PlutusScript and get hash
    const substandardIssueScript = createPlutusScript(
      substandardIssueValidator!.script_bytes,
      'V3'
    );

    const scriptHash = getScriptHash(substandardIssueScript);

    console.log('Substandard issue script hash:', scriptHash);
    console.log('Expected hash:', EXPECTED_SUBSTANDARD_ISSUE_HASH);

    expect(scriptHash).toBe(EXPECTED_SUBSTANDARD_ISSUE_HASH);
  });

  test('parameterized issuance mint contract hash matches backend', () => {
    // Get the substandard issue validator
    const substandardIssueValidator = dummySubstandard.validators.find(
      v => v.title === 'transfer.issue.withdraw'
    );

    expect(substandardIssueValidator).toBeDefined();

    // Create PlutusScript for substandard issue validator
    const substandardIssueScript = createPlutusScript(
      substandardIssueValidator!.script_bytes,
      'V3'
    );

    console.log('\n--- Building Issuance Mint Script ---');
    console.log('Protocol params programmableLogicBaseParams:', protocolBootstrap.programmableLogicBaseParams);
    console.log('Substandard issue script hash:', getScriptHash(substandardIssueScript));

    // Build parameterized issuance mint script
    const issuanceScript = buildIssuanceMintScript(
      protocolBootstrap,
      substandardIssueScript,
      protocolBlueprint
    );

    const issuanceScriptHash = getScriptHash(issuanceScript);

    console.log('Issuance script hash:', issuanceScriptHash);
    console.log('Expected hash:', EXPECTED_ISSUANCE_HASH);

    expect(issuanceScriptHash).toBe(EXPECTED_ISSUANCE_HASH);
  });
});
