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

### 6. GitHub Actions CI — COMPLETED
Added automated CI pipeline (`.github/workflows/ci.yml`) that runs:
- Aiken smart contract tests (80 tests)
- Java backend tests with PostgreSQL service (155 tests)
- Frontend lint, tests, and build verification (65 tests)
- All-pass gate job for PR status checks

### 7. Frontend Pages — COMPLETED
Added missing frontend pages:
- **Transfer Page** (`/transfer`) - Token selection, transfer form, preview, success flow
- **Dashboard Page** (`/dashboard`) - Protocol stats, registered tokens, quick actions
- Enhanced UI components with `outline` button variant and `destructive` toast variant

---

## Remaining Items

### 8. ~~Frontend Test Coverage~~ — COMPLETED

**Location:** `src/programmable-tokens-frontend/`

~~The frontend lacks unit tests. Currently relies on TypeScript compilation and linting for validation.~~

**COMPLETED:** Added comprehensive frontend test coverage using Vitest:
- **Minting API Tests (19 tests):** `stringToHex`, `hexToString`, `prepareMintRequest` functions
- **API Client Tests (7 tests):** GET/POST requests, error handling, timeout handling
- **Validation Tests (26 tests):** Token name, quantity, address, hex validation
- **Hook Tests (5 tests):** `useSubstandards` hook with loading, error, and refetch states
- **Type Tests (8 tests):** `ApiException` and type structure validation

**Test Setup:**
- Vitest 2.1.6 with React Testing Library
- jsdom environment for React component testing
- 65 unit tests, 0 failures

**Scripts Added:**
```bash
npm test           # Run tests once
npm run test:watch # Run tests in watch mode
npm run test:coverage # Run with coverage report
```

**Priority:** ~~Medium~~ — ✅ Completed

### 7. ~~Backend Test Coverage Expansion~~ — COMPLETED

**Location:** `src/programmable-tokens-offchain-java/`

~~Some areas could benefit from additional test coverage:~~
~~- Controller endpoint tests~~
~~- Service integration tests~~
~~- Error handling edge cases~~

**COMPLETED:** Added comprehensive test coverage:
- **Controller Tests (48 tests):** HealthcheckControllerTest, SubstandardControllerTest, ProtocolControllerTest, BalanceControllerTest, HistoryControllerTest, RegistryControllerTest, ProtocolParamsControllerTest
- **Validation Tests (36 tests):** MintTokenRequestValidationTest with parameterized tests
- **Exception Handler Tests (9 tests):** GlobalExceptionHandlerTest for error response consistency

Total test count increased from 62 to 155 tests.

**Priority:** ~~Low~~ — ✅ Completed

### 8. ~~Refactor Controller Error Responses to Use ApiException~~ — COMPLETED

**Location:** `src/programmable-tokens-offchain-java/src/main/java/org/cardanofoundation/cip113/controller/IssueTokenController.java`

~~The controller has ~20+ inline `ResponseEntity.badRequest()` and `ResponseEntity.internalServerError()` calls that return plain string bodies. These should be refactored to throw `ApiException` for consistent error formatting.~~

**COMPLETED:** All 25 inline error handlers in `IssueTokenController` have been migrated to use `ApiException`:
- `/register` endpoint: 9 error handlers migrated
- `/mint` endpoint: 7 error handlers migrated
- `/issue` endpoint: 9 error handlers migrated

All error responses now:
- Provide consistent JSON format via GlobalExceptionHandler
- Include timestamp, status, error type, message, and path
- Have improved, clearer error messages
- Include proper logging before throwing

---

## Summary Table

| Item | Status | Type | Priority |
|------|--------|------|----------|
| Config-driven UTxOs | ✅ Completed | Architecture | — |
| Input ordering checks | ✅ Clarified | Security | — |
| Test fixture docs | ✅ Improved | Testing | — |
| Documentation plan | ✅ Completed | Docs | — |
| RegistryNodeParserTest | ✅ Completed | Testing | — |
| GitHub Actions CI | ✅ Completed | DevOps | — |
| Frontend pages (transfer/dashboard) | ✅ Completed | Frontend | — |
| Global exception handler | ✅ Completed | Architecture | — |
| Bean Validation | ✅ Completed | Architecture | — |
| Controller ApiException refactor | ✅ Completed | Architecture | — |
| Backend test expansion | ✅ Completed | Testing | — |
| Frontend tests | ✅ Completed | Testing | — |

---

## Test Suite Status

**Final Results:** 300 total tests (155 Java + 80 Aiken + 65 Frontend), 0 failures

| Test Category | Count | Status |
|---------------|-------|--------|
| Java Unit Tests | 147 | ✅ Pass |
| Java Integration Tests | 8 | ✅ Pass |
| Aiken Smart Contract Tests | 80 | ✅ Pass |
| Frontend Unit Tests | 65 | ✅ Pass |

### Java Backend Test Classes (155 tests)
| Test Class | Tests | Description |
|------------|-------|-------------|
| HealthcheckControllerTest | 5 | `/healthcheck` endpoint tests |
| SubstandardControllerTest | 5 | `/api/v1/substandards` endpoint tests |
| ProtocolControllerTest | 4 | `/api/v1/protocol` endpoint tests |
| BalanceControllerTest | 9 | `/api/v1/balances` endpoint tests |
| HistoryControllerTest | 4 | `/api/v1/history` endpoint tests |
| RegistryControllerTest | 11 | `/api/v1/registry` endpoint tests |
| ProtocolParamsControllerTest | 10 | `/api/v1/protocol-params` endpoint tests |
| MintTokenRequestValidationTest | 36 | Bean Validation annotation tests |
| GlobalExceptionHandlerTest | 9 | Exception handling consistency tests |

### Frontend Test Classes (65 tests)
| Test File | Tests | Description |
|-----------|-------|-------------|
| minting.test.ts | 19 | Hex encoding, request preparation |
| client.test.ts | 7 | API client, error handling, timeouts |
| validation.test.ts | 26 | Token name, quantity, address validation |
| use-substandards.test.ts | 5 | React hook loading, error, refetch states |
| api.test.ts | 8 | ApiException and type structure tests |

### Aiken Smart Contract Tests (80 tests)
| Test Module | Tests | Description |
|-------------|-------|-------------|
| blacklist_mint.test | 8 | Blacklist linked list operations |
| example_transfer_logic.test | 12 | Transfer logic validators |
| issuance_mint.test | 11 | Token minting policy |
| linked_list_test | 8 | Sorted linked list utilities |
| programmable_logic_base.test | 10 | Base script delegation |
| programmable_logic_global.test | 14 | Core CIP-113 validator |
| registry_mint.test | 5 | Registry operations |
| types_test | 1 | Type utilities |
| utils_test | 11 | Utility functions |

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
