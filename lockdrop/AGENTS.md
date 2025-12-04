# Beelievers Lockdrop Project

## Project Overview

This is a Sui Move-based lockdrop contract implementation for the Beelievers project. The lockdrop allows users to deposit Sui accepted coins which will be locked and swapped for nBTC (Native Bitcoin) at mainnet launch. This is paired with the Hive Point campaign to incentivize early liquidity providers.

The project is written in Sui Move using the 2024.beta edition and follows the standard Sui Move package structure. Key features include:

- Admin-controlled contract with AdminCap pattern
- Time-based lockdrop with start/end times
- Support for multiple accepted coin types
- User deposit tracking and balance queries
- Rate-based conversion from deposits to nBTC
- Pausing functionality for admin control

Project spec and description: @README.md

## Architecture

### Main Components

- **sources/lockdrop.move**: Core contract implementation containing all logic
- **Move.toml**: Package configuration and dependencies
- **tests**: Directory for tests.

### Contract Structure

- `AdminCap`: Privileged role object created during package deployment
- `Lockdrop`: Main contract object with time controls, accepted coins list, and deposit tracking
- `DepositEvent`/`WithdrawEvent`: Event structures for external monitoring
- Various helper functions for coin type management and balance calculations
- Uses dynamic field to set nBTC type and balance in the future (type is unknown at the lockdrop creation).

## Building and Running

### Prerequisites

- Sui CLI tools installed and configured
- Sui network access (devnet/testnet/mainnet)

### Build Commands

```bash
# Build the package
sui move build

# Run tests
sui move test

# Publish the package
sui move publish
```

## Key Functions

### Admin Functions

- `new()`: Create a new lockdrop instance
- `add_accepted_coin<T>()`: Add new coin types to accept
- `set_time()`: Update start/end times
- `set_pause()`: Pause/unpause the contract
- `withdraw_deposit_to_swap<T>()`: Withdraw deposited coins for conversion
- `deposit_nbtc<T>()`: Deposit converted nBTC back to contract
- `set_rates()`: Set conversion rates for each coin type

### User Functions

- `deposit<T>()`: Deposit accepted coins into the lockdrop
- `claim<T>()`: Claim converted nBTC based on deposits
- `get_user_deposits()`: Query user's deposit balances

### Test helper functions

- `create_admin_cap`: creates Admin Cap for testing.

### Test instrcutions

See:

- https://intro.sui-book.com/unit-three/lessons/7_unit_testing.html
- Full example: https://docs.sui.io/guides/developer/app-examples/trustless-swap#testing

## Development Conventions

- Uses Sui Move 2024.beta edition
- Implements AdminCap pattern for access control
- Follows Sui Move coding conventions
- Emits events for external tracking by point systems
- Use helper functions whenever possible to avoid code duplication.
- Create common setup code for tests.
- Create common checker code for tests to avoid duplications.

## Dependencies

The contract depends on:

- Sui Framework (SUI, Coin, Clock, etc.)
- Move Standard Library
- Sui System packages

All dependencies are specified in the Move.toml and Move.lock files.
