import { describe, it, expect } from 'vitest';
import { stringToHex, hexToString, prepareMintRequest } from './minting';
import { MintFormData } from '@/types/api';

describe('stringToHex', () => {
  it('should convert simple ASCII string to hex', () => {
    expect(stringToHex('ABC')).toBe('414243');
  });

  it('should convert empty string to empty hex', () => {
    expect(stringToHex('')).toBe('');
  });

  it('should convert string with numbers', () => {
    expect(stringToHex('Token123')).toBe('546f6b656e313233');
  });

  it('should handle special characters', () => {
    expect(stringToHex('Hello World!')).toBe('48656c6c6f20576f726c6421');
  });

  it('should handle multi-byte UTF-8 characters', () => {
    // € is 3 bytes in UTF-8: E2 82 AC
    expect(stringToHex('€')).toBe('e282ac');
  });

  it('should handle emoji (4-byte UTF-8)', () => {
    // 🚀 is 4 bytes in UTF-8: F0 9F 9A 80
    expect(stringToHex('🚀')).toBe('f09f9a80');
  });
});

describe('hexToString', () => {
  it('should convert hex back to ASCII string', () => {
    expect(hexToString('414243')).toBe('ABC');
  });

  it('should convert empty hex to empty string', () => {
    expect(hexToString('')).toBe('');
  });

  it('should handle lowercase hex', () => {
    expect(hexToString('48656c6c6f')).toBe('Hello');
  });

  it('should handle uppercase hex', () => {
    expect(hexToString('48656C6C6F')).toBe('Hello');
  });

  it('should decode multi-byte UTF-8 characters', () => {
    expect(hexToString('e282ac')).toBe('€');
  });

  it('should decode emoji', () => {
    expect(hexToString('f09f9a80')).toBe('🚀');
  });

  it('should be reversible with stringToHex', () => {
    const original = 'Test Token 🎉';
    expect(hexToString(stringToHex(original))).toBe(original);
  });
});

describe('prepareMintRequest', () => {
  const baseFormData: MintFormData = {
    tokenName: 'TestToken',
    quantity: '1000',
    substandardId: 'freeze-and-seize',
    validatorTitle: 'freeze_and_seize_transfer',
  };

  const issuerAddress = 'addr_test1qz...';

  it('should create request with required fields', () => {
    const result = prepareMintRequest(baseFormData, issuerAddress);

    expect(result.issuerBaseAddress).toBe(issuerAddress);
    expect(result.substandardName).toBe('freeze-and-seize');
    expect(result.substandardIssueContractName).toBe('freeze_and_seize_transfer');
    expect(result.quantity).toBe('1000');
  });

  it('should hex-encode the token name', () => {
    const result = prepareMintRequest(baseFormData, issuerAddress);

    // 'TestToken' in hex
    expect(result.assetName).toBe('54657374546f6b656e');
  });

  it('should omit recipientAddress when not provided', () => {
    const result = prepareMintRequest(baseFormData, issuerAddress);

    expect(result.recipientAddress).toBeUndefined();
  });

  it('should include recipientAddress when provided', () => {
    const formDataWithRecipient: MintFormData = {
      ...baseFormData,
      recipientAddress: 'addr_test1recipient...',
    };

    const result = prepareMintRequest(formDataWithRecipient, issuerAddress);

    expect(result.recipientAddress).toBe('addr_test1recipient...');
  });

  it('should handle empty string recipientAddress as undefined', () => {
    const formDataWithEmptyRecipient: MintFormData = {
      ...baseFormData,
      recipientAddress: '',
    };

    const result = prepareMintRequest(formDataWithEmptyRecipient, issuerAddress);

    expect(result.recipientAddress).toBeUndefined();
  });

  it('should correctly encode special characters in token name', () => {
    const formDataWithSpecialName: MintFormData = {
      ...baseFormData,
      tokenName: 'Token€',
    };

    const result = prepareMintRequest(formDataWithSpecialName, issuerAddress);

    // 'Token€' = 546f6b656e + e282ac
    expect(result.assetName).toBe('546f6b656ee282ac');
  });
});
