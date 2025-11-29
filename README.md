# DCCP Smart Contracts

Smart contracts for the **Decentralized Carbon Credit Platform (DCCP)**, built using [Foundry](https://getfoundry.sh/).

These contracts manage the lifecycle of carbon credits, from project registration and auditing to trading and final retirement (offsetting).

## Contracts Overview

### 1. CarbonCreditToken (`src/Main.sol`)
An **ERC1155** token contract that represents the carbon credits themselves.
- **Project Management**: Handles project submission, verification, and approval.
- **Roles**:
  - `REGISTRY_ROLE`: Can approve projects and mint credits (Admin).
  - `AUDITOR_ROLE`: Can verify project documentation and assign status.
  - `CONSULTANT_ROLE`: Advisory role.
- **Lifecycle**: `Submitted` -> `UnderAudit` -> `Approved` -> `Active` (Minting allowed) -> `Completed`.

### 2. CarbonCreditMarketplace (`src/Auction.sol`)
A comprehensive marketplace for trading Carbon Credits.
- **Listing Types**:
  - **English Auction**: Classic auction where price increases with bids.
  - **Dutch Auction**: Price starts high and decreases over time until bought.
  - **Fixed Price**: Instant purchase at a set price.
- **RFPs (Request for Proposals)**: Buyers can post requirements for credits they wish to purchase.
- **Escrow**: Credits are held in escrow during active listings.

### 3. RetirementCertificateNFT (`src/NFT.sol`)
An **ERC721** NFT contract that serves as a proof of retirement (offset certificate).
- **Retirement**: Users "burn" their ERC1155 credits to mint this NFT.
- **Certificate**: Contains immutable details about the offset (amount, project, beneficiary, reason).
- **Reporting**: Generates retirement reports for users.

## Development

### Prerequisites
Ensure you have **Foundry** installed:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build
Compile the contracts:
```bash
forge build
```

### Test
Run the test suite:
```bash
forge test
```

### Deploy
Deploy the contracts to a network (e.g., Sepolia, Local Anvil):

```bash
# Start local node
anvil

# Deploy
forge script script/Deploy.s.sol:DeployScript --rpc-url http://127.0.0.1:8545 --private-key <PRIVATE_KEY> --broadcast
```

## Architecture

1. **Project Developer** submits a project -> `CarbonCreditToken`.
2. **Auditor** verifies and approves the project.
3. **Registry** mints credits to the Developer.
4. **Developer** lists credits on `CarbonCreditMarketplace`.
5. **Buyers** purchase credits via Auction or Fixed Price.
6. **Holders** retire credits via `RetirementCertificateNFT` to offset emissions.
