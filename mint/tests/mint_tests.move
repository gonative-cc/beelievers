#[test_only]
module beelievers_mint::mint_tests;

use beelievers_mint::mint::{NFTMinted, EPremintAlreadyCompleted, BeelieversCollection, AdminCap, BeelieverNFT, mint, EAlreadyMinted, EMintingNotActive, EWrongAuctionContract, EInsufficientSupply};
use beelievers_mint::e2e_tests::{setup_for_testing, call_premint, create_auction_for_testing};
use std::unit_test::assert_eq;
use sui::test_scenario::{return_shared, next_tx, return_to_address, Scenario};
use beelivers_auction::auction::{Auction, create, create_admin_cap};
use sui::transfer_policy::TransferPolicy;
use sui::random::Random;
use sui::event::events_by_type;


const ADMIN: address = @0xffff;
const MINTER: address = @0x1111;
const MINTER_MYTHIC: address = @0x1112;

#[test_only]
fun call_mint(mut scenario: Scenario, minter: address) : (Scenario, vector<NFTMinted>) {
    scenario.next_tx(minter);
    let minted_event = {
	let mut c: BeelieversCollection = scenario.take_shared();
        let (mut kiosk, kiosk_cap) = sui::kiosk::new(scenario.ctx());
        let tp: TransferPolicy<BeelieverNFT> = scenario.take_shared();
        let r: Random = scenario.take_shared();
        let clock = sui::clock::create_for_testing(scenario.ctx());
        let auction: Auction = scenario.take_shared();

	c.mint(&tp, &auction, &mut kiosk, &kiosk_cap, &clock, &r, scenario.ctx());

	return_shared(c);
        return_shared(r);
        return_shared(tp);
        return_shared(auction);
	transfer::public_transfer(kiosk, minter);
	transfer::public_transfer(kiosk_cap, minter);
        sui::test_utils::destroy(clock);
	events_by_type<NFTMinted>()
    };
    (scenario, minted_event)
}

#[test]
fun premint_happy_case() {
    let mut scenario = setup_for_testing(ADMIN);
    let minted_events;
    (scenario, minted_events) = call_premint(scenario, ADMIN);

    scenario.next_tx(ADMIN);
    {
	let c: BeelieversCollection = scenario.take_shared();
        let kiosk: sui::kiosk::Kiosk = scenario.take_shared();
        assert_eq!(kiosk.item_count(), 211);
        let mut mythic_count = 0;
        minted_events.do!(|mint_event| {
	    assert_eq!(kiosk.is_locked(mint_event.nft_id()), true);
	    if (mint_event.token_id() <= 21) {
                mythic_count = mythic_count + 1;
	    }
        });

        assert_eq!(mythic_count, 11);
        return_shared(kiosk);
	return_shared(c);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = EPremintAlreadyCompleted)]
fun double_premint_should_fails() {
    let mut scenario = setup_for_testing(ADMIN);
    (scenario, _ ) = call_premint(scenario, ADMIN);
    let (_scenario, _) = call_premint(scenario, ADMIN);
    abort
}


#[test]
fun mint_happy_case() {
    let mut scenario = setup_for_testing(ADMIN);
    (scenario, _) = call_premint(scenario, ADMIN);
    scenario = create_auction_for_testing(scenario);

    scenario.next_tx(ADMIN);
    {
	let admin_cap: AdminCap = scenario.take_from_address(ADMIN);
	let mut auction: Auction = scenario.take_shared();
	let mut c: BeelieversCollection = scenario.take_shared();

	auction.set_winners(vector[MINTER, MINTER_MYTHIC]);
	c.set_auction(object::id(&auction).to_address());
	c.set_remaining_nfts(vector[1, 100]);
	c.set_remaining_mythic(1);
	admin_cap.add_mythic_eligible(&mut c, vector[MINTER_MYTHIC]);
	admin_cap.start_minting(&mut c, 0);

	return_shared(c);
        return_shared(auction);
	return_to_address(ADMIN, admin_cap);
    };



    {
	let minted_event;
	(scenario, minted_event) = call_mint(scenario, MINTER);
	assert_eq!(minted_event.length(), 1);
	scenario.next_tx(MINTER);
	let kiosk: sui::kiosk::Kiosk = scenario.take_from_sender();
	assert_eq!(kiosk.item_count(), 1);
	assert_eq!(kiosk.has_item(minted_event[0].nft_id()), true);
	assert_eq!(minted_event[0].token_id(), 100);
	scenario.return_to_sender(kiosk);
    };

    {

	let minted_event;
	(scenario, minted_event) = call_mint(scenario, MINTER_MYTHIC);
	assert_eq!(minted_event.length(), 1);

	scenario.next_tx(MINTER_MYTHIC);

	let c: BeelieversCollection = scenario.take_shared();
	let kiosk: sui::kiosk::Kiosk = scenario.take_from_sender();
	assert_eq!(kiosk.item_count(), 1);
	assert_eq!(kiosk.has_item(minted_event[0].nft_id()), true);
	assert_eq!(minted_event[0].token_id(), 1);
	assert_eq!(c.is_mythic_eligible(MINTER_MYTHIC), false);

	scenario.return_to_sender(kiosk);
	return_shared(c);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = EMintingNotActive)]
fun mint_when_contract_not_active_should_failed() {
    let mut scenario = setup_for_testing(ADMIN);
    (scenario, _) = call_premint(scenario, ADMIN);
    scenario = create_auction_for_testing(scenario);
    let (_scenario, _) = call_mint(scenario, MINTER);
    abort
}

#[test, expected_failure(abort_code = EAlreadyMinted)]
fun double_mint_should_failed() {
    let mut scenario = setup_for_testing(ADMIN);
    (scenario, _) = call_premint(scenario, ADMIN);
    scenario = create_auction_for_testing(scenario);

    scenario.next_tx(ADMIN);
    {
	let admin_cap: AdminCap = scenario.take_from_address(ADMIN);
	let mut auction: Auction = scenario.take_shared();
	let mut c: BeelieversCollection = scenario.take_shared();

	auction.set_winners(vector[MINTER, MINTER_MYTHIC]);
	c.set_auction(object::id(&auction).to_address());
	admin_cap.add_mythic_eligible(&mut c, vector[MINTER_MYTHIC]);
	admin_cap.start_minting(&mut c, 0);

	return_shared(c);
        return_shared(auction);
	return_to_address(ADMIN, admin_cap);
    };

    (scenario, _) = call_mint(scenario, MINTER);
    let (_scenario, _) = call_mint(scenario, MINTER);

    abort
}


#[test, expected_failure(abort_code = EWrongAuctionContract)]
fun mint_with_invalid_auction_should_failed() {
    let mut scenario = setup_for_testing(ADMIN);
    (scenario, _) = call_premint(scenario, ADMIN);
    scenario = create_auction_for_testing(scenario);

    scenario.next_tx(ADMIN);
    {
	let admin_cap: AdminCap = scenario.take_from_address(ADMIN);
	let mut auction: Auction = scenario.take_shared();
	let mut c: BeelieversCollection = scenario.take_shared();

	auction.set_winners(vector[MINTER, MINTER_MYTHIC]);
	c.set_auction(object::id(&auction).to_address());
	admin_cap.add_mythic_eligible(&mut c, vector[MINTER_MYTHIC]);
	admin_cap.start_minting(&mut c, 0);

	return_shared(c);
        return_shared(auction);
	return_to_address(ADMIN, admin_cap);
    };

    scenario = create_auction_for_testing(scenario);
    let (_scenario, _) = call_mint(scenario, MINTER);
    abort
}


#[test, expected_failure(abort_code = EInsufficientSupply)]
fun mint_insufficient_supply_should_failed() {
    let mut scenario = setup_for_testing(ADMIN);
    (scenario, _) = call_premint(scenario, ADMIN);
    scenario = create_auction_for_testing(scenario);

    scenario.next_tx(ADMIN);
    {
	let admin_cap: AdminCap = scenario.take_from_address(ADMIN);
	let mut auction: Auction = scenario.take_shared();
	let mut c: BeelieversCollection = scenario.take_shared();

	auction.set_winners(vector[MINTER, MINTER_MYTHIC]);
	c.set_auction(object::id(&auction).to_address());
	c.set_remaining_nfts(vector[]);
	admin_cap.add_mythic_eligible(&mut c, vector[MINTER_MYTHIC]);
	admin_cap.start_minting(&mut c, 0);

	return_shared(c);
        return_shared(auction);
	return_to_address(ADMIN, admin_cap);
    };

    scenario = create_auction_for_testing(scenario);
    let (_scenario, _) = call_mint(scenario, MINTER);
    abort
}
