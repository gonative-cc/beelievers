# Finalize Auction

## How to run

### 1. Install dependencies

See the scripts [README](./README.md) file.

### 2. Create `.env` file

```env
NETWORK="mainnet"
# specify mnemonic or a secret key
MNEMONIC="your mnemonic"
# or:
SK="suiprivkey1..."
```

### 3. Execute scripts

Update ./scripts/auction.config.ts to match with package id, auction id and admin cap of your auction.

We should prepare the auction winner list: a text file with Sui addresses, one address per line, example:

```text
0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
```

Set the winner list to auction

```bash
bun beelievers_auction_finalize.js set-winners data.txt
```

Finalize the auction with clearing price set in the auction.config.ts.
Before running, double check if you need to specify `discounts` in the config.

```bash
bun beelievers_auction_finalize.js finalize
```

Run Ruffle

```bash
bun beelievers_auction_finalize.js raffle
```
