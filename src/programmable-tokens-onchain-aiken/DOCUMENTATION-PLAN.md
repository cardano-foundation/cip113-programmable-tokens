# Documentation Plan - Programmable Tokens (Aiken Implementation)

**Status**: In Progress - Phase 1
**Last Updated**: 2025-10-24
**Target Audience Priority**: Medium-to-deep technical (integration engineers, solution architects, developers)

---

## Documentation Structure

```
README.md (Main entry point - Progressive disclosure)
├── docs/
│   ├── 01-INTRODUCTION.md (Light technical background)
│   ├── 02-ARCHITECTURE.md (Medium-technical system design)
│   ├── 03-VALIDATORS.md (Technical - high-level logic)
│   ├── 04-DATA-STRUCTURES.md (Technical reference)
│   ├── 05-TRANSACTION-FLOWS.md (Technical - practical)
│   ├── 06-USAGE.md (Practical guide)
│   ├── 07-MIGRATION-NOTES.md (For Plutarch developers)
│   └── 08-INTEGRATION-GUIDES.md (Audience-specific: wallets, indexers/explorers, dApps)
```

---

## Implementation Timeline

### **Phase 1**: Foundation (README + Introduction)
**Goal**: Get the story and basic concepts right

**Deliverables**:
1. ✅ `README.md` - Main entry point with quick start
2. ✅ `docs/01-INTRODUCTION.md` - Problem, solution, high-level concepts

**Verification Sources**:
- `/doc/architecture.md` (official Plutarch docs)
- CIP-143 specification (cardano-foundation/CIPs)
- User feedback on clarity

---

### **Phase 2**: Architecture (Medium-Technical)
**Goal**: Verify technical accuracy of system design

**Deliverables**:
1. ✅ `docs/02-ARCHITECTURE.md` - System components, flows, integration points

**Verification Sources**:
- `/doc/architecture.md` (cross-reference all claims)
- Plutarch source code in `src/programmable-tokens-onchain/`
- `/CIP-0143-FLOW.md` (verify against our reverse-engineered flows)
- Test transactions on preview testnet

---

### **Phase 3**: Deep Technical Documentation
**Goal**: Complete technical reference for implementers

**Deliverables**:
1. ✅ `docs/03-VALIDATORS.md` - High-level validator logic (not line-by-line)
2. ✅ `docs/04-DATA-STRUCTURES.md` - Types, redeemers, datums
3. ✅ `docs/05-TRANSACTION-FLOWS.md` - Practical transaction building
4. ✅ `docs/06-USAGE.md` - Build, test, deploy guide
5. ✅ `docs/07-MIGRATION-NOTES.md` - Plutarch → Aiken notes
6. ✅ `docs/08-INTEGRATION-GUIDES.md` - Audience-specific integration guidance (wallets, indexers/explorers, dApps)

**Verification Sources**:
- Aiken source code (ground truth: "code is law")
- Plutarch equivalents for comparison
- Integration test results

---

## Content Guidelines

### General Principles
1. **Progressive Disclosure**: Non-tech → Medium-tech → Deep-tech
2. **Verification Required**: Mark unverified claims with `⚠️ VERIFY:`
3. **Code is Law**: When in doubt, reference actual Aiken code
4. **Practical Focus**: Examples over theory
5. **Mermaid Diagrams**: Use for all visual aids (renders in GitHub)
6. **Clear Navigation**: Link related sections

### Standards Coverage (LIGHT TOUCH ONLY)
- **DO**: Mention CIP-143 as the base standard
- **DO**: Brief mention that programmable tokens enable regulatory compliance
- **DO**: Link to external standards docs for reference
- **DON'T**: Deep dive into MiFID II, FATF, ISO 20022, etc.
- **DON'T**: List all possible regulatory use cases
- **KEEP IT**: 1-2 sentences max per standard/regulation

### Blacklist Operations
- **Scope**: Example use case only
- **Coverage**: How it works at high level
- **Detail Level**: Reference to `blacklist_mint.ak` without deep explanation
- **Purpose**: Show extensibility, not comprehensive feature docs

### Validator Documentation (High-Level)
- **Focus**: What each validator does and why
- **Logic**: High-level validation flow (not line-by-line)
- **Security**: What attack vectors are prevented
- **No**: Detailed code walkthroughs (code speaks for itself)

---

## Detailed Section Plans

### **README.md**
**Length**: ~100-150 lines
**Tone**: Professional, clear, accessible

**Contents**:
1. **Title & Badge** (Status, Aiken version)
2. **Quick Summary** (2-3 lines)
3. **Key Features** (Bullet points, 4-6 items)
4. **What Are Programmable Tokens?** (2 short paragraphs)
5. **Quick Start** (Build/test commands)
6. **Documentation Navigation** (Links to all docs)
7. **Project Status** (CIP-143 based, production readiness)
8. **Contributing** (How to contribute)
9. **License**

---

### **docs/01-INTRODUCTION.md**
**Length**: ~200-300 lines
**Tone**: Accessible but technical enough for engineers
**Verification**: Cross-check with `/doc/architecture.md`

**Contents**:

#### 1. The Problem (50 lines)
- Blockchain tokens lack transfer restrictions
- Real-world assets require compliance (1-2 sentence examples only)
- Gap between blockchain and regulated finance

#### 2. What Are Programmable Tokens? (80 lines)
- **Definition**: Native Cardano assets + lifecycle rules
- **Key Principle**: Still native assets, enhanced with constraints
- **Not a Fork**: Layer on top of existing infrastructure
- **Comparison Table**:
  ```
  | Aspect | Native Token | Programmable Token |
  |--------|-------------|-------------------|
  | Transfer | Unrestricted | Rule-based |
  | Custody | Any address | Programmable address |
  | Validation | Ledger rules only | Ledger + custom logic |
  ```

#### 3. How They Work (High-Level) (70 lines)
- **Special Addresses**: Tokens locked in smart contracts
- **Registry**: On-chain directory of approved tokens
- **Validation**: Custom logic runs on every transfer
- **Diagram**: Simple flow chart (Mermaid)
  ```mermaid
  graph LR
    A[User Transfer] --> B{Registry Lookup}
    B --> C[Validation Script]
    C --> D{Rules Pass?}
    D -->|Yes| E[Transfer Complete]
    D -->|No| F[Transaction Rejected]
  ```

#### 4. Key Benefits (50 lines)
- **For Issuers**: Compliance automation, reduced overhead
- **For Users**: Same wallet UX, transparent rules
- **For Ecosystem**: Interoperable, composable

#### 5. CIP-143 Standard (30 lines)
- Brief intro to CIP-143
- Link to official spec
- **Standards mention** (LIGHT): "Enables compliance with various regulatory frameworks including stablecoin standards and tokenized securities requirements. See [references] for details."
- This implementation status

---

### **docs/02-ARCHITECTURE.md**
**Length**: ~400-500 lines
**Tone**: Technical but not code-heavy
**Verification**: Every claim cross-checked with `/doc/architecture.md` and source code

**Contents**:

#### 1. System Overview (80 lines)
- Core components list
- High-level architecture diagram (Mermaid)
- Component interactions

#### 2. Token Registry (80 lines)
- Purpose and design
- Linked list structure (with diagram)
- Why linked list (O(1) lookups)
- Registry entry contents
- ⚠️ **VERIFY**: Against `directory_mint.ak` and `DirectorySetNode` type

#### 3. Programmable Logic Base (60 lines)
- What it is
- Why shared payment credential
- Address structure explanation
- ⚠️ **VERIFY**: Against `programmable_logic_base.ak`

#### 4. Validation Scripts (70 lines)
- Transfer logic scripts
- Issuer logic scripts
- Withdraw-zero pattern
- Blacklist example (high-level only)
- ⚠️ **VERIFY**: Against `programmable_logic_global.ak`

#### 5. Smart Contract Addresses (60 lines)
- Address structure details
- Stake vs payment credentials
- Ownership model
- Example addresses

#### 6. Transaction Lifecycle (80 lines)
- Registration flow (simple diagram)
- Issuance flow (simple diagram)
- Transfer flow (simple diagram)
- ⚠️ **VERIFY**: Against `/CIP-0143-FLOW.md` BUT verify accuracy

#### 7. Security Model (50 lines)
- Ownership proof
- Authorization layers
- NFT authenticity
- Immutability guarantees

#### 8. Integration Points (30 lines)
- For wallets
- For dApps
- For issuers
- Reference to usage guide

---

### **docs/03-VALIDATORS.md**
**Length**: ~300-400 lines
**Tone**: Technical reference
**Approach**: High-level logic, not line-by-line

**Contents**:

#### 1. Validator Overview
- Table of all validators with summary

#### 2. Per-Validator Sections
For each validator:
- **File Reference**: `validators/xyz.ak`
- **Type**: Minting/Spend/Stake
- **Parameters**: What it's parameterized by
- **Redeemer**: Structure (reference to types.ak)
- **Purpose**: What it does (2-3 sentences)
- **Validation Logic**: Bullet points of checks (5-10 items)
- **Security**: What attacks it prevents
- **Plutarch Equivalent**: File reference

#### 3. Validation Patterns
- Withdraw-zero pattern
- NFT authenticity checks
- Reference input patterns

---

### **docs/04-DATA-STRUCTURES.md**
**Length**: ~200-300 lines
**Tone**: Technical reference
**Source**: Direct from `lib/types.ak`

**Contents**:

#### 1. Core Types
- `DirectorySetNode`
- `ProgrammableLogicGlobalParams`
- `BlacklistNode`
- `IssuanceCborHex`

Each with:
- Aiken definition
- Field-by-field explanation
- Example values
- CBOR representation

#### 2. Redeemers
- All redeemer types
- When to use each
- Example values

#### 3. Constants
- All protocol constants
- Rationale for values

---

### **docs/05-TRANSACTION-FLOWS.md**
**Length**: ~400-500 lines
**Tone**: Practical technical
**Purpose**: Show developers how to build transactions

**Contents**:

#### 1. Transaction Structure Template
- General pattern
- Required fields
- Reference input handling

#### 2. Phase-by-Phase Flows
- Deployment
- Registration
- Issuance
- Transfer
- Seizure

Each with:
- Inputs/outputs/mint/certificates structure
- Redeemer examples
- Witness requirements
- ⚠️ **VERIFY**: Against actual testnet transactions if possible

#### 3. Common Patterns
- Building reference inputs
- Calculating indices
- Proof construction

#### 4. Error Scenarios
- Common failures
- Debug strategies

---

### **docs/06-USAGE.md**
**Length**: ~200-300 lines
**Tone**: Practical guide

**Contents**:

#### 1. Prerequisites
#### 2. Building
#### 3. Testing
#### 4. Deployment Guide
#### 5. Off-chain Integration Examples
#### 6. Troubleshooting

---

### **docs/07-MIGRATION-NOTES.md**
**Length**: ~150-200 lines
**Tone**: Technical comparison

**Contents**:

#### 1. Plutarch → Aiken Mapping
- Validator equivalence table
- Type mappings
- Language differences

#### 2. Known Differences
- What changed and why

#### 3. CIP-143 Implementation Notes
- Where we deviate
- Why we deviate

---

### **docs/08-INTEGRATION-GUIDES.md**
**Length**: ~500-600 lines
**Tone**: Practical, audience-specific
**Purpose**: Tell each integration audience exactly what they need to know

**Contents**:

#### 0. Understanding Programmable Addresses (~60 lines)
- Address structure: shared payment credential + unique stake credential
- Credential flexibility: stake key, payment key, or script hash in stake slot
- On-chain validators are credential-agnostic (VerificationKey vs Script only)
- Choice of credential type is a protocol/off-chain design decision

#### 1. For Wallet Developers (~150 lines)
- **Balance Resolution**: Query by full address (payment + stake credential), handle both payment-key and stake-key conventions
- **Building Transfers**: Authorization method (stake vs payment key), withdraw-zero invocations, reference inputs, registry proofs, output construction
- **Transaction Skeleton**: Complete example of a transfer transaction
- **Token Discovery**: How to query the on-chain registry
- **Stake Delegation**: Implications for each credential type (minimal ADA, but technically possible)
- **Common Pitfalls**: Table of frequent integration mistakes

#### 2. For Indexers and Explorers (~150 lines)
- **Balance Tracking**: Group UTxOs by stake credential at `programmable_logic_base`, handle script owners
- **Credential Type Ambiguity**: Payment key vs stake key hashes are indistinguishable on-chain
- **TX History by Stake Address**: Standard case (straightforward)
- **TX History by Payment Key in Stake Slot**: Enterprise/CEX pattern — query payment key hash as a stake credential
- **Transfer vs Seizure Detection**: `TransferAct` vs `ThirdPartyAct` redeemers
- **Registry State Tracking**: Token registrations, transfer logic, compliance events
- **Common Pitfalls**: Table of frequent integration mistakes

#### 3. For dApp Developers (~200 lines)
- **Script as Owner**: dApp script hash in stake slot, withdraw-zero authorization
- **Transaction Building**: Multiple simultaneous withdraw-zero invocations, composing with dApp logic
- **Script Requirements**: Must implement `withdraw` purpose, stake address registration
- **Delegation and Withdrawal**: Distinguishing zero-ADA (authorization) from real withdrawals
- **Execution Budget**: Multiple validator invocations, profiling guidance
- **Composability Patterns**: Receiving, releasing, and holding mixed assets
- **Common Pitfalls**: Table of frequent integration mistakes

---

## Verification Checklist

Before marking any section complete:

- [ ] Cross-referenced with `/doc/architecture.md`
- [ ] Checked against actual Aiken source code
- [ ] Verified against Plutarch equivalent (if applicable)
- [ ] Tested claims with code/tests where possible
- [ ] Marked unverified claims with `⚠️ VERIFY:`
- [ ] Added Mermaid diagrams where helpful
- [ ] Linked related sections
- [ ] Practical examples included

---

## Current Status

**Phase 1**: 🔄 In Progress
- [ ] README.md
- [ ] docs/01-INTRODUCTION.md

**Phase 2**: ⏳ Pending
**Phase 3**: ⏳ Pending

---

## Notes & Decisions

- **Standards Coverage**: LIGHT TOUCH - 1-2 sentences max, focus on technical implementation
- **Blacklist**: Example only, not comprehensive feature documentation
- **Validators**: High-level logic, code is self-documenting
- **Diagrams**: Mermaid for GitHub rendering
- **Audience**: Medium-to-deep technical (integration engineers priority)
- **Verification**: Every claim must be verifiable against source code or official Plutarch docs

---

## Open Questions / TODOs

- [ ] Get access to CIP-143 official spec URL
- [ ] Identify testnet transaction hashes for examples
- [ ] Confirm production readiness status
- [ ] Decide on license for documentation

---

*This plan will be updated as we progress through each phase.*
