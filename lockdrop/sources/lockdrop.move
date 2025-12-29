module beelievers_lockdrop::lockdrop;

use std::type_name::{TypeName, with_defining_ids};
use sui::balance::Balance;
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;
use sui::table::{Self, Table};

/// Package version
const VERSION: u8 = 1;

// === Errors ===
const ENotActive: u64 = 1;
const EInvalidTime: u64 = 2;
const EWrongCoin: u64 = 3;
const EVersionMismatch: u64 = 4;
const EStarted: u64 = 5;
const ERateNotSet: u64 = 6;
const EWrongLen: u64 = 7;
const ELockdropEnded: u64 = 8;
const ELockdropNotEnded: u64 = 9;
const ENoDeposit: u64 = 10;

const StatusPaused: u8 = 1;
const StatusCancelled: u8 = 2;

// === Events ===
public struct DepositEvent has copy, drop {
    user: address,
    coin_type: TypeName,
    amount: u64,
    total_amount: u64,
}

public struct WithdrawEvent has copy, drop {
    user: address,
    total_claim: u64,
}

// === Structs ===

public struct AdminCap has key, store {
    id: UID,
}

public struct Lockdrop has key {
    id: UID,
    version: u8,
    start_time: u64,
    end_time: u64,
    status: u8,
    nbtc_type: Option<TypeName>,
    /// Set of accepted Coin types.
    accepted: vector<TypeName>,
    vault: sui::bag::Bag,
    /// User accounting (Deposits).
    /// Key: User Address, Value: vector mapping CoinType index (based on the accepted coins) -> Total balance Amount
    deposits: Table<address, vector<u64>>,
    /// Withdraw rates. Withdraw Amount = deposit[i] * rates[i] / divisor.
    rates: vector<u64>,
    rates_divisor: u64,
}

// === Init ===

/// Only creates the AdminCap.
/// The actual Lockdrop logic is moved to `create_lockdrop`.
fun init(ctx: &mut TxContext) {
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

// === Admin Functions (Creation) ===

/// callable by Admin to create a new Lockdrop instance.
public fun new<T>(_: &AdminCap, start: u64, end: u64, ctx: &mut TxContext) {
    let accepted = vector[with_defining_ids<T>()];

    let lockdrop = Lockdrop {
        id: object::new(ctx),
        version: VERSION,
        start_time: start,
        end_time: end,
        status: 0, // Default to active since we are setting times now
        nbtc_type: option::none(),
        accepted,
        vault: sui::bag::new(ctx),
        deposits: table::new(ctx),
        rates: vector::empty(),
        rates_divisor: 0,
    };

    transfer::share_object(lockdrop);
}

// === User Functions ===

public fun deposit<T>(
    lockdrop: &mut Lockdrop,
    clock: &Clock,
    coin_in: Coin<T>,
    ctx: &mut TxContext,
) {
    assert!(lockdrop.version == VERSION, EVersionMismatch);
    let now = clock.timestamp_ms();

    assert!(lockdrop.status == 0, ENotActive);
    assert!(now >= lockdrop.start_time, EInvalidTime);
    assert!(now <= lockdrop.end_time, ELockdropEnded);

    let (idx, coin_type) = lockdrop.get_cointype<T>();
    let sender = ctx.sender();
    let amount = coin_in.value();
    let b = coin_in.into_balance();

    // 1. Handle Physical Coin Storage
    if (lockdrop.vault.contains(coin_type)) {
        let balance: &mut Balance<T> = lockdrop.vault.borrow_mut(coin_type);
        balance.join(b);
    } else {
        lockdrop.vault.add(coin_type, b);
    };

    // 2. Handle User Accounting
    let total_amount = if (!lockdrop.deposits.contains(sender)) {
        let mut user_deposits = zeros_vector(lockdrop.accepted.length());
        let a = &mut user_deposits[idx];
        *a = amount;
        lockdrop.deposits.add(sender, user_deposits);
        amount
    } else {
        let a = &mut lockdrop.deposits[sender][idx];
        *a = *a + amount;
        *a
    };

    event::emit(DepositEvent {
        user: sender,
        coin_type,
        amount,
        total_amount,
    });
}

public fun claim<ResultCoin>(lockdrop: &mut Lockdrop, ctx: &mut TxContext): Coin<ResultCoin> {
    assert!(lockdrop.version == VERSION, EVersionMismatch);
    assert!(lockdrop.status == 0, ENotActive);
    let sender = ctx.sender();
    let result_type = with_defining_ids<ResultCoin>();

    assert!(lockdrop.nbtc_type.is_some_and!(|t| t == result_type), EWrongCoin);
    assert!(lockdrop.rates.length() > 0, ERateNotSet);

    // remove user deposit to prevent double spend
    let deposits = lockdrop.deposits.remove(sender);
    let mut total_claim = 0;
    let mut i = 0;
    let len = lockdrop.accepted.length();
    while (i < len) {
        total_claim = total_claim + deposits[i] * lockdrop.rates[i] / lockdrop.rates_divisor;
        i = i + 1;
    };

    event::emit(WithdrawEvent {
        user: sender,
        total_claim,
    });

    let vault_balance: &mut Balance<ResultCoin> = lockdrop.vault.borrow_mut(result_type);
    coin::from_balance(vault_balance.split(total_claim), ctx)
}

#[allow(lint(self_transfer))]
public fun claim_and_transfer<ResultCoin>(l: &mut Lockdrop, ctx: &mut TxContext) {
    let result = claim<ResultCoin>(l, ctx);
    transfer::public_transfer(result, ctx.sender());
}

/// In case the lockdrop is cancelled, allows user withdraw his deposit.
/// Fails if the user didn't deposit the given coin or already withdrawn it.
public fun claim_cancelled<ResultCoin>(
    lockdrop: &mut Lockdrop,
    ctx: &mut TxContext,
): Coin<ResultCoin> {
    assert!(lockdrop.version == VERSION, EVersionMismatch);
    assert!(lockdrop.status == StatusCancelled, ENotActive);

    let sender = ctx.sender();
    let (idx, coin_type) = lockdrop.get_cointype<ResultCoin>();

    let amount = &mut lockdrop.deposits[sender][idx];
    assert!(*amount > 0, ENoDeposit);
    let balance: &mut Balance<ResultCoin> = lockdrop.vault.borrow_mut(coin_type);
    let c = coin::take(balance, *amount, ctx);
    *amount = 0;
    c
}

public fun get_user_deposits(lockdrop: &Lockdrop, user: address): vector<u64> {
    if (!lockdrop.deposits.contains(user)) {
        return vector[]
    };
    *lockdrop.deposits.borrow(user)
}

// === Admin Functions (Management) ===

// NOTE: should be done before the lockdrop is active
public fun add_accepted_coin<T>(lockdrop: &mut Lockdrop, _: &AdminCap, clock: &Clock) {
    let now = clock.timestamp_ms();
    assert!(now < lockdrop.start_time, EStarted);

    let type_key = with_defining_ids<T>();
    assert!(!lockdrop.accepted.contains(&type_key), EWrongCoin);
    lockdrop.accepted.push_back(type_key);
}

public fun set_time(lockdrop: &mut Lockdrop, _: &AdminCap, start: u64, end: u64) {
    lockdrop.start_time = start;
    lockdrop.end_time = end;
}

public fun set_status(lockdrop: &mut Lockdrop, _: &AdminCap, status: u8) {
    lockdrop.status = status;
}

public fun withdraw_deposit_to_swap<T>(
    lockdrop: &mut Lockdrop,
    _: &AdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    assert!(lockdrop.version == VERSION, EVersionMismatch);
    let now = clock.timestamp_ms();
    assert!(now > lockdrop.end_time, ELockdropNotEnded);

    let type_key = with_defining_ids<T>();
    let balance: &mut Balance<T> = lockdrop.vault.borrow_mut(type_key);

    coin::from_balance(balance.withdraw_all(), ctx)
}

// Can deposit multiple times, but each time must be the same coin
public fun deposit_nbtc<ResultCoin>(lockdrop: &mut Lockdrop, _: &AdminCap, nBTC: Coin<ResultCoin>) {
    assert!(lockdrop.version == VERSION, EVersionMismatch);
    let type_key = with_defining_ids<ResultCoin>();

    if (lockdrop.nbtc_type.is_none()) {
        lockdrop.nbtc_type.fill(type_key);
    } else {
        assert!(*lockdrop.nbtc_type.borrow() == type_key, EWrongCoin);
    };

    if (!lockdrop.vault.contains(type_key)) {
        lockdrop.vault.add(type_key, nBTC.into_balance());
    } else {
        let bal: &mut Balance<ResultCoin> = lockdrop.vault.borrow_mut(type_key);
        bal.join(nBTC.into_balance());
    };
}

public fun set_rates(lockdrop: &mut Lockdrop, _: &AdminCap, rates: vector<u64>, divisor: u64) {
    assert!(lockdrop.version == VERSION, EVersionMismatch);
    assert!(rates.length() == lockdrop.accepted.length(), EWrongLen);
    assert!(divisor > 0);
    lockdrop.rates = rates;
    lockdrop.rates_divisor = divisor;
}

//
// Helper functions
//

public(package) fun get_cointype<DepositCoin>(lockdrop: &Lockdrop): (u64, TypeName) {
    let typename = with_defining_ids<DepositCoin>();
    let (ok, idx) = lockdrop.accepted.index_of(&typename);
    assert!(ok, EWrongCoin);
    (idx, typename)
}

fun zeros_vector(len: u64): vector<u64> {
    vector::tabulate!(len, |_| 0)
}

#[test_only]
public fun create_admin_cap(ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx) }
}

#[test_only]
public fun get_start_time(lockdrop: &Lockdrop): u64 { lockdrop.start_time }

#[test_only]
public fun get_end_time(lockdrop: &Lockdrop): u64 { lockdrop.end_time }

#[test_only]
public fun is_paused(lockdrop: &Lockdrop): bool { lockdrop.status == StatusPaused }

#[test_only]
public fun get_accepted(lockdrop: &Lockdrop): vector<TypeName> { lockdrop.accepted }

#[test_only]
public fun get_nbtc_type(lockdrop: &Lockdrop): Option<TypeName> { lockdrop.nbtc_type }

#[test_only]
public fun get_rates(lockdrop: &Lockdrop): vector<u64> { lockdrop.rates }

#[test_only]
public fun get_rates_divisor(lockdrop: &Lockdrop): u64 { lockdrop.rates_divisor }
