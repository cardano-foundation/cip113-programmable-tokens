/**
 * Dummy Substandard Handler for client-side transaction building
 * Ports the Java DummySubstandardHandler.buildMintTransaction logic to TypeScript
 */

import { Transaction } from '@meshsdk/core';
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
      data: {
        alternative: 0,
        fields: [
          {
            alternative: 1,
            fields: [{ bytes: getScriptHash(substandardIssueScript) }]
          }
        ]
      }
    };

    // Determine recipient address
    const recipient = params.recipientAddress || params.issuerBaseAddress;

    // Build target address (programmable logic base + recipient's delegation credential)
    // For now, we'll use the recipient address directly
    // TODO: Implement proper address derivation with script payment credential
    const targetAddress = recipient;

    // Build the transaction
    const tx = new Transaction({ initiator: wallet });

    // Add issuer UTXOs as inputs
    issuerUtxos.forEach(utxo => {
      tx.sendLovelace(utxo.input.txHash, params.issuerBaseAddress);
    });

    // Mint the programmable token
    const mintAsset = {
      assetName: params.assetName,
      assetQuantity: params.quantity,
      metadata: {},
      label: '721' as `${number}`,
      recipient: targetAddress
    };

    tx.mintAsset(
      issuanceScript,
      mintAsset,
      issuanceRedeemer
    );

    // Withdraw from substandard issue validator (proof of authorization)
    // Note: The withdrawRewards API may differ - this is a placeholder
    // TODO: Verify correct MeshSDK withdrawRewards signature
    tx.withdrawRewards(
      substandardIssueAddress,
      '0' // Zero withdrawal
    );

    // Set change address
    tx.setChangeAddress(params.issuerBaseAddress);

    // Build unsigned transaction
    const unsignedTx = await tx.build();

    return unsignedTx;
  } catch (error) {
    console.error('Failed to build mint transaction:', error);
    throw error;
  }
}
