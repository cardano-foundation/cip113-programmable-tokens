# Phase 4: Token Minting - Implementation Plan

**Status:** Ready to Start
**Updated:** 2025-11-27
**Focus:** Educational project - Show both backend and frontend transaction building

---

## Architecture Decision

### Transaction Building Strategy

**Two Modes:**
1. **Backend Mode** (Initial/Default) - Backend builds & returns unsigned transaction
2. **Frontend Mode** (Educational) - Frontend builds transaction using Mesh SDK

**UI Toggle:** Hardcoded to Backend initially, UI toggle for future frontend mode

---

## API Integration

### 1. Protocol Blueprint
**Endpoint:** `GET http://localhost:8080/api/v1/protocol/blueprint`
**Response:** Large JSON with CIP-113 validator definitions
**Usage:**
- Load protocol validators
- Get script hashes/addresses
- Understand protocol structure

### 2. Substandards
**Endpoint:** `GET http://localhost:8080/api/v1/substandards`
**Response:** JSON array of available substandards
**Usage:**
- Display available validation logic options
- Let user choose minting constraints (simple-transfer, blacklist, etc.)

### 3. Minting API
**Controller:** `IssueTokenController` (Java backend)
**Endpoints:**
- `POST /api/v1/issue-token/mint` - Mint new programmable tokens
- `POST /api/v1/issue-token/register` - Register new token substandards
**Status:** Implemented

---

## Phase 4 Implementation Plan

### Step 1: API Integration Layer
**Files to Create:**
- `lib/api/client.ts` - Base API client with fetch wrapper
- `lib/api/protocol.ts` - Protocol & blueprint API calls
- `lib/api/substandards.ts` - Substandards API calls
- `lib/api/minting.ts` - Minting transaction API calls
- `types/api.ts` - API request/response types

**Tasks:**
- [ ] Create API client with base URL configuration
- [ ] Add error handling and retry logic
- [ ] Implement protocol blueprint fetching
- [ ] Implement substandards fetching
- [ ] Add network-specific API configuration

**Environment Variables:**
```bash
NEXT_PUBLIC_API_BASE_URL=http://localhost:8080
NEXT_PUBLIC_API_TIMEOUT=30000
```

---

### Step 2: Minting Page UI
**Files to Create:**
- `app/mint/page.tsx` - Main minting page
- `components/mint/mint-form.tsx` - Minting form component
- `components/mint/substandard-selector.tsx` - Substandard selection
- `components/mint/transaction-builder-toggle.tsx` - Backend/Frontend toggle
- `components/mint/transaction-preview.tsx` - Preview before signing
- `hooks/use-mint-token.ts` - Minting logic hook

**UI Components:**
1. **Token Details Form**
   - Token name (required)
   - Token symbol/ticker (required)
   - Token amount (required)
   - Description (optional)
   - Metadata (optional)

2. **Substandard Selection**
   - Dropdown/radio to select validation logic
   - Display substandard description
   - Show selected constraints

3. **Transaction Builder Toggle**
   - Radio button: Backend (default) | Frontend (disabled initially)
   - Info tooltip explaining the difference
   - Badge showing current mode

4. **Transaction Preview**
   - Show transaction details before signing
   - Display fees
   - Show what will be minted
   - Confirm button to sign with wallet

**Tasks:**
- [ ] Create mint page route structure
- [ ] Build token details form with validation (Zod)
- [ ] Integrate substandard selector with API
- [ ] Add transaction builder toggle (hardcoded to backend)
- [ ] Create transaction preview component
- [ ] Add loading states and error handling

---

### Step 3: Backend Transaction Flow
**Flow:**
1. User fills out mint form
2. User selects substandard
3. Frontend calls backend API: `POST /api/v1/mint`
4. Backend builds transaction and returns CBOR
5. Frontend deserializes transaction
6. User signs with wallet (Mesh SDK)
7. Frontend submits signed transaction
8. Display transaction hash and confirmation

**Request Payload (Example):**
```json
{
  "walletAddress": "addr1...",
  "tokenName": "MyToken",
  "tokenSymbol": "MTK",
  "amount": 1000000,
  "substandardId": "simple-transfer",
  "metadata": {
    "description": "...",
    "image": "..."
  }
}
```

**Response (Example):**
```json
{
  "txCbor": "84a400...",
  "txHash": "abc123...",
  "fee": "170000",
  "tokenId": "policy.asset"
}
```

**Tasks:**
- [ ] Define exact API request/response format (coordinate with backend)
- [ ] Implement backend transaction request
- [ ] Handle CBOR deserialization with Mesh SDK
- [ ] Implement wallet signing flow
- [ ] Implement transaction submission
- [ ] Add transaction status tracking
- [ ] Display success/error states

---

### Step 4: Frontend Transaction Flow (Future)
**Note:** To be implemented later for educational purposes

**Flow:**
1. User fills out mint form
2. Frontend loads protocol blueprint from API
3. Frontend builds transaction locally using Mesh SDK
4. User signs with wallet
5. Frontend submits transaction
6. Display confirmation

**Tasks (Future):**
- [ ] Parse protocol blueprint in frontend
- [ ] Build minting transaction with Mesh SDK
- [ ] Handle UTxO selection
- [ ] Calculate and attach correct datums
- [ ] Set redeemers correctly
- [ ] Enable toggle to switch between modes

---

### Step 5: Error Handling & UX
**Error Scenarios:**
- API connection failure
- Insufficient wallet funds
- Transaction building errors
- Signing rejection
- Submission failure
- Network errors

**Tasks:**
- [ ] Add comprehensive error messages
- [ ] Implement retry logic for failed requests
- [ ] Add loading spinners and progress indicators
- [ ] Show transaction status updates
- [ ] Add success confirmations with links to explorer

---

## Data Structures Needed

### Protocol Blueprint Type
```typescript
interface ProtocolBlueprint {
  validators: Array<{
    title: string;
    redeemer: any;
    datum: any;
    compiledCode: string;
    hash: string;
  }>;
  preamble: {
    title: string;
    description: string;
    version: string;
  };
}
```

### Substandard Type
```typescript
interface Substandard {
  id: string;
  name: string;
  description: string;
  constraints: string[];
  validatorHash?: string;
}
```

### Mint Request Type
```typescript
interface MintRequest {
  walletAddress: string;
  tokenName: string;
  tokenSymbol: string;
  amount: number;
  substandardId: string;
  metadata?: Record<string, any>;
}
```

### Mint Response Type
```typescript
interface MintResponse {
  txCbor: string;      // Unsigned transaction CBOR
  txHash: string;      // Expected transaction hash
  fee: string;         // Transaction fee in lovelace
  tokenId: string;     // Policy ID + Asset name
}
```

---

## Questions to Answer

### API Questions:
1. ✅ What's the base URL? - `http://localhost:8080`
2. ✅ Blueprint endpoint? - `GET /api/v1/protocol/blueprint`
3. ✅ Substandards endpoint? - `GET /api/v1/substandards`
4. ❓ **Exact mint endpoints from IssueTokenController?**
5. ❓ **What parameters are required for minting?**
6. ❓ **What does the mint request/response look like?**
7. ❓ **How to handle metadata (CIP-25, CIP-68)?**
8. ❓ **Does the API handle policy creation or is policy pre-existing?**
9. ❓ **Are there different endpoints for different token types?**
10. ❓ **Authentication required for API calls?**

### Network Questions:
11. ❓ **Is API URL different per network (preview/preprod/mainnet)?**
12. ❓ **Does the backend API run per network or single instance?**

### Transaction Questions:
13. ❓ **Does backend return signed or unsigned transaction?**
14. ❓ **Who pays transaction fees - minter or protocol?**
15. ❓ **Are reference scripts used or inline scripts?**

---

## Success Criteria

- [ ] User can load available substandards from API
- [ ] User can fill out token minting form
- [ ] User can select validation logic (substandard)
- [ ] Backend builds minting transaction
- [ ] Frontend displays transaction preview
- [ ] User can sign transaction with wallet
- [ ] Transaction submits successfully to blockchain
- [ ] User sees confirmation with transaction hash
- [ ] Error handling works for all failure cases
- [ ] UI shows loading states appropriately

---

## File Structure

```
app/
  mint/
    page.tsx                           # Main mint page
components/
  mint/
    mint-form.tsx                      # Form component
    substandard-selector.tsx           # Substandard picker
    transaction-builder-toggle.tsx     # Backend/Frontend toggle
    transaction-preview.tsx            # Preview before signing
    transaction-status.tsx             # Status display
lib/
  api/
    client.ts                          # Base API client
    protocol.ts                        # Protocol API
    substandards.ts                    # Substandards API
    minting.ts                         # Minting API
  contracts/
    mint-transaction.ts                # Transaction building (future)
types/
  api.ts                               # API types
  protocol.ts                          # Protocol types
  minting.ts                           # Minting types
hooks/
  use-mint-token.ts                    # Minting hook
  use-protocol-data.ts                 # Protocol data hook
  use-substandards.ts                  # Substandards hook
```

---

## Next Steps

1. **Answer API questions** - Get mint endpoint details from backend
2. **Create API integration layer** - Set up API client and types
3. **Build minting page UI** - Create form and components
4. **Implement backend flow** - Connect to backend API
5. **Test end-to-end** - Mint token on preview network
6. **Polish UX** - Add error handling, loading states

---

## Notes

- This is an **educational project** - goal is to show both approaches
- Backend mode is simpler and more reliable initially
- Frontend mode requires understanding protocol details
- Different token types may need different minting flows (iterative)
- Keep toggle UI visible but disabled until frontend mode is ready
- Consider adding transaction history/explorer links
- May need to handle CIP-25 or CIP-68 metadata standards

---

**Status:** Waiting for mint API specification from backend team
