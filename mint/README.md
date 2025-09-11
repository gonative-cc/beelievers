# Beelievers Mint Contract & Setup

This directory contains the Beelievers NFT minting contract and complete setup infrastructure for both testnet and mainnet deployment.

## 🏗️ Contract Overview

### Key Features

- **Total Supply**: 6,021 NFTs
- **Mythic Supply**: 21 NFTs (special rarity)
- **Normal Supply**: 6,000 NFTs
- **Mythic Eligibility System**: Special addresses can mint mythic NFTs
- **Auction Integration**: Auction winners can mint normal NFTs
- **Badge System**: Dynamic badge assignment
- **Premint System**: Controlled premint for specific ranges
- **Metadata Management**: Comprehensive NFT metadata and URL management

## 🚀 Setup Script Usage

### Dependencies

See the parent [../README](../README.md#dependencies)

### Setup

Install dependencies:

```sh
cd mint
bun install
```

Firstly we need to deploy auction:

```bash
cd ../beelievers_mint; sui client publish --gas-budget 500000000
# NOTE: save the auction pkg ID
set auction_pkg 0x...

# create auction
sui client ptb --move-call $auction_pkg::auction::create 30  --gas-budget 50000000
set auction_id 0x...
```

Now we can publish mint package. During the `init` of the package, mint object is created and
shared publicly.

```bash
cd ../mint
sui client publish --gas-budget 500000000
```

Copy IDs of the following objects PackageId, AdminCap, Collection, TransferPolicy, TransferPolicyCap, Publisher
and past them in `setup_script.js`.
Set the private key as well.

For LOCALNET we need to deploy kiosk:

```bash
git clone https://github.com/MystenLabs/apps.git sui-apps
cd sui-apps/kiosk
sui move publish
set kiosk_pkg 0x...
```

### Run minting scripts

```bash
# localnet test
node setup_script.js local

# reduced testnet:
node setup_script.js test
```

### Command Options

```bash
# Skip premint process
node setup_script.js test --skip-premint

# Skip minting start
node setup_script.js production --skip-minting
```

## 📊 Data Files

### 1. `mythic_eligible.txt`

- **Purpose**: Contains addresses eligible for mythic NFT minting
- **Format**: One address per line (with or without 0x prefix)
- **Count**: 3,977 addresses
- **Usage**: Production environment reads this file

### 2. `badges.json`

- **Purpose**: Maps addresses to badge numbers
- **Format**: `{ "address": [badge_numbers] }`
- **Example**:

```json
{
  "0x123...": [1, 3, 5],
  "0x456...": [2, 4]
}
```

### 3. `badge_names.json`

- **Purpose**: Maps badge numbers to display names
- **Format**: `{ "badge_names": { "1": "Early Adopter", "2": "Whale" } }`
- **Example**:

```json
{
  "badge_names": {
    "1": "Early Adopter",
    "2": "Whale",
    "3": "OG"
  }
}
```

### 4. `imagelinks.json`

- **Purpose**: Maps NFT token IDs to image URLs
- **Format**: `{ "1": "https://walrus.tusky.io/image1.jpg" }`
- **Count**: 6,021 entries (one per NFT)

### 5. `JSON/` Directory

- **Purpose**: Individual NFT metadata files
- **Format**: One JSON file per NFT (1.json to 6021.json)
- **Structure**:

```json
{
  "attributes": [
    { "trait_type": "Background", "value": "Blue" },
    { "trait_type": "Eyes", "value": "Green" }
  ]
}
```

## 🔧 Environment Configuration

### Test Environment

- **RPC**: Testnet (`https://fullnode.testnet.sui.io:443`)
- **Package ID**: `0x3064d43ee6cc4d703d4c10089786f0ae805b24d2d031326520131d78667ffc2c`
- **Processing**: First 21 NFTs only (attributes & URLs)
- **Mythic Eligible**: 9 hardcoded test addresses
- **Premint**: Skipped, manually set as completed

### Production Environment

- **RPC**: Mainnet (`https://fullnode.mainnet.sui.io:443`)
- **Package ID**: (To be set)
- **Processing**: All 6,021 NFTs
- **Mythic Eligible**: From `mythic_eligible.txt` (3,978 addresses)
- **Premint**: Full execution (NFTs #1-210)

## 🎯 Setup Process

### Complete Setup Flow

1. **Add Mythic Eligible** - Configure special addresses
2. **Set Badge Names** - Define badge display names
3. **Set Minter Badges** - Assign badges to addresses
4. **Set NFT Attributes** - Configure NFT metadata
5. **Set NFT URLs** - Set image URLs for each NFT
6. **Set Badge Display** - Configure which badges are visible
7. **Add Royalty Rules** - Set 5% royalty and lock rules
8. **Execute Premint** - Mint initial NFTs (production only)
9. **Start Minting** - Enable public minting

### Batch Processing

- **Batch Size**: 50 NFTs per transaction
- **Delay**: 5 seconds between batches
- **Gas Budget**: 1 SUI per transaction

## 🔑 Key Contract Functions

### Admin Functions

```move
// Add mythic eligible addresses
add_mythic_eligible(admin_cap, collection, addresses)

// Set badge names
set_bulk_badge_names(admin_cap, collection, badge_ids, names)

// Set minter badges
set_bulk_minter_badges(admin_cap, collection, addresses, badges)

// Set NFT attributes
set_bulk_nft_attributes(admin_cap, collection, nft_ids, keys, values)

// Set NFT URLs
set_bulk_nft_urls(admin_cap, collection, nft_ids, urls)

// Start minting
start_minting(admin_cap, collection, start_time)
```

### Public Functions

```move
// Mint an NFT
mint(collection, transfer_policy, random, clock, auction, kiosk, kiosk_cap)

// Check eligibility
is_mythic_eligible(collection, address)
has_minted(collection, address)

// Get collection stats
get_collection_stats(collection)
```

## 🧪 Testing

### Run Contract Tests

```bash
# Build & deploy testnet contract
sui move build
node setup_script.js test
```

### Test Minting

```bash
# Test minting functionality after setup
node setup_script.js test-minting
```

### Check Collection Stats

The setup script includes automatic stats checking after operations.

## ⚙️ Configuration

### Environment Variables

- `ADMIN_PRIVATE_KEY`: Admin wallet private key (set in script)
- `MINT_START_TIME`: Timestamp when minting starts (in milliseconds)

### Customization

- Modify `CONFIGS` object in `setup_script.js` for different environments
- Adjust batch sizes and delays for network conditions
- Update package IDs and contract addresses for deployment

## 🚨 Error Handling

### Common Errors

- `EInsufficientSupply`: No more NFTs available
- `EMintingNotActive`: Minting not started or paused
- `EUnauthorized`: Address not eligible for minting
- `EAlreadyMinted`: Address already minted
- `EInsufficientPayment`: Insufficient payment amount

### Error Recovery

- Failed batches can be retried
- Use `--skip-premint` or `--skip-minting` to resume from specific step
- Check transaction digests for detailed error information

## 📈 Monitoring

### Collection Stats

```move
// Returns: (total_minted, mythic_minted, normal_minted, available_mythics, available_normals)
get_collection_stats(collection)
```

### Event Monitoring

- `NFTMinted`: Emitted when NFT is minted
- `MythicEligibleAdded`: Emitted when mythic eligible added
- `MintingStarted`: Emitted when minting starts
- `PremintCompleted`: Emitted when premint finishes

## 🔒 Security Features

- **Transfer Policy**: Royalty and lock rules
- **Admin Controls**: Restricted admin functions
- **Eligibility Checks**: Address validation for mythic minting
- **Payment Validation**: Proper payment amount verification
- **Auction Integration**: Validates auction contract

## 📝 Notes

- Test environment processes limited NFTs to save gas
- Production environment requires all data files to be present
- Mythic eligible addresses are processed in batches of 50
- Premint is skipped on testnet for cost efficiency
- All transactions include proper gas budgeting

## 🆘 Troubleshooting

### Common Issues

1. **File Not Found**: Ensure all data files are in the correct location
2. **Gas Errors**: Increase gas budget in transaction blocks
3. **Batch Failures**: Check network conditions and retry
4. **Permission Errors**: Verify admin private key and capabilities
