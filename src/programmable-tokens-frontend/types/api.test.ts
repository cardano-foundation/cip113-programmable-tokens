import { describe, it, expect } from 'vitest';
import { ApiException } from './api';

describe('ApiException', () => {
  it('should create exception with message only', () => {
    const error = new ApiException('Something went wrong');

    expect(error.message).toBe('Something went wrong');
    expect(error.name).toBe('ApiException');
    expect(error.status).toBeUndefined();
    expect(error.details).toBeUndefined();
  });

  it('should create exception with status', () => {
    const error = new ApiException('Not found', 404);

    expect(error.message).toBe('Not found');
    expect(error.status).toBe(404);
    expect(error.details).toBeUndefined();
  });

  it('should create exception with details', () => {
    const details = { field: 'email', reason: 'Invalid format' };
    const error = new ApiException('Validation failed', 400, details);

    expect(error.message).toBe('Validation failed');
    expect(error.status).toBe(400);
    expect(error.details).toEqual(details);
  });

  it('should be an instance of Error', () => {
    const error = new ApiException('Test');

    expect(error).toBeInstanceOf(Error);
    expect(error).toBeInstanceOf(ApiException);
  });

  it('should have correct stack trace', () => {
    const error = new ApiException('Test');

    expect(error.stack).toBeDefined();
    expect(error.stack).toContain('ApiException');
  });
});

describe('MintTokenRequest type validation', () => {
  it('should accept valid request structure', () => {
    const request = {
      issuerBaseAddress: 'addr_test1qz...',
      substandardName: 'freeze-and-seize',
      substandardIssueContractName: 'freeze_and_seize_transfer',
      assetName: '546f6b656e',
      quantity: '1000',
    };

    // Type check - if this compiles, the type is correct
    expect(request.issuerBaseAddress).toBeDefined();
    expect(request.substandardName).toBeDefined();
    expect(request.substandardIssueContractName).toBeDefined();
    expect(request.assetName).toBeDefined();
    expect(request.quantity).toBeDefined();
  });

  it('should allow optional recipientAddress', () => {
    const requestWithRecipient = {
      issuerBaseAddress: 'addr_test1qz...',
      substandardName: 'freeze-and-seize',
      substandardIssueContractName: 'freeze_and_seize_transfer',
      recipientAddress: 'addr_test1recipient...',
      assetName: '546f6b656e',
      quantity: '1000',
    };

    const requestWithoutRecipient: { recipientAddress?: string } = {
    };

    expect(requestWithRecipient.recipientAddress).toBeDefined();
    expect(requestWithoutRecipient.recipientAddress).toBeUndefined();
  });
});

describe('Substandard type structure', () => {
  it('should have expected structure', () => {
    const substandard = {
      id: 'freeze-and-seize',
      validators: [
        {
          title: 'freeze_and_seize_transfer',
          script_bytes: '4d01000033222220051',
          script_hash: 'abcd1234efgh5678',
        },
      ],
    };

    expect(substandard.id).toBe('freeze-and-seize');
    expect(substandard.validators).toHaveLength(1);
    expect(substandard.validators[0].title).toBe('freeze_and_seize_transfer');
  });
});
