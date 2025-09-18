/// Module: beelivers_auction
#[allow(unused_const)]
module beelivers_auction::auction;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event::emit;
use sui::random::Random;
use sui::sui::SUI;
use sui::table::{Self, Table};

// ======== Constants ========

// One hour in milliseconds
const ONE_HOUR: u64 = 60 * 60 *1000;
const MIN_BID: u64 = 1_000_000_000; // 1SUI = MIST_PER_SUI;

// ======== Errors ========
const ENotStarted: u64 = 1;
const EEnded: u64 = 2;
const ENotEnded: u64 = 3;
const ENotFinalized: u64 = 4;
const EAlreadyFinalized: u64 = 5;
const ENoBidFound: u64 = 6;
const EDurationTooShort: u64 = 7;
const EStartTimeNotInFuture: u64 = 8;
const EWinnersNotSorted: u64 = 9;
const EWrongWinnersSize: u64 = 10;
const EEntryBidTooSmall: u64 = 11;
const EBidZeroSui: u64 = 12;
const ENotAdmin: u64 = 13;
const EInsufficientBidForWinner: u64 = 14;
const EPaused: u64 = 15;
const ERaffleTooBig: u64 = 16;
const ERaffleAlreadyDone: u64 = 17;
const ENotPause: u64 = 18;
// ========== Structs ==========

public struct AdminCap has key, store {
    id: UID,
}

public struct Auction has key, store {
    id: UID,
    // TODO: consider removing this and use address.
    admin_cap_id: ID,
    paused: bool,
    /// number of items to bid
    size: u32,
    /// auction start time in ms, inclusive
    start_ms: u64,
    /// auction end time in ms, exclusive
    end_ms: u64,
    /// SUI deposits
    vault: Balance<SUI>,
    /// mapping from a bidder -> total bid
    bidders: Table<address, u64>,
    winners: vector<address>,
    /// The price winning bidders are going to pay
    clearing_price: u64,
    finalized: bool,
    raffle_done: bool,
}

public struct AuctionCreateEvent has copy, drop {
    auction_id: ID,
    admin_cap_id: ID,
}

public struct BidEvent has copy, drop {
    auction_id: ID,
    /// bidder (tx sender) total (aggregated) bid amount
    total_bid_amount: u64,
}

public struct RaffleResultEvent has copy, drop {
    auction_id: ID,
    winners: vector<address>,
}

public struct FinalizedEvent has copy, drop {
    auction_id: ID,
    /// funds from the auction transferred to the admin.
    funds: u64,
    clearing_price: u64,
}

public struct EmergencyEvent has copy, drop {
    total_fund: u64,
    auction_id: ID,
}

/// Create admin capability
public fun create_admin_cap(ctx: &mut TxContext): AdminCap {
    AdminCap {
        id: object::new(ctx),
    }
}

#[allow(lint(share_owned))]
/// creates a new Auction (shared object) and associate it with the provided AdminCap.
public fun create(
    admin_cap: &AdminCap,
    start_ms: u64,
    duration_ms: u64,
    size: u32,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let auction = create_(admin_cap, start_ms, duration_ms, size, clock, ctx);

    emit(AuctionCreateEvent {
        auction_id: object::id(&auction),
        admin_cap_id: object::id(admin_cap),
    });

    transfer::public_share_object(auction)
}

// helper function to be used with tests
public(package) fun create_(
    admin_cap: &AdminCap,
    start_ms: u64,
    duration_ms: u64,
    size: u32,
    clock: &Clock,
    ctx: &mut TxContext,
): Auction {
    // must start at least 1h in the future
    assert!(start_ms >= clock.timestamp_ms() + ONE_HOUR, EStartTimeNotInFuture);
    assert!(duration_ms >= ONE_HOUR, EDurationTooShort);
    Auction {
        id: object::new(ctx),
        admin_cap_id: object::id(admin_cap),
        paused: false,
        size,
        start_ms,
        end_ms: start_ms + duration_ms,
        vault: balance::zero(),
        bidders: table::new(ctx),
        winners: vector::empty(),
        clearing_price: 0,
        finalized: false,
        raffle_done: false,
    }
}

fun assert_is_active(auction: &Auction, clock: &Clock) {
    let now = clock.timestamp_ms();
    assert!(now >= auction.start_ms, ENotStarted);
    assert!(now < auction.end_ms, EEnded);
    assert!(!auction.paused, EPaused);
}

/// Place a bid or increase existing bid.
/// Returns total amount bid by the user.
public fun bid(auction: &mut Auction, payment: Coin<SUI>, clock: &Clock, ctx: &mut TxContext): u64 {
    auction.assert_is_active(clock);
    let bidder = tx_context::sender(ctx);
    let bid_amount = coin::value(&payment);
    assert!(bid_amount > 0, EBidZeroSui);

    auction.vault.join(coin::into_balance(payment));

    let total = if (table::contains(&auction.bidders, bidder)) {
        let a = &mut auction.bidders[bidder];
        *a = *a + bid_amount;
        *a
    } else {
        assert!(bid_amount >= MIN_BID, EEntryBidTooSmall);
        auction.bidders.add(bidder, bid_amount);
        bid_amount
    };

    emit(BidEvent {
        auction_id: auction.id.to_inner(),
        total_bid_amount: total,
    });

    total
}

public fun set_paused(admin_cap: &AdminCap, auction: &mut Auction, pause: bool) {
    assert!(object::id(admin_cap) == auction.admin_cap_id, ENotAdmin);
    auction.paused = pause;
}

// NOTE: we can't finalize in a single transaction. Sui tx can only can have 16kb size parameter
// or 500 addresses.
// https://move-book.com/guides/building-against-limits#single-pure-argument-size
/// Finalizes the auction. Must be chained with finalize_continue* and finalize_end to finish the
/// process.
public fun finalize_start(
    admin_cap: &AdminCap,
    auction: &mut Auction,
    winners: vector<address>,
    clock: &Clock,
) {
    assert!(object::id(admin_cap) == auction.admin_cap_id, ENotAdmin);
    assert!(!auction.finalized, EAlreadyFinalized);
    assert!(auction.end_ms <= clock.timestamp_ms(), ENotEnded);
    assert!(is_sorted(&winners), EWinnersNotSorted);
    auction.winners = winners;
}

public fun finalize_continue(
    admin_cap: &AdminCap,
    auction: &mut Auction,
    winners: vector<address>,
    clock: &Clock,
) {
    assert!(object::id(admin_cap) == auction.admin_cap_id, ENotAdmin);
    assert!(is_sorted(&winners), EWinnersNotSorted);
    assert!(!auction.finalized, EAlreadyFinalized);
    assert!(auction.end_ms <= clock.timestamp_ms(), ENotEnded);
    let len = auction.winners.length();
    assert!(auction.winners[len-1].to_u256() < winners[0].to_u256(), EWinnersNotSorted);
    auction.winners.append(winners);
}

/// * `clearing_price`: the amount of MIST all winners have to pay.
/// * `discounts`: amount in MIST. Due to offchain logic, some winners may have a discount,
///    making them pay less than what they bid. This has to be taken into the account, when the
///    admin takes the rewards.beelivers_auction
#[allow(lint(self_transfer))]
public fun finalize_end(
    admin_cap: &AdminCap,
    auction: &mut Auction,
    clearing_price: u64,
    discounts: u64,
    ctx: &mut TxContext,
) {
    assert!(object::id(admin_cap) == auction.admin_cap_id, ENotAdmin);
    assert!(!auction.finalized, EAlreadyFinalized);

    // update status of auction
    auction.finalized = true;
    auction.clearing_price = clearing_price;

    let len = auction.winners.length();
    assert!(0 < len && len <= auction.size as u64, EWrongWinnersSize);

    let funds = auction.clearing_price * len - discounts;
    transfer::public_transfer(
        coin::from_balance(auction.vault.split(funds), ctx),
        ctx.sender(),
    );

    emit(FinalizedEvent {
        auction_id: auction.id.to_inner(),
        funds,
        clearing_price: auction.clearing_price,
    });
}

/// Allows anyone to top up coins to the auction in cases of inconsistency with withdraws.
/// Top up amount is credited to the auction vault and not to the sender.
#[allow(lint(self_transfer))]
public fun top_up(auction: &mut Auction, payment: Coin<SUI>) {
    auction.vault.join(coin::into_balance(payment));
}

#[allow(lint(public_random))]
/// returns the raffle winners
public fun run_raffle(
    auction: &mut Auction,
    admin_cap: &AdminCap,
    num_winners: u32,
    r: &Random,
    ctx: &mut TxContext,
): vector<address> {
    assert!(object::id(admin_cap) == auction.admin_cap_id, ENotAdmin);
    assert!(auction.finalized, ENotFinalized);
    assert!(!auction.raffle_done, ERaffleAlreadyDone);
    auction.raffle_done = true;

    let max = auction.winners.length() as u32;
    assert!(num_winners <= max / 2, ERaffleTooBig);

    let mut raffle_winners: vector<address> = vector[];
    let mut generator = r.new_generator(ctx);
    let mut n = 1;
    while (n <= num_winners) {
        let rnd = generator.generate_u32_in_range(0, max-1);
        let winner = auction.winners[rnd as u64];
        if (!raffle_winners.contains(&winner)) {
            raffle_winners.push_back(winner);
            n = n + 1;
        }
    };

    emit(RaffleResultEvent {
        auction_id: auction.id.to_inner(),
        winners: raffle_winners,
    });
    raffle_winners
}

public fun reset_status(admin_cap: &AdminCap, auction: &mut Auction) {
    assert!(object::id(admin_cap) == auction.admin_cap_id, ENotAdmin);
    assert!(!auction.finalized, EAlreadyFinalized);

    auction.winners = vector::empty();
}

// NOTE: entry forces to drop all the return objects
#[allow(lint(public_entry))]
/// Allows any user to withdraw their funds after the auction is finalized.
public entry fun withdraw(auction: &mut Auction, ctx: &mut TxContext) {
    assert!(auction.finalized, ENotFinalized);
    assert!(!auction.paused, EPaused);
    let sender = ctx.sender();
    assert!(auction.bidders.contains(sender), ENoBidFound);

    let bid = auction.bidders.remove(sender);
    let is_winner = bisect_address(&auction.winners, sender);

    let refund = if (is_winner) {
        assert!(bid >= auction.clearing_price, EInsufficientBidForWinner);
        bid - auction.clearing_price
    } else {
        bid
    };
    transfer::public_transfer(
        coin::from_balance(auction.vault.split(refund), ctx),
        sender,
    );
}

#[allow(lint(self_transfer))]
public fun emergency_withdraw(admin_cap: &AdminCap, auction: &mut Auction, ctx: &mut TxContext) {
    assert!(auction.paused, ENotPause);
    assert!(object::id(admin_cap) == auction.admin_cap_id, ENotAdmin);
    let total_fund = auction.vault.value();
    let sender = ctx.sender();

    transfer::public_transfer(
        coin::from_balance(auction.vault.split(total_fund), ctx),
        sender,
    );

    emit(EmergencyEvent {
        total_fund,
        auction_id: object::id(auction),
    })
}
// ========== View functions ==========

/// returns auction start timestamp in ms
public fun start_ms(auction: &Auction): u64 {
    auction.start_ms
}

/// returns auction end time in ms, exlusive.
public fun end_ms(auction: &Auction): u64 {
    auction.end_ms
}

public fun size(auction: &Auction): u32 {
    auction.size
}

public fun is_paused(auction: &Auction): bool {
    auction.paused
}

/// Returns true if auction is finalized and bidders can withdraw excees of their funds.
public fun is_finalized(auction: &Auction): bool {
    auction.finalized
}

/// Returns true if a given address is winner. If auction is not finalized, returns false.
public fun is_winner(auction: &Auction, bidder: address): bool {
    bisect_address(&auction.winners, bidder)
}

/// Returns bidder total (aggregated) bid. Returns None if the bidder didn't participate in the
/// auction or withdrew his bid after the auction is finalized.
public fun query_total_bid(auction: &Auction, bidder: address): Option<u64> {
    if (!auction.bidders.contains(bidder)) {
        return option::none()
    };
    option::some(auction.bidders[bidder])
}

/// Returns None if auction is not finalized yet. Otherwise returns the clearing price in Sui.
public fun clearing_price(auction: &Auction): Option<u64> {
    if (auction.finalized) option::some(auction.clearing_price) else option::none()
}

// ==================== helper functions ===================================

/// Returns true if the vector elements are in strict ascending order.
fun is_sorted(v: &vector<address>): bool {
    let len = v.length();
    if (len < 2) { return true };
    let mut i = 1;
    let mut prev = v[0].to_u256();
    while (i < len) {
        let x = v[i].to_u256();
        if (prev >= x) { return false };
        prev = x;
        i = i + 1;
    };
    true
}

/// Binary search to find index of an address in sorted vector
/// Returns (found, index) where index is the position if found, or insertion position if not found
public(package) fun bisect_address(v: &vector<address>, addr: address): bool {
    let len = v.length();
    if (len == 0) return false;

    let addr = addr.to_u256();
    let mut left = 0;
    let mut right = len;
    while (left < right) {
        let mid_idx = left + (right - left) / 2;
        let mid_val = v[mid_idx].to_u256();
        if (addr == mid_val) return true;
        if (addr < mid_val) { right = mid_idx; } else { left = mid_idx + 1; }
    };
    false
}

// ----------------------
// Unit tests
// ----------------------

// #[test_only]
// public fun init_for_test(ctx: &mut TxContext): (Auction, AdminCap) {
// }

#[test]
fun test_is_sorted() {
    // Test sorted vectors
    assert!(is_sorted(&vector[]));
    assert!(is_sorted(&vector[@0x1]));
    assert!(is_sorted(&vector[@0x1, @0x2]));
    assert!(is_sorted(&vector[@0x1, @0x2, @0x3]));
    assert!(is_sorted(&vector[@0x1, @0x3]));
    assert!(is_sorted(&vector[@0x1, @0x2, @0x3, @0x30]));

    // Test unsorted vectors
    assert!(!is_sorted(&vector[@0x1, @0x1]));
    assert!(!is_sorted(&vector[@0x2, @0x1]));
    assert!(!is_sorted(&vector[@0x3, @0x1, @0x2]));
    assert!(!is_sorted(&vector[@0x1, @0x3, @0x2]));
    assert!(!is_sorted(&vector[@0x1, @0x2, @0x30, @0x3]));
    assert!(!is_sorted(&vector[@0x1, @0x2, @0x2, @0x3]));
}

#[test]
fun test_bisect_address() {
    let addresses = vector[@0x1, @0x3, @0x5, @0xFAFAFA];

    // Test existing address
    assert!(bisect_address(&addresses, @0x1));
    assert!(bisect_address(&addresses, @0x3));
    assert!(bisect_address(&addresses, @0x5));
    assert!(bisect_address(&addresses, @0xFAFAFA));

    // Test non-existing address
    assert!(!bisect_address(&addresses, @0x2));
    assert!(!bisect_address(&addresses, @0x4));
    assert!(!bisect_address(&addresses, @0x0));
    assert!(!bisect_address(&addresses, @0xFFAAFF));

    let empty = vector[];
    assert!(!bisect_address(&empty, @0x1));
    let single = vector[@0x3];
    assert!(bisect_address(&single, @0x3));
    assert!(!bisect_address(&single, @0x1));

    let addresses = vector[@0x1, @0x2, @0x3, @0x4, @0x5, @0x6, @0x7, @0x8, @0x9, @0xa];
    // Test all elements are found
    let mut i = 0;
    while (i < addresses.length()) {
        assert!(bisect_address(&addresses, addresses[i]), i);
        i = i + 1;
    };
}

#[test_only]
public fun set_winners(a: &mut Auction, winners: vector<address>) {
    a.finalized = true;
    a.winners = winners;
}
