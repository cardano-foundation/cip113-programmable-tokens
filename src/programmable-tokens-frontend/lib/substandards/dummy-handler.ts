/**
 * Dummy Substandard Handler for client-side transaction building
 * Ports the Java DummySubstandardHandler.buildMintTransaction logic to TypeScript
 */

import { Transaction, mConStr0, mConStr1, MeshTxBuilder } from '@meshsdk/core';
import type { IWallet } from '@meshsdk/core';
import type { ProtocolBootstrapParams, ProtocolBlueprint, SubstandardBlueprint } from '@/types/protocol';
import { buildIssuanceMintScript } from '../protocol-script-builder';
import { createPlutusScript, getScriptHash, resolveRewardAddress } from '../script-utils';

export interface MintTransactionParams {
  assetName: string;
  quantity: string;
  issuerBaseAddress: string;
  recipientAddress?: string;
  substandardName: string;
  substandardIssueContractName: string;
}

/**
 * Build a mint transaction for dummy substandard tokens
 *
 * @param params - Mint transaction parameters
 * @param protocolParams - Protocol bootstrap parameters
 * @param protocolBlueprint - Protocol blueprint with validators
 * @param substandardBlueprint - Substandard blueprint with validators
 * @param wallet - Connected wallet
 * @returns Unsigned transaction hex
 */
export async function buildDummyMintTransaction(
  params: MintTransactionParams,
  protocolParams: ProtocolBootstrapParams,
  protocolBlueprint: ProtocolBlueprint,
  substandardBlueprint: SubstandardBlueprint,
  wallet: IWallet
): Promise<string> {
  try {
    // Get issuer UTXOs
    const issuerUtxos = await wallet.getUtxos();
    if (!issuerUtxos || issuerUtxos.length === 0) {
      throw new Error('Issuer wallet is empty');
    }

    // Get substandard issue contract
    const substandardIssueValidatorData = substandardBlueprint.validators.find(
      v => v.title === params.substandardIssueContractName
    );

    if (!substandardIssueValidatorData) {
      throw new Error(`Substandard issue contract not found: ${params.substandardIssueContractName}`);
    }

    // Create PlutusScript from validator bytes
    const substandardIssueScript = createPlutusScript(
      substandardIssueValidatorData.script_bytes,
      'V3'
    );

    // Get substandard issue reward address
    const substandardIssueAddress = resolveRewardAddress(
      substandardIssueScript.code,
      substandardIssueScript.version
    );

    console.log('Substandard issue address:', substandardIssueAddress);

    // Build parameterized issuance mint script
    const issuanceScript = buildIssuanceMintScript(
      protocolParams,
      substandardIssueScript,
      protocolBlueprint
    );

    const issuanceScriptHash = getScriptHash(issuanceScript);
    console.log('Issuance script hash:', issuanceScriptHash);

    // Build issuance redeemer: constr(0, [constr(1, [bytes(substandardIssueScriptHash)])])
    const issuanceRedeemer: any = {
      data: mConStr0([
        mConStr1([getScriptHash(substandardIssueScript)])
      ])
    };

    // Determine recipient address
    const recipient = params.recipientAddress || params.issuerBaseAddress;

    // Build target address using programmable logic base script hash + recipient's delegation credential
    // For now, use the recipient address directly
    // TODO: Derive proper hybrid address (script payment + delegation credential)
    const targetAddress = recipient;

    // Build the transaction using the lower-level MeshTxBuilder for Plutus script withdrawals
    const txBuilder = new MeshTxBuilder();

    // Step 1: Withdrawal from substandard issue validator (must be first for script context)
    txBuilder
      .withdrawalPlutusScriptV3()
      .withdrawal(substandardIssueAddress, '0') // Zero withdrawal
      .withdrawalScript(substandardIssueScript.code)
      .withdrawalRedeemerValue(100); // BigIntPlutusData(100)

    // Step 2: Mint the programmable token
    const policyId = getScriptHash(issuanceScript);
    txBuilder
      .mintPlutusScriptV3()
      .mint(params.quantity, policyId, params.assetName)
      .mintingScript(issuanceScript.code)
      .mintRedeemerValue(issuanceRedeemer.data);

    // Step 3: Send minted token to recipient
    txBuilder
      .txOut(targetAddress, [
        { unit: 'lovelace', quantity: '2000000' }, // Min ADA
        { unit: `${policyId}${params.assetName}`, quantity: params.quantity }
      ])
      .txOutInlineDatumValue(mConStr0([])); // Empty datum (constr(0, []))

    // Set change address
    txBuilder.changeAddress(params.issuerBaseAddress);

    // Complete the transaction
    const unsignedTx = await txBuilder.complete();

    return unsignedTx;
  } catch (error) {
    console.error('Failed to build mint transaction:', error);
    throw error;
  }
}
