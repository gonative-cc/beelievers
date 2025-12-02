# Beelievers Lockdrop - Native BTC liquidity campaign

_Contribute to the Hive. Claim Your Place in the Future of BTCFi._

The project goal is to incentivize early liquidity providers to lock Sui accepted coins, that will swapped to nBTC at mainnet launch.
This is paired with the Hive Point campaign.

## Spec


Roles:

- Users
- Admin

Contract attributes

- list of accepted coins
- start time
- end time


## Flow

- When deploying the package, AdminCap is created and transferred to the sender.
- Admin can create new Lockdrop object (start and end time).
- Admin can add new coin types to list of accepted coins. This must be done before the campaign start time.
- Users deposit any of the accepted coins.
- Deposits are locked until admin will swap the coins to nBTC. nBTC type and coin will be created at Native mainnent launch (so now, the nBTC package ID and it's full type name is unknown).
- When doing a deposit, relevant event is issued.
  - That event is captured by the TBook point system to calculate points and tiers.
- Users can do multiple deposits. The balances are aggregated.
- At the end of the Lockdrop program (after end_time), admin can withdraw all balances swap them for a nBTC and send that coin back to the contract.
- Admin assigns nBTC conversion rates for each accepted currency.
- Users can withdraw claim nBTC based on their deposit coins.

Additional functions:

- Allow anyone to query any user balance.

Additional Admin functions:

- update start and end time
- pause the contract
