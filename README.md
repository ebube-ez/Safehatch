# SafeHatch - Multi-Party Escrow System

## Overview

SafeHatch is a decentralized, multi-party escrow system designed to secure transactions between buyers, sellers, and arbiters. It ensures that funds are held safely until all parties agree, with a structured dispute resolution mechanism when conflicts arise. The system integrates arbiter reputation tracking, percentage-based dispute resolutions, and emergency administrative controls for maximum security.

## Key Features

* **Escrow Management**: Create, fund, confirm, complete, or refund escrows with automated fund handling.
* **Dispute Resolution**: Structured system where arbiters resolve disputes and distribute funds based on percentage allocation.
* **Arbiter Registry**: Arbiters register with fee rates, build reputation, and toggle their availability.
* **Transaction Transparency**: Comprehensive audit trail with detailed transaction history for each escrow.
* **Emergency & Admin Controls**: Owner can pause/unpause operations, adjust fees, and enable emergency mode.
* **Reputation System**: Tracks arbiters’ dispute outcomes and reputation scores for accountability.

## Contract Components

* **Error Constants**: Standardized codes for invalid states, unauthorized access, insufficient funds, expired escrows, and more.

* **Contract Constants**: Includes fee caps, duration limits, minimum amounts, and protocol fee precision.

* **Data Variables**:

  * `next-escrow-id` - Unique identifier for escrows.
  * `protocol-fee` - Percentage fee for protocol sustainability.
  * `fee-recipient` - Recipient address for protocol fees.
  * `contract-paused` / `emergency-mode` - System control switches.
  * `total-escrows-created` / `total-volume` - Global activity stats.

* **Data Maps**:

  * `escrows` - Main escrow records.
  * `deposits` - Records deposits with metadata for auditing.
  * `arbiters` - Arbiter registry with reputation and fees.
  * `escrow-participants` - Quick lookup of participants by role.
  * `transaction-history` - Records actions in sequence for transparency.
  * `transaction-sequences` - Tracks sequence numbers for escrow events.

## Functions

### Escrow Lifecycle

* `create-escrow` - Initiate a new escrow with buyer, seller, and arbiter.
* `fund-escrow` - Deposit STX into escrow.
* `confirm-completion` - Buyer and seller confirm transaction, releasing funds.
* `refund-escrow` - Refunds depositor if escrow expires or is canceled.

### Dispute Resolution

* `file-dispute` - Buyer or seller raises a dispute with detailed reason.
* `resolve-dispute` - Arbiter resolves dispute with percentage-based fund distribution.

### Arbiter System

* `register-arbiter` - Register as an arbiter with profile and fee rate.
* `update-arbiter-profile` - Update arbiter’s name or fee rate.
* `toggle-arbiter-status` - Enable or disable availability.

### Administration

* `pause-contract` / `unpause-contract` - Temporarily halt contract operations.
* `emergency-pause` / `emergency-unpause` - Force emergency state to protect funds.
* `update-protocol-fee` - Adjust fee charged by the protocol.
* `update-fee-recipient` - Change recipient of protocol fees.

### Read-Only Queries

* `get-escrow` - Fetch details of an escrow.
* `get-arbiter` - Retrieve arbiter details and reputation.
* `get-deposit` - View deposit records for auditing.
* `get-transaction-history` - View full action log of escrow.
* `get-contract-info` - General contract configuration and owner.
* `get-contract-stats` - Aggregated usage and volume statistics.

## Usage Flow

1. **Arbiter Registration**: Arbiters join the registry and set their fee rates.
2. **Escrow Creation**: Buyer (or seller) initiates an escrow, specifying counterparties and arbiter.
3. **Funding**: Funds are deposited securely into escrow.
4. **Completion or Refund**:

   * If both parties confirm, funds are released.
   * If escrow expires or is canceled, funds are refunded.
5. **Disputes**: Either party may raise a dispute, with arbiter resolving and distributing funds accordingly.
6. **Reputation & Transparency**: Arbiter statistics and transaction logs ensure accountability.

## Security Highlights

* Escrow can only be funded once and is locked until completion, refund, or resolution.
* Arbiter reputation incentivizes fair dispute handling.
* Emergency controls safeguard against vulnerabilities or attacks.
* Comprehensive logging ensures transparency in every transaction.
