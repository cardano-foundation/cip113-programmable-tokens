# Future Work & Technical Debt

This document captures remaining TODOs, FIXMEs, and potential improvements identified during codebase review.

---

## ✅ Completed Items (This PR)

### 1. Backend: Config-Driven Bootstrap UTxOs — COMPLETED
Extended `ProtocolBootstrapParams` and `protocolBootstrap.json` with explicit UTxO references. Refactored `IssueTokenController` to use config values.

### 2. On-Chain: Input Ordering Validation — CLARIFIED
Analysis confirmed that ordering is already validated via the `node.key == cs` check in `validate_single_cs`. Updated comments to document this.

### 3. Test Fixtures: Documentation — IMPROVED
Updated FIXME comments to accurate documentation. Tests are using real contract hashes from `Cip113Contracts` class which is valid for testing.

### 4. Documentation: Complete Plan Execution — COMPLETED
Created comprehensive documentation for Aiken smart contracts:
- `docs/01-INTRODUCTION.md` - Problem, solution, and core concepts
- `docs/02-ARCHITECTURE.md` - System design and component overview
- `docs/03-VALIDATORS.md` - Validator reference guide
- `docs/04-DATA-STRUCTURES.md` - Types, redeemers, and datum formats
- `docs/05-TRANSACTION-FLOWS.md` - Transaction building patterns
- `docs/06-USAGE.md` - Build, test, and deploy guide
- `docs/07-MIGRATION-NOTES.md` - Plutarch to Aiken migration details

### 5. RegistryNodeParserTest: Fixed CBOR Data — COMPLETED
Created `GenerateCborTest.java` utility to generate valid CBOR programmatically. Updated tests with correct CBOR structures. All 3 tests pass.

---

## Remaining Items

### 6. Frontend Test Coverage

**Location:** `src/programmable-tokens-frontend/`

The frontend lacks unit tests. Currently relies on TypeScript compilation and linting for validation.

**Recommendation:**
- Add Jest/Vitest for component testing
- Test critical paths: minting flow, wallet connection, API functions
- Add Playwright/Cypress for E2E testing

**Priority:** Medium — improves reliability.

### 7. Backend Test Coverage Expansion

**Location:** `src/programmable-tokens-offchain-java/`

Some areas could benefit from additional test coverage:
- Controller endpoint tests
- Service integration tests
- Error handling edge cases

**Priority:** Low — existing tests cover core functionality.

### 8. Refactor Controller Error Responses to Use ApiException

**Location:** `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/controller/IssueTokenController.java`

The controller has ~20+ inline `ResponseEntity.badRequest()` and `ResponseEntity.internalServerError()` calls that return plain string bodies. These should be refactored to throw `ApiException` for consistent error formatting.

**Example of current pattern:**
```java
if (protocolParamsUtxoOpt.isEmpty()) {
    return ResponseEntity.internalServerError().body("could not resolve protocol params");
}
```

**Recommended pattern:**
```java
if (protocolParamsUtxoOpt.isEmpty()) {
    throw ApiException.internalServerError("could not resolve protocol params");
}
```

This would:
- Provide consistent JSON error responses via GlobalExceptionHandler
- Reduce duplication in controller code
- Make error handling more testable

**Priority:** Low — functional but inconsistent error format.

---

## Summary Table

| Item | Status | Type | Priority |
|------|--------|------|----------|
| Config-driven UTxOs | ✅ Completed | Architecture | — |
| Input ordering checks | ✅ Clarified | Security | — |
| Test fixture docs | ✅ Improved | Testing | — |
| Documentation plan | ✅ Completed | Docs | — |
| RegistryNodeParserTest | ✅ Completed | Testing | — |
| Global exception handler | ✅ Completed | Architecture | — |
| Bean Validation | ✅ Completed | Architecture | — |
| Frontend tests | Remaining | Testing | Medium |
| Backend test expansion | Remaining | Testing | Low |
| Controller ApiException refactor | Remaining | Architecture | Low |

---

## Test Suite Status

**Final Results:** 62 tests, 0 failures, 0 skipped

| Test Category | Count | Status |
|---------------|-------|--------|
| Unit Tests | 58 | ✅ Pass |
| Integration Tests | 4 | ✅ Pass |

### Excluded from Default Run (Manual Integration Tests)
| Test | Purpose | How to Run |
|------|---------|------------|
| `TransferTokenTest` | Transfer programmable tokens between accounts | `./gradlew manualIntegrationTest --tests TransferTokenTest` |
| `FundSubAccountsTest` | Transfer ADA to alice/bob accounts | `./gradlew manualIntegrationTest --tests FundSubAccountsTest` |
| `SetupProgrammableAddressesTest` | Create UTxOs at programmable addresses | `./gradlew manualIntegrationTest --tests SetupProgrammableAddressesTest` |
| `GenerateSubAccountsTest` | Display all sub-account addresses | `./gradlew manualIntegrationTest --tests GenerateSubAccountsTest` |
| `DiscoverTokensTest` | Discover tokens at programmable addresses | `./gradlew manualIntegrationTest --tests DiscoverTokensTest` |

---

## Completed Fixes (This PR)

### Bug Fixes
1. **Frontend Browser Compatibility** — Replaced `Buffer` with `TextEncoder`/`TextDecoder` in `lib/api/minting.ts`.
2. **Frontend Validation** — Fixed token name validation to check UTF-8 byte length (≤32) in `mint-form.tsx`.
3. **Backend Type Safety** — Changed `DirectorySetNode` to use `Credential` instead of `String` for script fields.

### Logging Improvements
4. **DirectorySetNode** — Replaced `System.out.println` with proper SLF4J `log.debug()`, added exception logging.
5. **ProtocolParamsParser** — Changed `log.info` to `log.debug` for verbose output, improved error messages.
6. **IssueTokenController** — Improved error message from generic "error" to descriptive "Failed to mint token".

### Architectural Improvements
7. **Config-Driven UTxOs** — Extended `ProtocolBootstrapParams` with UTxO references, eliminated hardcoded indices.
8. **Input Ordering** — Documented existing validation in Aiken validator.
9. **Test Documentation** — Updated misleading FIXME comments with accurate documentation.

### Documentation Updates
10. **PHASE4-MINTING-PLAN.md** — Updated to reflect implemented endpoints.

All changes documented in `PR_CHANGES.md`.
