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

---

## Remaining Items

### 4. Documentation: Complete Plan Execution

**Location:** `src/programmable-tokens-onchain-aiken/DOCUMENTATION-PLAN.md`

Contains "Open Questions / TODOs" section with planning notes for documentation work.

**Recommendation:**
- Work through remaining documentation phases as outlined.
- Consider publishing generated docs to GitHub Pages or a docs site.

**Priority:** Low — improves onboarding and developer experience.

---

## Summary Table

| Item | Status | Type | Priority |
|------|--------|------|----------|
| Config-driven UTxOs | ✅ Completed | Architecture | — |
| Input ordering checks | ✅ Clarified | Security | — |
| Test fixture docs | ✅ Improved | Testing | — |
| Documentation plan | Remaining | Docs | Low |

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
