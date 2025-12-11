# CIP-113 Programmable Tokens PoC Website - Implementation Plan

**Version:** 1.0
**Last Updated:** 2025-12-01
**Status:** Phase 4 Complete ✅

---

## Overview

Build a Next.js web application for interacting with CIP-113 programmable tokens on Cardano. The app enables protocol deployment, token minting, and token transfers with configurable validation logic.

---

## Tech Stack

### Frontend
- **Next.js 14+** (App Router, TypeScript)
- **Tailwind CSS** (responsive, mobile-first)
- **Mesh SDK v1.x** (@meshsdk/core, @meshsdk/react) - Transaction building
- **React Hook Form** - Form management
- **Zod** - Validation
- **Lucide React** - Icons

### Blockchain Integration
- **Mesh SDK** - Primary transaction builder
- **Blockfrost API** (via Mesh) - Blockchain queries
- **Future consideration:** Java backend with Yaci if needed

### Wallet Support
- Nami, Eternl, Lace, Flint
- Wallet-based authentication only

---

## Project Structure

```
frontend/
├── src/
│   ├── app/                          # Next.js app router
│   │   ├── layout.tsx
│   │   ├── page.tsx                  # Landing page
│   │   ├── deploy/                   # Protocol deployment (isolated)
│   │   ├── dashboard/                # Main token management
│   │   ├── mint/                     # Token minting flow
│   │   ├── transfer/                 # Token transfer flow
│   │   ├── blacklist/                # Blacklist management UI
│   │   └── token/[policyId]/         # Token details
│   ├── components/
│   │   ├── ui/                       # Reusable UI components
│   │   ├── wallet/                   # Wallet connection
│   │   ├── forms/                    # Form components
│   │   └── layout/                   # Layout components
│   ├── lib/
│   │   ├── mesh/                     # Mesh SDK utilities
│   │   ├── contracts/                # Smart contract interactions
│   │   ├── config/                   # Configuration management
│   │   └── utils/                    # Helper functions
│   ├── hooks/                        # Custom React hooks
│   ├── types/                        # TypeScript types
│   ├── config/
│   │   ├── networks.ts               # Network configurations
│   │   ├── cip113-blueprint.json     # Main CIP-113 plutus.json
│   │   ├── protocol-bootstrap.json   # Protocol instance params
│   │   └── substandards/             # Substandard definitions
│   │       ├── simple-transfer.json
│   │       └── blacklist-example.json
│   └── constants/
└── public/
```

---

## Configuration Architecture

### 1. Network Configuration (Parametric)
```typescript
// config/networks.ts
type Network = 'preview' | 'preprod' | 'mainnet'

interface NetworkConfig {
  name: Network
  blockfrostApiKey: string
  blockfrostUrl: string
  protocolBootstrap?: ProtocolBootstrap // Loaded after deployment
}

// Default: Preview
// Easily switchable via environment variables or UI
```

### 2. CIP-113 Core Definition
```json
// config/cip113-blueprint.json
{
  "validators": {
    "programmable_logic_global": { ... },
    "programmable_logic_base": { ... },
    "registry_mint": { ... },
    "registry_spend": { ... },
    "issuance_mint": { ... },
    "protocol_params_mint": { ... }
  }
}
```

### 3. Protocol Bootstrap JSON (Generated from Deployment)
```json
// config/protocol-bootstrap.json
{
  "network": "preview",
  "protocolParamsPolicyId": "abc123...",
  "registryPolicyId": "def456...",
  "programmableLogicCredential": "ghi789...",
  "deploymentTxHash": "jkl012...",
  "timestamp": "2025-11-07T...",
  "operator": "addr_test1..."
}
```

### 4. Substandard Definitions (Array of Transfer Logic Configs)
```json
// config/substandards/simple-transfer.json
{
  "name": "Simple Transfer",
  "description": "Basic transfer with simple redeemer acceptance",
  "plutus": {
    "validators": {
      "transfer_logic": { ... },
      "minting_logic": { ... }
    }
  },
  "config": {
    "redeemerType": "simple",
    "requiredSigners": []
  }
}

// config/substandards/blacklist-example.json
{
  "name": "Blacklist Transfer",
  "description": "Transfer with blacklist validation",
  "plutus": {
    "validators": {
      "transfer_logic": { ... },
      "minting_logic": { ... },
      "blacklist_mint": { ... }
    }
  },
  "config": {
    "redeemerType": "complex",
    "requiresBlacklist": true,
    "blacklistPolicyId": null  // Set after deployment
  }
}
```

**Note:** Each substandard may require different transaction building logic. We'll handle this iteratively.

---

## Core Features & Pages

### 1. Landing Page (`/`)
**Purpose:** Introduction and quick access to main functions

**Content (high-level):**
- Hero section with CIP-113 overview
- Three feature cards:
  - Deploy Protocol (if not deployed)
  - Mint Tokens
  - Transfer Tokens
- Connect Wallet CTA
- Network indicator/selector

**Status:** Content details TBD during development

---

### 2. Protocol Deployment (`/deploy`) ⚠️ ISOLATED FLOW
**Purpose:** One-time protocol setup (generates protocol-bootstrap.json)

**Important Notes:**
- This is a one-time operation per network
- Results used to generate `protocol-bootstrap.json`
- Users primarily use mint/transfer; deployment is admin-level
- Should be accessible but clearly marked as "advanced/one-time"

**High-level Flow:**
1. Check if protocol already deployed
2. Configure deployment parameters
3. Execute deployment transaction
4. Generate and save protocol-bootstrap.json
5. Success screen with deployment details

**Status:** Detailed UX TBD during development

---

### 3. Dashboard (`/dashboard`)
**Purpose:** Main hub for token management

**High-level Content:**
- Wallet overview (address, balance, tokens)
- Protocol status indicator
- List of available programmable tokens
- Quick actions (mint, transfer)
- Token filtering

**Status:** Detailed layout TBD during development

---

### 4. Token Minting (`/mint`)
**Purpose:** Create new programmable tokens with selected transfer logic

**High-level Flow:**
1. Select substandard (simple transfer, blacklist, etc.)
2. Configure token parameters
3. Review and sign transaction
4. Confirmation

**Status:** Form details TBD during development

---

### 5. Token Transfer (`/transfer`)
**Purpose:** Transfer programmable tokens with automatic validation

**High-level Flow:**
1. Select token from owned tokens
2. Enter recipient and amount
3. Preview validation rules
4. Sign and submit
5. Confirmation

**Status:** Form details TBD during development

---

### 6. Blacklist Management (`/blacklist`)
**Purpose:** Manage blacklist for freeze-and-seize example

**High-level Content:**
- Current blacklist entries
- Add address to blacklist
- Remove address from blacklist
- Blacklist status check tool

**Status:** Detailed UI TBD during development

---

### 7. Token Details (`/token/[policyId]`)
**Purpose:** View token information and history

**High-level Content:**
- Token metadata
- Registry information
- Transfer logic details
- Transaction history (if available)

**Status:** Detailed content TBD during development

---

## Key Components (High-Level)

### Wallet Integration
```typescript
// components/wallet/WalletProvider.tsx
- Mesh wallet connection
- Network detection
- Balance tracking

// components/wallet/ConnectButton.tsx
- Wallet selection modal
- Connection status
```

### Transaction Builders
```typescript
// lib/mesh/transactions/
- deployProtocol.ts
- mintProgrammableToken.ts
- transferProgrammableToken.ts
- manageBlacklist.ts
```

### Configuration Management
```typescript
// lib/config/ConfigManager.ts
- Load CIP-113 blueprint
- Load/save protocol bootstrap
- Load substandard definitions
- Network switching
```

### Smart Contract Integration
```typescript
// lib/contracts/
- Load Aiken blueprints
- Build validators with Mesh
- Compute addresses
- Build redeemers/datums
```

---

## Design System

**Inspiration:** https://cip113-policy-manager-dev.fluidtokens.com/

**Theme:**
- Dark mode with gradient accents
- Primary: Blue gradient (#3B82F6 → #2563EB)
- Accent: Teal (#14B8A6)
- Background: Dark slate (#0F172A, #1E293B)

**Components:**
- Rounded cards (24px)
- Gradient buttons
- Dark inputs with focus glow
- Smooth transitions

**Responsive:**
- Mobile-first design
- Breakpoints: sm/md/lg/xl
- Hamburger menu on mobile

**Note:** Detailed design specifications TBD during development

---

## Implementation Phases

### Phase 1: Setup & Foundation (Days 1-2)
**Deliverables:**
- ✅ Next.js project initialized with TypeScript
- ✅ Dependencies installed (Mesh SDK, Tailwind, etc.)
- ✅ Project structure created
- ✅ Tailwind configured with custom theme
- ✅ Base layout and navigation
- ✅ Wallet connection with Mesh
- ✅ Network configuration system
- ✅ Configuration loader (blueprints, bootstrap, substandards)

**Success Criteria:**
- App runs locally
- Can connect wallet
- Can switch networks
- Configuration files load correctly

---

### Phase 2: Core UI Components (Days 2-3)
**Deliverables:**
- ✅ Reusable UI components library (Button, Card, Input, Select, etc.)
- ✅ Wallet components (ConnectButton, WalletInfo, NetworkSelector)
- ✅ Responsive navigation
- ✅ Landing page layout
- ✅ Dashboard layout skeleton

**Success Criteria:**
- Component library functional
- Responsive on mobile/tablet/desktop
- Wallet connection flow works

---

### Phase 3: Protocol Deployment Flow (Days 3-5)
**Deliverables:**
- ✅ Load CIP-113 Aiken blueprints
- ✅ Protocol deployment page UI
- ✅ Transaction builder for deployment
- ✅ Protocol bootstrap JSON generation
- ✅ Deployment status checker
- ✅ Test on Preview testnet

**Success Criteria:**
- Can deploy protocol on Preview
- protocol-bootstrap.json generated correctly
- Deployment status detectable

---

### Phase 4: Simple Transfer Substandard (Days 5-7)
**Deliverables:**
- ✅ Load simple transfer substandard config
- ✅ Minting flow for simple transfer tokens
- ✅ Transfer flow for simple transfer tokens
- ✅ Transaction builders for both operations
- ✅ Test end-to-end on Preview

**Success Criteria:**
- Can mint tokens with simple transfer logic
- Can transfer tokens successfully
- Validation works correctly

---

### Phase 5: Blacklist Substandard (Days 7-9)
**Deliverables:**
- ✅ Load blacklist substandard config
- ✅ Blacklist management UI
- ✅ Minting flow for blacklist tokens
- ✅ Transfer flow with blacklist validation
- ✅ Transaction builders with blacklist proofs
- ✅ Test end-to-end on Preview

**Success Criteria:**
- Can manage blacklist entries
- Can mint blacklist-enabled tokens
- Transfers validate against blacklist
- Blacklisted addresses cannot receive tokens

---

### Phase 6: Dashboard & Token Details (Days 9-10)
**Deliverables:**
- ✅ Token listing on dashboard
- ✅ Fetch owned tokens from blockchain
- ✅ Token details page
- ✅ Transaction history (if available via Blockfrost)
- ✅ Filtering and search

**Success Criteria:**
- Dashboard shows accurate token data
- Token details page informative
- Performance acceptable

---

### Phase 7: Testing & Polish (Days 10-11)
**Deliverables:**
- ✅ E2E testing with real wallets
- ✅ Mobile responsiveness testing
- ✅ Error handling improvements
- ✅ Loading states and animations
- ✅ User feedback (toasts, confirmations)
- ✅ Documentation (README, user guide)

**Success Criteria:**
- No critical bugs
- Smooth user experience
- Works on mobile devices
- Clear error messages

---

## Open Items & Future Considerations

### Answered Questions ✅
1. **Network:** Preview by default, parametric for switching ✅
2. **Transfer Logic:** Parametric via substandard configs (simple + blacklist initially) ✅
3. **Backend:** Blockfrost only initially, Java/Yaci if needed later ✅
4. **Blacklist UI:** Yes, include it ✅
5. **Authentication:** Wallet-based only ✅

### Future Considerations 🔮
- [ ] Different transaction building per substandard (handle case-by-case)
- [ ] Java backend with Yaci integration (if Blockfrost insufficient)
- [ ] Additional substandards (whitelist, time-locks, etc.)
- [ ] Advanced token registry browser
- [ ] Transaction simulation/preview
- [ ] Multi-sig support
- [ ] Governance features

---

## Development Notes

### Configuration Management Priority
The configuration system is critical. We need:
1. **Network switching** without code changes
2. **Protocol bootstrap persistence** (local storage + file export)
3. **Substandard discovery** (dynamic loading of new standards)
4. **Version compatibility** checking

### Transaction Building Abstraction
Since different substandards may need different tx building:
```typescript
interface SubstandardAdapter {
  buildMintTx(params: MintParams): Promise<Transaction>
  buildTransferTx(params: TransferParams): Promise<Transaction>
  validateConfig(): boolean
}

// Implement per substandard
class SimpleTransferAdapter implements SubstandardAdapter { ... }
class BlacklistTransferAdapter implements SubstandardAdapter { ... }
```

### Iterative Content Design
**Important:** Page content, forms, and UX details will be designed iteratively during development. This plan provides structure, not pixel-perfect specifications.

---

## Success Metrics

**For PoC:**
- ✅ Can deploy protocol on Preview testnet
- ✅ Can mint programmable tokens (2 substandards)
- ✅ Can transfer tokens with validation
- ✅ Can manage blacklist
- ✅ Works on mobile devices
- ✅ Code quality suitable for demo

**Timeline:** ~11 days of focused development

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Mesh SDK limitations | High | Test early, have Java backend as fallback |
| Complex transaction building | High | Start with simple substandard, iterate |
| Blockfrost rate limits | Medium | Implement caching, consider Yaci backend |
| Wallet compatibility issues | Medium | Test with multiple wallets early |
| Mobile responsiveness | Low | Mobile-first design from start |

---

## Next Steps

1. ✅ Review and approve plan
2. ⏭️ Initialize Next.js project
3. ⏭️ Setup development environment
4. ⏭️ Begin Phase 1 implementation

---

**Questions before starting?**
- Confirm project name/directory structure
- Blockfrost API key availability
- Any specific design preferences beyond inspiration site
- Priority on certain features if timeline tight

---

_This plan is a living document and will be updated as development progresses._
