# Deployment Packages

## v0.2

```
set LockdropPkg 0xd244750dc02f917b2d539c5b68e14afbfc4e58920f04a0587692f8c6920e94ea
set AdminCap 0x366413a8ef36d78ac3b3080567482d3fb636b54f1af76c34b02073c4043dcf8d 
set USDCType 0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC

UpgradeCap: 0x6bb2bff1f08d99eb13bce3030442a3a74b2b2064844009542978995fd3f61e43
```

Created lockdrops:

```
set LockdropId 0xb4b2841c611936bebb2aa0a8ba77dbbdf65ca8752e4326de6b948c384a0b4335
```

## v0.1

```
set LockdropPkg 0xfdd5779ce1f081b940c23070c7268edecaf9df2904fbda76f201816c3fef8f4d
set AdminCap 0x44a7d032ee07dbf93023acba6a38c09c6c8e1f13926d210552abbdaa32be254d
set MyCoinType 0xfb8ded87111165ea690d825a4d70be6d86d0602c4cd5a9776acc3fe795229d4::tokens::MyCoin
set USDCType 0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC

UpgradeCap: 0x1fab0ea520bbffbdf9b26a7cababd7602c8d28dcc6a85095a2ba47832f6312cf
```

Created lockdrops:

```
set LockdropId 0x11613fb91149e1f36a6c0f013f60c5d9e1150431f7e874c09cbf85b803bc4fc3
set LockdropId 0x2e1f5ebf89440afc4592765c1cc82b6bd872dc67f9e3ad9f229a3e3528de35a5
```

## Usage

```
sui client call --package $LockdropPkg --module lockdrop \
  --function new \
  --type-args $USDCType \
  --args $AdminCap START_TIMESTAMP_MS  END_TIMESTAMP_MS \
  --gas-budget 10000000
```

Split coins:

```
sui client split-coin --coin-id COIN_OBJECT_ID \
  --amounts AMOUNT_TO_SPLIT \
  --gas-budget 10000000
```

Add Accepted Coin

```
sui client call --package $LockdropPkg --module lockdrop --function add_accepted_coin \
  --type-args $MyCoinType \
  --args $LockdropId $AdminCap 0x6 \
  --gas-budget 5000000
```

Deposit SUI

```
sui client call --package $LockdropPkg --module lockdrop --function deposit \
  --type-args "0x2::sui::SUI" \
  --args $LockdropId 0x6 COIN_OBJECT_ID_TO_DEPOSIT \
  --gas-budget 5000000
```

Query deposits:

```
sui client call --package $LockdropPkg --module lockdrop --function get_user_deposits \
  --args $LockdropId USER_ADDR \
  --dev-inspect
```

Withdraw Source Deposits (0x6 is the Clock object address)

```
sui client ptb \
  --move-call $LockdropPkg::lockdrop::withdraw_deposits_to_swap<0x2::sui::SUI> <ADMIN_CAP_ID> $LockdropId 0x6 \
  --transfer-objects [0] @<YOUR_ADDRESS> \
  --gas-budget 10000000
```

Withdraw nBTC

```
sui client ptb \
  --move-call $LockdropPkg::lockdrop::claim<0x::tokens::BeeliverBtc> $LockdropId \
  --transfer-objects [0] @<YOUR_ADDRESS> \
  --gas-budget 10000000
```
