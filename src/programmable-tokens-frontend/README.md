# CIP-113 Programmable Tokens Frontend

A Next.js web application for interacting with CIP-113 programmable tokens on Cardano.

## Features

- 🔐 Wallet connection (Nami, Eternl, Lace, Flint)
- 🌐 Multi-network support (Preview, Preprod, Mainnet)
- 🚀 Protocol deployment
- 💎 Token minting with configurable validation logic
- 📤 Token transfers with automatic validation
- 🚫 Blacklist management for regulated tokens

## Tech Stack

- **Next.js 15** with TypeScript
- **Mesh SDK** for Cardano transactions
- **Tailwind CSS** with Forest Night theme
- **React Hook Form** + Zod for form validation
- **Blockfrost API** for blockchain queries

## Getting Started

### Prerequisites

- Node.js 18+ (20+ recommended)
- npm or yarn
- Blockfrost API key for Preview testnet

### Installation

1. Clone the repository
2. Install dependencies:

```bash
npm install
```

3. Create environment file:

```bash
cp .env.preview.example .env.preview
```

4. Add your Blockfrost API key to `.env.preview`:

```
NEXT_PUBLIC_BLOCKFROST_API_KEY=your_preview_api_key_here
NEXT_PUBLIC_NETWORK=preview
```

### Development

Run the development server:

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

## Project Structure

```
programmable-tokens-frontend/
├── app/                    # Next.js app router
│   ├── layout.tsx
│   ├── page.tsx
│   ├── deploy/
│   ├── dashboard/
│   ├── mint/
│   ├── transfer/
│   └── blacklist/
├── components/
│   ├── ui/                 # Reusable UI components
│   ├── wallet/             # Wallet connection
│   ├── forms/              # Form components
│   └── layout/             # Layout components
├── lib/
│   ├── mesh/               # Mesh SDK utilities
│   ├── contracts/          # Smart contract interactions
│   ├── config/             # Configuration management
│   └── utils/              # Helper functions
├── config/
│   ├── cip113-blueprint.json
│   ├── protocol-bootstrap.example.json
│   └── substandards/
│       └── simple-transfer.json
└── public/
```

## Configuration

### Network Configuration

The app supports multiple networks. Set the network in your `.env` file:

```bash
NEXT_PUBLIC_NETWORK=preview  # or preprod, mainnet
```

### CIP-113 Blueprint

The main CIP-113 smart contract definitions are in `config/cip113-blueprint.json`.

### Protocol Bootstrap

After deploying the protocol, a `protocol-bootstrap.json` file is generated with deployment details.

### Substandards

Transfer logic configurations are in `config/substandards/`:
- `simple-transfer.json` - Basic transfer validation
- More to be added (blacklist, whitelist, etc.)

## Development Phases

- [x] Phase 1: Setup & Foundation
- [x] Phase 2: Core UI Components
- [x] Phase 3: Protocol Deployment (UI ready, backend pending)
- [x] Phase 4: Token Minting Flow
- [x] Phase 5: Transfer & Dashboard
- [x] Phase 6: Testing (65 unit tests)
- [ ] Phase 7: Blacklist Substandard (Coming Soon)

## Testing

Run the test suite:

```bash
npm test           # Run tests once
npm run test:watch # Run tests in watch mode
```

**Test Coverage:**
- API client tests (7 tests)
- Minting API tests (19 tests)
- Validation tests (26 tests)
- Hook tests (5 tests)
- Type tests (8 tests)

## License

Apache License 2.0 - see the [LICENSE](../LICENSE) file for details.

Copyright 2024 Cardano Foundation

## Acknowledgments

Built on top of the CIP-113 standard and the original CIP-143 implementation by Phil DiSarro and the IOG Team.
