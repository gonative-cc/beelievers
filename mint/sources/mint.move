//@author - native and deadlabs
#[allow(lint(public_random))]
module beelievers_mint::mint;

use beelivers_auction::auction::{Self, Auction};
use std::ascii;
use std::string::{Self, String};
use sui::clock::{Self, Clock};
use sui::display;
use sui::event;
use sui::kiosk;
use sui::package;
use sui::random::Random;
use sui::table::{Self, Table};
use sui::transfer_policy;
use sui::vec_map::{Self, VecMap};

const TOTAL_SUPPLY: u16 = 6021;
const MYTHIC_SUPPLY: u16 = 21;
const NORMAL_SUPPLY: u16 = 6000;
const NATIVE_MYTHICS: u16 = 11;
const NATIVE_NORMALS: u16 = 200;

const EInsufficientSupply: u64 = 1;
const EMintingNotActive: u64 = 2;
const EUnauthorized: u64 = 3;
const EAlreadyMinted: u64 = 4;
const ESetupNotFinished: u64 = 5;
const EInvalidQuantity: u64 = 6;
const EInvalidTokenId: u64 = 7;
const EPremintNotCompleted: u64 = 8;
const EPremintAlreadyCompleted: u64 = 9;
const EWrongAuctionContract: u64 = 10;
const EPostMintNotActive: u64 = 11;

public struct NFTMinted has copy, drop {
    nft_id: object::ID,
    token_id: u16,
    minter: address,
}

public struct MintingStarted has copy, drop {
    timestamp: u64,
}

public struct MINT has drop {}

public struct AdminCap has key, store {
    id: UID,
}

public struct NftMetadata has store {
    image_id: ascii::String,
    attrs: VecMap<String, String>,
}

public(package) fun empty_metadata(): NftMetadata {
    NftMetadata { attrs: vec_map::empty<String, String>(), image_id: b"".to_ascii_string() }
}

public struct AttrBadge has store {
    name: String,
    id: u16, // badge ID
}

public struct BeelieversCollection has key {
    id: UID,
    /// Unix time in ms, when admin can claim not minted tokens back to the treasury.
    postmint_start: u64,
    remaining_mythic: u16,
    // vector values make a list nfts that are remaining to mint.
    // each time we mint an NFT, we probe it from a specific index:
    //   token_id = remaining_nfts[probe],
    // and then swap that element in the vector with the last element and remove the last
    // element to effectively remove that nft id from available nfts.
    remaining_nfts: vector<u16>,
    /// List of addresses eligible to mint a mythic NFT. Prunned on mint.
    mythic_eligible_list: Table<address, bool>,
    minted_addresses: Table<address, bool>,
    // amount of remaining addresses eligible to mint a mythic nft
    remaining_mythic_eligible: u16,
    premint_completed: bool,
    minting_active: bool,
    mint_start_time: u64,
    auction_contract: address,
    // REVIEW: this is not used
    treasury_address: address,
    /// mapping by token_id. Prunned on mint.
    nft_metadata: Table<u16, NftMetadata>,
    /// badges setup during the initial mint, by the minter address. Prunned on mint.
    preset_badges: Table<address, vector<u16>>,
    /// map of the token_id -> final set of badges. This is when we want to update
    /// NFT in the future and attach new badges
    future_badges: Table<u16, vector<u16>>,
    // REVIEW: since this is a small list (only 21 entries), it should be vector.
    /// mapping from badge_id (number) to badge name
    badge_names: Table<u16, String>,
    /// Badge IDs that will go be added as attributes during the mint
    /// This is a list of pairs: attribute name, badge ID
    attribute_badges: vector<AttrBadge>,
}

public struct BeelieverNFT has key, store {
    id: UID,
    name: String,
    image_id: ascii::String,
    attributes: VecMap<String, String>,
    token_id: u16,
    badges: vector<String>,
}

#[allow(lint(share_owned))]
fun init(witness: MINT, ctx: &mut TxContext) {
    let publisher = package::claim(witness, ctx);

    let collection = BeelieversCollection {
        id: object::new(ctx),
        postmint_start: 1760054400000, // October 10, 2025 00:00:00 UTC.
        remaining_mythic: MYTHIC_SUPPLY,
        // NOTE: token IDs start from 1.
        remaining_nfts: vector::tabulate!(TOTAL_SUPPLY as u64, |i| (i+1) as u16),
        premint_completed: false,
        minting_active: false,
        mint_start_time: 0,
        mythic_eligible_list: table::new<address, bool>(ctx),
        minted_addresses: table::new<address, bool>(ctx),
        remaining_mythic_eligible: 0,
        auction_contract: @auction_addr,
        treasury_address: @treasury_address,
        nft_metadata: table::new<u16, NftMetadata>(ctx),
        preset_badges: table::new<address, vector<u16>>(ctx),
        future_badges: table::new<u16, vector<u16>>(ctx),
        badge_names: table::new<u16, String>(ctx),
        // NOTE: this is a hardcoded top_21 badge that we will add as an attribute
        attribute_badges: vector[AttrBadge { name: b"badge_rank".to_string(), id: 4 }],
    };

    let _admin_cap = AdminCap { id: object::new(ctx) };

    let mut nft_display = display::new<BeelieverNFT>(&publisher, ctx);
    display::add(&mut nft_display, string::utf8(b"name"), string::utf8(b"{name}"));
    display::add(
        &mut nft_display,
        string::utf8(b"description"),
        string::utf8(
            b"BTCFi Beelievers is more than an NFT- it's a movement to make Bitcoin work in DeFi without bridges, wrappers, or custodians. The Beeliever NFT is your badge of conviction, fueling Native's nBTC and BYield on Sui.",
        ),
    );
    display::add(
        &mut nft_display,
        string::utf8(b"image_url"),
        string::utf8(b"https://walrus.tusky.io/{image_id}"),
    );
    display::add(&mut nft_display, string::utf8(b"attributes"), string::utf8(b"{attributes}"));
    display::add(&mut nft_display, string::utf8(b"badges"), string::utf8(b"{badges}"));
    display::update_version(&mut nft_display);

    let (transfer_policy, transfer_policy_cap) = transfer_policy::new<BeelieverNFT>(
        &publisher,
        ctx,
    );

    transfer::transfer(_admin_cap, tx_context::sender(ctx));
    transfer::public_transfer(publisher, tx_context::sender(ctx));
    transfer::public_transfer(nft_display, tx_context::sender(ctx));
    transfer::public_transfer(transfer_policy_cap, tx_context::sender(ctx));
    transfer::public_share_object(transfer_policy);
    transfer::share_object(collection);
}

fun create_nft(
    collection: &mut BeelieversCollection,
    token_id: u16,
    minter: address,
    ctx: &mut TxContext,
): BeelieverNFT {
    let mut name = string::utf8(b"Beelievers #");
    string::append(&mut name, token_id.to_string());

    let NftMetadata { image_id, mut attrs } = if (collection.nft_metadata.contains(token_id)) {
        collection.nft_metadata.remove(token_id)
    } else {
        empty_metadata()
    };

    let badge_ids = if (collection.preset_badges.contains(minter)) {
        collection.preset_badges.remove(minter)
    } else {
        vector::empty<u16>()
    };

    let mut badges = vector::empty<String>();
    let mut i = 0;
    while (i < badge_ids.length()) {
        let b = *vector::borrow(&badge_ids, i);
        let badge_name = badge_number_to_name(collection, b);
        vector::push_back(&mut badges, badge_name);

        collection.attribute_badges.do_ref!(|ab| {
            if (ab.id == b) attrs.insert(ab.name, badge_name);
        });

        i = i + 1;
    };

    BeelieverNFT {
        id: object::new(ctx),
        name,
        image_id,
        attributes: attrs,
        token_id,
        badges,
    }
}

fun badge_number_to_name(collection: &BeelieversCollection, badge_id: u16): String {
    if (collection.badge_names.contains(badge_id)) {
        *table::borrow(&collection.badge_names, badge_id)
    } else {
        string::utf8(b"unknown_badge")
    }
}

// NOTE: this must be called before minting
public fun add_mythic_eligible(
    _admin_cap: &AdminCap,
    c: &mut BeelieversCollection,
    mythic_eligible: vector<address>,
) {
    mythic_eligible.do!(|e| {
        if (!c.mythic_eligible_list.contains(e)) {
            c.mythic_eligible_list.add(e, true);
            c.remaining_mythic_eligible = c.remaining_mythic_eligible + 1;
        };
    })
}

public fun start_minting(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    start_time: u64,
) {
    assert!(collection.premint_completed, EPremintNotCompleted);
    assert!(collection.mythic_eligible_list.length() > 0, ESetupNotFinished);

    collection.minting_active = true;
    collection.mint_start_time = start_time;

    event::emit(MintingStarted {
        timestamp: collection.mint_start_time,
    });
}

public fun pause_minting(_admin_cap: &AdminCap, collection: &mut BeelieversCollection) {
    collection.minting_active = false;
}

#[allow(lint(public_entry))]
public entry fun set_treasury(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    treasury_address: address,
) {
    collection.treasury_address = treasury_address;
}

public fun set_bulk_preset_badges(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    addresses: vector<address>,
    badges: vector<vector<u16>>,
) {
    assert!(vector::length(&addresses) == vector::length(&badges), EInvalidQuantity);

    let mut index = 0;
    while (index < vector::length(&addresses)) {
        let addr = *vector::borrow(&addresses, index);
        let badge_list = *vector::borrow(&badges, index);

        if (table::contains(&collection.preset_badges, addr)) {
            let mut existing_badges = *table::borrow(&collection.preset_badges, addr);
            existing_badges.append(badge_list);
            *table::borrow_mut(&mut collection.preset_badges, addr) = existing_badges;
        } else {
            table::add(&mut collection.preset_badges, addr, badge_list);
        };

        index = index + 1;
    };
}

public fun set_bulk_badge_names(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    badge_ids: vector<u16>,
    badge_names: vector<String>,
) {
    assert!(vector::length(&badge_ids) == vector::length(&badge_names), EInvalidQuantity);

    let mut index = 0;
    while (index < vector::length(&badge_ids)) {
        let badge_id = *vector::borrow(&badge_ids, index);
        let badge_name = *vector::borrow(&badge_names, index);

        if (table::contains(&collection.badge_names, badge_id)) {
            *table::borrow_mut(&mut collection.badge_names, badge_id) = badge_name;
        } else {
            table::add(&mut collection.badge_names, badge_id, badge_name);
        };

        index = index + 1;
    };
}

/// Admin to set new badges to be upserted by an NFT owner.
public fun set_future_badges(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    nft_id: u16,
    badges: vector<u16>,
) {
    assert!(nft_id > 0 && nft_id <= TOTAL_SUPPLY, EInvalidTokenId);

    if (collection.future_badges.contains(nft_id)) {
        *table::borrow_mut(&mut collection.future_badges, nft_id) = badges;
    } else {
        table::add(&mut collection.future_badges, nft_id, badges);
    };
}

/// Allows NFT owner to upsert new budges
public fun upsert_nft_badges(c: &BeelieversCollection, nft: &mut BeelieverNFT) {
    if (!c.future_badges.contains(nft.token_id)) return;
    c.future_badges[nft.token_id].do!(|b| {
        let name = c.badge_names[b];
        if (!nft.badges.contains(&name)) nft.badges.push_back(name);
    });
}

public fun set_nft_image(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    nft_id: u16,
    image_id: vector<u8>,
) {
    assert!(nft_id > 0 && nft_id <= TOTAL_SUPPLY, EInvalidTokenId);

    if (collection.nft_metadata.contains(nft_id)) {
        let m = table::borrow_mut(&mut collection.nft_metadata, nft_id);
        m.image_id = image_id.to_ascii_string();
    } else {
        let m = NftMetadata {
            attrs: vec_map::empty<String, String>(),
            image_id: image_id.to_ascii_string(),
        };
        table::add(&mut collection.nft_metadata, nft_id, m);
    };
}

public fun set_bulk_nft_images(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    nft_ids: vector<u16>,
    image_ids: vector<vector<u8>>,
) {
    assert!(vector::length(&nft_ids) == vector::length(&image_ids), EInvalidQuantity);

    let mut index = 0;
    while (index < vector::length(&nft_ids)) {
        set_nft_image(
            _admin_cap,
            collection,
            *vector::borrow(&nft_ids, index),
            *vector::borrow(&image_ids, index),
        );
        index = index + 1;
    };
}

/// see set_nft_attributes documentation
public fun set_bulk_nft_attributes(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    nft_ids: vector<u16>,
    keys: vector<vector<String>>,
    values: vector<vector<String>>,
) {
    let total_nfts = vector::length(&nft_ids);
    assert!(
        total_nfts == vector::length(&keys) && total_nfts == vector::length(&values),
        EInvalidQuantity,
    );

    let mut index = 0;
    while (index < total_nfts) {
        set_nft_attributes(
            _admin_cap,
            collection,
            *vector::borrow(&nft_ids, index),
            *vector::borrow(&keys, index),
            *vector::borrow(&values, index),
        );
        index = index + 1;
    };
}

/// sets attributes (metadata) for a given NFT. keys and values are lists that makes the
/// key -> value mapping and has to have the same size.
/// NOTE: It overwrites the previous set of attributes.
public fun set_nft_attributes(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    nft_id: u16,
    keys: vector<String>,
    values: vector<String>,
) {
    assert!(nft_id > 0 && nft_id <= TOTAL_SUPPLY, EInvalidTokenId);
    assert!(vector::length(&keys) == vector::length(&values), EInvalidQuantity);

    let mut attributes_map = vec_map::empty<String, String>();
    let mut index = 0;

    while (index < vector::length(&keys)) {
        vec_map::insert(
            &mut attributes_map,
            *vector::borrow(&keys, index),
            *vector::borrow(&values, index),
        );
        index = index + 1;
    };

    if (collection.nft_metadata.contains(nft_id)) {
        let m = table::borrow_mut(&mut collection.nft_metadata, nft_id);
        m.attrs = attributes_map;
    } else {
        let mut m = empty_metadata();
        m.attrs = attributes_map;
        table::add(&mut collection.nft_metadata, nft_id, m);
    };
}

/// mints an NFT for the ctx sender
fun mint_for_sender(
    collection: &mut BeelieversCollection,
    probe_idx: u64,
    transfer_policy: &transfer_policy::TransferPolicy<BeelieverNFT>,
    kiosk: &mut kiosk::Kiosk,
    kiosk_owner_cap: &kiosk::KioskOwnerCap,
    ctx: &mut TxContext,
) {
    let recipient = tx_context::sender(ctx);
    let token_id = collection.remaining_nfts[probe_idx];
    let nft = collection.create_nft(token_id, recipient, ctx);

    let is_mythic = token_id <= MYTHIC_SUPPLY;
    if (is_mythic) {
        let last_mythic_idx = (collection.remaining_mythic-1) as u64;
        if (probe_idx != last_mythic_idx)
            collection.remaining_nfts.swap(probe_idx, last_mythic_idx);
        collection.remaining_nfts.swap_remove(last_mythic_idx);
        collection.remaining_mythic = collection.remaining_mythic - 1;
    } else {
        collection.remaining_nfts.swap_remove(probe_idx);
    };

    event::emit(NFTMinted {
        nft_id: object::id(&nft),
        token_id,
        // NOTE: technically this is the AdminCap owner
        // REVIEW: do we need it? Event already contains sender info.
        minter: recipient,
    });

    kiosk::lock(kiosk, kiosk_owner_cap, transfer_policy, nft);
}

#[allow(lint(public_entry))]
public entry fun mint(
    collection: &mut BeelieversCollection,
    transfer_policy: &transfer_policy::TransferPolicy<BeelieverNFT>,
    auction: &Auction,
    kiosk: &mut kiosk::Kiosk,
    kiosk_owner_cap: &kiosk::KioskOwnerCap,
    clock: &Clock,
    random: &Random,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    let current_time = clock::timestamp_ms(clock);
    let remaining_nfts = collection.remaining_nfts.length();

    assert!(collection.minting_active, EMintingNotActive);
    assert!(current_time >= collection.mint_start_time, EMintingNotActive);
    assert!(!has_minted(collection, sender), EAlreadyMinted);
    assert!(remaining_nfts >= 1, EInsufficientSupply);
    assert!(object::id(auction).to_address() == collection.auction_contract, EWrongAuctionContract);
    let (is_eligible, can_mythic) = collection.determine_mint_eligibility(sender, auction);
    assert!(is_eligible, EUnauthorized);

    collection.mint_random(transfer_policy, can_mythic, kiosk, kiosk_owner_cap, random, ctx);

    collection.minted_addresses.add(sender, true);
    if (can_mythic) {
        collection.remaining_mythic_eligible = collection.remaining_mythic_eligible - 1;
        collection.mythic_eligible_list.remove(sender);
    };
}

public(package) fun mint_random(
    collection: &mut BeelieversCollection,
    transfer_policy: &transfer_policy::TransferPolicy<BeelieverNFT>,
    can_mythic: bool,
    kiosk: &mut kiosk::Kiosk,
    kiosk_owner_cap: &kiosk::KioskOwnerCap,
    random: &Random,
    ctx: &mut TxContext,
) {
    let remaining_nfts = collection.remaining_nfts.length() as u16;
    let remaining_mythic = collection.remaining_mythic;
    let start = if (can_mythic) 0 else remaining_mythic;
    // we need to make sure that mythics will be all minted to eligible users
    // so if number of eligible users gets to the remining mythics, we assure that
    // they mint mythic. Note: start / end indexes start from 0.
    let end = if (
        can_mythic
        && remaining_mythic >= collection.remaining_mythic_eligible && remaining_mythic >= 1
    ) remaining_mythic-1 else remaining_nfts-1;
    let probe = random.new_generator(ctx).generate_u16_in_range(start, end);
    collection.mint_for_sender(probe as u64, transfer_policy, kiosk, kiosk_owner_cap, ctx);
}

///Premint NFT
public fun premint_to_native(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    tp: &transfer_policy::TransferPolicy<BeelieverNFT>,
    kiosk: &mut kiosk::Kiosk,
    kiosk_cap: &kiosk::KioskOwnerCap,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(!collection.premint_completed, EPremintAlreadyCompleted);
    let mut g = r.new_generator(ctx);

    // mint NATIVE_MYTHICS to the treasury
    let mut i = 1;
    while (i <= NATIVE_MYTHICS) {
        // NOTE: indexes for available tokens start from 0
        //
        let probe = g.generate_u16_in_range(0, collection.remaining_mythic-1);
        collection.mint_for_sender(probe as u64, tp, kiosk, kiosk_cap, ctx);
        i = i+1;
    };

    // mint NATIVE_NORMALS to the treasury
    i = 1;
    let start_normal = collection.remaining_mythic;
    let remaining_nfts = collection.remaining_nfts.length() as u16;
    while (i <= NATIVE_NORMALS) {
        // NOTE: i must start from 1 to make `remaining_nfts-i` correct
        let probe = g.generate_u16_in_range(start_normal, remaining_nfts-i);
        collection.mint_for_sender(probe as u64, tp, kiosk, kiosk_cap, ctx);
        i = i+1;
    };

    collection.premint_completed = true;
}

/// Allows admint to claim not minted NFTs to the admin treasury.
/// `num` is the amount of NFTs admin will try to claim. Claim wil start from the last index
/// in the `remaining_nfts` and keep poping from the end.
public fun postmint_to_native(
    _admin_cap: &AdminCap,
    collection: &mut BeelieversCollection,
    num: u16,
    tp: &transfer_policy::TransferPolicy<BeelieverNFT>,
    kiosk: &mut kiosk::Kiosk,
    kiosk_cap: &kiosk::KioskOwnerCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let current_time = clock::timestamp_ms(clock);
    let remaining_nfts = collection.remaining_nfts.length() as u16;
    assert!(collection.postmint_start <= current_time, EPostMintNotActive);
    assert!(num > 0 && num < remaining_nfts, EInsufficientSupply);

    let mut i = 1;
    while (i <= num) {
        collection.mint_for_sender((remaining_nfts - i) as u64, tp, kiosk, kiosk_cap, ctx);
        i = i+1;
    };
}

/// returns (is_auction_winner, can_mint_mythic)
fun determine_mint_eligibility(
    collection: &BeelieversCollection,
    sender: address,
    auction: &Auction,
): (bool, bool) { if (is_mythic_eligible(collection, sender)) {
        return (true, true)
    }; (auction::is_winner(auction, sender), false) }

/// returns: (total_minted, mythic_minted, normal_minted)
public fun get_collection_stats(c: &BeelieversCollection): (u16, u16, u16) {
    // remaining_nfts[0] is not used!
    let total_minted = TOTAL_SUPPLY - (c.remaining_nfts.length() as u16);
    let mythic_minted = MYTHIC_SUPPLY - c.remaining_mythic;
    (total_minted, mythic_minted, total_minted - mythic_minted)
}

public fun get_supply(): vector<u16> { vector[TOTAL_SUPPLY, MYTHIC_SUPPLY, NORMAL_SUPPLY] }

public fun is_mythic_eligible(collection: &BeelieversCollection, addr: address): bool {
    table::contains(&collection.mythic_eligible_list, addr)
}

public fun has_minted(collection: &BeelieversCollection, addr: address): bool {
    table::contains(&collection.minted_addresses, addr)
}

public fun get_badge_name(collection: &BeelieversCollection, badge_id: u16): String {
    if (collection.badge_names.contains(badge_id)) {
        *table::borrow(&collection.badge_names, badge_id)
    } else {
        string::utf8(b"unknown_badge")
    }
}

public fun is_minting_active(collection: &BeelieversCollection): bool {
    collection.minting_active
}

public fun get_mint_start_time(collection: &BeelieversCollection): u64 {
    collection.mint_start_time
}

//
// Helper functions
//

#[test_only]
public(package) fun witness_for_test(): MINT {
    return MINT {}
}

#[test_only]
public(package) fun init_for_testing(otw: MINT, ctx: &mut TxContext) {
    init(otw, ctx);
}
#[test_only]
public(package) fun nft_id(e: &NFTMinted): ID {
    e.nft_id
}

#[test_only]
public(package) fun token_id(e: &NFTMinted): u16 {
    e.token_id
}

#[test_only]
public(package) fun set_auction(c: &mut BeelieversCollection, addr: address) {
    c.auction_contract = addr;
}

#[test_only]
public(package) fun remove_mythic_eligible(c: &mut BeelieversCollection, addr: address) {
    if (c.mythic_eligible_list.contains(addr)) {
        c.remaining_mythic_eligible = c.remaining_mythic_eligible - 1;
        c.mythic_eligible_list.remove(addr);
    };
}

#[test_only]
public(package) fun set_remaining_nfts(c: &mut BeelieversCollection, nfts: vector<u16>) {
    c.remaining_nfts = nfts;
}

#[test_only]
public(package) fun set_remaining_mythic(c: &mut BeelieversCollection, remaining_mythic: u16) {
    c.remaining_mythic = remaining_mythic;
}

#[test]
public fun test_vecmap() {
    let mut attrs = vec_map::empty<String, String>();
    let key = b"Family".to_string();
    let val = b"test_fam".to_string();
    attrs.insert(key, val);

    assert!(attrs.contains(&key));
    assert!(attrs[&key] == val);
}
