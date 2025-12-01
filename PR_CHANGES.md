# Pull Request: Frontend Fixes for Browser Compatibility and Validation

## Summary
This PR addresses critical issues in the frontend application related to browser compatibility and input validation, plus a type safety fix in the backend.

## Changes

### 1. Replace Node.js `Buffer` with Browser-Native APIs
**File:** `src/programmable-tokens-frontend/lib/api/minting.ts`

- **Issue:** The code was using `Buffer.from()` for hex encoding/decoding. `Buffer` is a Node.js API and is not available in the browser environment (client-side components), causing runtime errors.
- **Fix:** Replaced `Buffer` usage with `TextEncoder` and `TextDecoder` APIs, which are standard in modern browsers and fully supported in the Next.js client environment.

### 2. Fix Token Name Validation
**File:** `src/programmable-tokens-frontend/components/mint/mint-form.tsx`

- **Issue:** The validation logic checked `tokenName.length > 32`. In Cardano, asset names are limited to 32 **bytes**, not characters. Multi-byte characters (e.g., emojis, accented characters) could pass the character length check but exceed the byte limit, leading to on-chain transaction failures.
- **Fix:** Updated the validation to check the byte length of the UTF-8 encoded string using `new TextEncoder().encode(tokenName).length`.

### 3. Fix Type Safety in `DirectorySetNode.java`
**File:** `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/model/DirectorySetNode.java`

- **Issue:** The `DirectorySetNode` record was using `String` for `transferLogicScript` and `issuerLogicScript`, with `FIXME` comments indicating they should be `Credential` objects.
- **Fix:** Updated the record fields to use `Credential` type and updated the `fromInlineDatum` method to parse the hex strings into `Credential` objects using `Credential.fromScript()`. This improves type safety and aligns with the domain model.

### 4. Update Unit Test for `DirectorySetNode`
**File:** `src/programmable-tokens-offchain-java/src/test/java/org/cardanofoundation/cip113/model/DirectorySetNodeTest.java`

- **Issue:** The test was creating `DirectorySetNode` instances with `String` parameters, which no longer compile after the type change to `Credential`.
- **Fix:** Updated the test to use `Credential.fromScript()` and compare using `getBytes()` for proper credential comparison.

### 5. Documentation Updates
**File:** `src/programmable-tokens-frontend/PHASE4-MINTING-PLAN.md`

- **Issue:** The documentation contained a `TODO` for defining minting endpoints, which were already implemented.
- **Fix:** Updated the documentation to reflect the implemented endpoints (`/api/v1/issue-token/mint` and `/api/v1/issue-token/register`) and marked the section as "Implemented".

### 6. Replace Debug Print with Proper Logging
**File:** `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/model/DirectorySetNode.java`

- **Issue:** The code contained a `System.out.println(json)` debug statement that should not be in production code. Also, the catch block was silently swallowing exceptions.
- **Fix:** Replaced with proper SLF4J logging using `log.debug()` and added `log.warn()` for exception handling. The class already has `@Slf4j` annotation, so the logger was available.

### 7. Improve Logging in ProtocolParamsParser
**File:** `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/model/onchain/ProtocolParamsParser.java`

- **Issue:** The code was using `log.info("jsonData: {}", jsonData)` for debug output (too verbose for INFO level) and `log.warn("error", e)` with a non-descriptive message.
- **Fix:** Changed debug output to `log.debug()` level and improved exception message to be more descriptive: `"Failed to parse protocol params from inline datum: {}"`.

## Verification
- ✅ Frontend lint: `npm run lint` - No ESLint warnings or errors
- ✅ Frontend TypeScript: `npx tsc --noEmit` - No type errors
- ✅ Frontend build: `npm run build` - Completes successfully
- ✅ Backend compile: `./gradlew compileJava` - Completes successfully
- ✅ DirectorySetNodeTest: `./gradlew test --tests "*.DirectorySetNodeTest"` - Passes
- ✅ Verified no `Buffer` usage remains in frontend source code

**Note:** Some pre-existing test failures exist in `RegistryServiceTest`, `AddressUtilTest`, and `BalanceValueHelperTest` (H2 database and address parsing issues). These are unrelated to the changes in this PR and were failing before these changes.

### 8. Config-Driven Bootstrap UTxO References
**Files:**
- `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/model/bootstrap/ProtocolBootstrapParams.java`
- `src/programmable-tokens-offchain-java/src/main/resources/protocolBootstrap.json`
- `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/controller/IssueTokenController.java`

- **Issue:** The `IssueTokenController` had hardcoded UTxO output indices (0, 1, 2) when looking up protocol params, directory, and issuance UTxOs. This made deployments fragile across different environments.
- **Fix:**
  - Extended `ProtocolBootstrapParams` record to include `protocolParamsUtxo`, `directoryUtxo`, and `issuanceUtxo` as `TxInput` objects
  - Updated `protocolBootstrap.json` to include the new UTxO references
  - Refactored all three endpoint methods (`/register`, `/mint`, `/issue`) to read UTxO references from config instead of hardcoding indices
  - Removed TODO comments that were addressed

### 9. Input Ordering Documentation in Aiken Validator
**File:** `src/programmable-tokens-onchain-aiken/validators/programmable_logic_global.ak`

- **Issue:** TODO comment suggested adding input ordering checks, but the existing `node.key == cs` validation already ensures proper ordering.
- **Fix:** Updated the comment to document how ordering is implicitly validated through:
  1. Lexicographic ordering of currency symbols in Aiken's pairs
  2. The `node.key == cs` check in `validate_single_cs` ensuring proofs match currency symbols

### 10. Test Fixture Documentation
**Files:**
- `src/programmable-tokens-offchain-java/src/test/java/org/cardanofoundation/cip113/DirectoryMintTest.java`
- `src/programmable-tokens-offchain-java/src/test/java/org/cardanofoundation/cip113/ProtocolParamsMintTest.java`
- `src/programmable-tokens-offchain-java/src/test/java/org/cardanofoundation/cip113/ProtocolDeploymentMintTest.java`

- **Issue:** FIXME comments were misleading - tests were using real contract hashes from `Cip113Contracts` class, which is valid for testing.
- **Fix:** Replaced FIXME comments with accurate documentation explaining the datum structure fields. Updated `ProtocolDeploymentMintTest` to use the new `ProtocolBootstrapParams` constructor with UTxO references.

## Verification
- ✅ Frontend lint: `npm run lint` - No ESLint warnings or errors
- ✅ Frontend TypeScript: `npx tsc --noEmit` - No type errors
- ✅ Frontend build: `npm run build` - Completes successfully
- ✅ Backend compile: `./gradlew compileJava` - Completes successfully
- ✅ Backend test compile: `./gradlew compileTestJava` - Completes successfully
- ✅ DirectorySetNodeTest: `./gradlew test --tests "*.DirectorySetNodeTest"` - Passes
- ✅ Verified no `Buffer` usage remains in frontend source code

**Note:** Some pre-existing test failures exist in `RegistryServiceTest`, `AddressUtilTest`, and `BalanceValueHelperTest` (H2 database and address parsing issues). These are unrelated to the changes in this PR and were failing before these changes.

## Future Work
All architectural improvements identified during review have been addressed. See `FUTURE_WORK.md` for remaining documentation tasks.

## Files Changed

### Modified
- `src/programmable-tokens-frontend/lib/api/minting.ts` - Browser-compatible hex encoding
- `src/programmable-tokens-frontend/components/mint/mint-form.tsx` - Byte-length validation
- `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/model/DirectorySetNode.java` - Type safety fix + proper logging
- `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/model/onchain/ProtocolParamsParser.java` - Improved logging levels
- `src/programmable-tokens-offchain-java/src/test/java/org/cardanofoundation/cip113/model/DirectorySetNodeTest.java` - Test update
- `src/programmable-tokens-frontend/PHASE4-MINTING-PLAN.md` - Documentation update
- `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/model/bootstrap/ProtocolBootstrapParams.java` - Added UTxO reference fields
- `src/programmable-tokens-offchain-java/src/main/resources/protocolBootstrap.json` - Added UTxO references
- `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/controller/IssueTokenController.java` - Config-driven UTxO lookup + better error logging
- `src/programmable-tokens-onchain-aiken/validators/programmable_logic_global.ak` - Clarified ordering documentation
- `src/programmable-tokens-offchain-java/src/test/java/org/cardanofoundation/cip113/DirectoryMintTest.java` - Improved documentation
- `src/programmable-tokens-offchain-java/src/test/java/org/cardanofoundation/cip113/ProtocolParamsMintTest.java` - Improved documentation
- `src/programmable-tokens-offchain-java/src/test/java/org/cardanofoundation/cip113/ProtocolDeploymentMintTest.java` - Updated for new ProtocolBootstrapParams

### Added
- `.github/copilot-instructions.md` - Copilot instructions for the project
- `PR_CHANGES.md` - This file documenting PR changes
- `FUTURE_WORK.md` - Technical debt documentation
