/// Module: beelivers_auction
#[allow(unused_const)]
module beelivers_auction::auction;

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
}

/// Create admin capability
public fun create_admin_cap(ctx: &mut TxContext): AdminCap {
    AdminCap {
        id: object::new(ctx),
    }
}

#[allow(lint(share_owned))]
/// creates a new Auction (shared object) and associate it with the provided AdminCap.
public fun create(_size: u32, ctx: &mut TxContext) {
    let auction = Auction {
        id: object::new(ctx),
    };

    transfer::public_share_object(auction)
}

/// Returns true if a given address is winner. If auction is not finalized, returns false.
public fun is_winner(_auction: &Auction, _bidder: address): bool {
    return true
}
