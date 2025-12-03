# Deployment Packages

## v0.1

```
set LockdropPkg 0xfdd5779ce1f081b940c23070c7268edecaf9df2904fbda76f201816c3fef8f4d
set AdminCap 0x44a7d032ee07dbf93023acba6a38c09c6c8e1f13926d210552abbdaa32be254d
set MyCoinType 0xfb8ded87111165ea690d825a4d70be6d86d0602c4cd5a9776acc3fe795229d4::tokens::MyCoin

UpgradeCap: 0x1fab0ea520bbffbdf9b26a7cababd7602c8d28dcc6a85095a2ba47832f6312cf
```

Created lockdrops:

```
set LockdropId 0x11613fb91149e1f36a6c0f013f60c5d9e1150431f7e874c09cbf85b803bc4fc3
```

## Usage

```
sui client call --package $LockdropPkg --module lockdrop \
  --function new \
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
