#[test_only]
module beelievers_mint::e2e_tests;

use beelievers_mint::mint::{
    Self,
    witness_for_test,
    init_for_testing,
    AdminCap,
    BeelieverNFT,
    premint_to_native,
    NFTMinted
};
use beelivers_auction::auction::{Auction, create, create_admin_cap};
use std::unit_test::assert_eq;
use sui::address::from_u256;
use sui::event::events_by_type;
use sui::random::{Self, create_for_testing, Random, shuffle};
use sui::test_scenario::{Self, return_shared, Scenario, next_tx, return_to_address};
use sui::transfer_policy;

const ADMIN: address = @0xffff;

#[test_only]
public fun create_auction_for_testing(mut scenario: Scenario): Scenario {
    scenario.next_tx(ADMIN);
    let admin = create_admin_cap(scenario.ctx());
    let clock = sui::clock::create_for_testing(scenario.ctx());
    create(&admin, 10000_000, 10000_000, 5810, &clock, scenario.ctx());
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(admin);
    scenario
}

#[test_only]
public fun setup_for_testing(admin: address): Scenario {
    let mut scenario = test_scenario::begin(admin);
    let witness = witness_for_test();
    init_for_testing(witness, scenario.ctx());

    scenario.next_tx(@0x0);
    create_for_testing(scenario.ctx());
    scenario
}

#[test_only]
public fun call_premint(mut scenario: Scenario, admin: address): (Scenario, vector<NFTMinted>) {
    scenario.next_tx(admin);
    let minted_events: vector<NFTMinted> = {
        let admin_cap: AdminCap = scenario.take_from_address(admin);
        let mut c: mint::BeelieversCollection = scenario.take_shared();
        let (mut kiosk, kiosk_cap) = sui::kiosk::new(scenario.ctx());
        let tp: transfer_policy::TransferPolicy<BeelieverNFT> = scenario.take_shared();
        let r: Random = scenario.take_shared();

        premint_to_native(&admin_cap, &mut c, &tp, &mut kiosk, &kiosk_cap, &r, scenario.ctx());

        scenario.return_to_sender(admin_cap);
        return_shared(c);
        return_shared(tp);
        return_shared(r);
        sui::transfer::public_share_object(kiosk);
        sui::transfer::public_transfer(kiosk_cap, ADMIN);
        events_by_type<NFTMinted>()
    };
    (scenario, minted_events)
}

#[test]
fun full_e2e_tests() {
    let mut scenario = test_scenario::begin(ADMIN);
    let witness = witness_for_test();
    init_for_testing(witness, scenario.ctx());

    scenario.next_tx(@0x0);
    create_for_testing(scenario.ctx());

    let minted_events;
    (scenario, minted_events) = call_premint(scenario, ADMIN);

    scenario = create_auction_for_testing(scenario);

    let number_token_mint = 5810;
    let mut request = vector::tabulate!(number_token_mint, |i| from_u256(i as u256));

    scenario.next_tx(ADMIN);
    {
        let admin_cap: AdminCap = scenario.take_from_address(ADMIN);
        let mut auction: Auction = scenario.take_shared();
        let mut c: mint::BeelieversCollection = scenario.take_shared();
        let r: Random = scenario.take_shared();

        auction.set_winners(request);
        c.set_auction(object::id(&auction).to_address());
        admin_cap.add_mythic_eligible(&mut c, vector::tabulate!(4000, |i| request[i]));
        admin_cap.start_minting(&mut c, 0);

        let mut g = random::new_generator(&r, scenario.ctx());
        // Mint mythic token
        shuffle(&mut g, &mut request);

        return_shared(r);
        return_shared(c);
        return_shared(auction);
        return_to_address(ADMIN, admin_cap);
    };

    scenario.next_tx(@0x00);
    {
        let mut r: Random = scenario.take_shared();
        r.update_randomness_state_for_testing(0, b"thisisnative", scenario.ctx());
        return_shared(r);
    };

    let mut result = vector[];
    let mut id = 0;
    while (id < number_token_mint) {
        let minter_addr: address = request[id];
        scenario.next_tx(minter_addr);

        let mut c: mint::BeelieversCollection = scenario.take_shared();
        let (mut kiosk, kiosk_cap) = sui::kiosk::new(scenario.ctx());
        let tp: transfer_policy::TransferPolicy<BeelieverNFT> = scenario.take_shared();
        let r: Random = scenario.take_shared();
        let clock = sui::clock::create_for_testing(scenario.ctx());
        let auction: Auction = scenario.take_shared();

        let steps: u64 = if (id == 5800) {
            10
        } else {
            100
        };

        steps.do!(|i| {
            let can_mythic = c.is_mythic_eligible(request[id + i]);
            c.mint_random(&tp, can_mythic, &mut kiosk, &kiosk_cap, &r, scenario.ctx());
            c.remove_mythic_eligible(request[id + i]);
        });

        let events = events_by_type<NFTMinted>();
        assert_eq!(events.length(), steps);
        result.append(events);
        id = id + steps;

        return_shared(c);
        return_shared(r);
        return_shared(tp);
        return_shared(auction);
        sui::test_utils::destroy(clock);
        sui::test_utils::destroy(kiosk);
        sui::test_utils::destroy(kiosk_cap);
    };

    assert_eq!(result.length(), number_token_mint);
    let mc = result.count!(|token_event| { token_event.token_id() <= 21 });
    assert_eq!(mc, 10);

    let mut ids = sui::table::new<u16, bool>(scenario.ctx());
    result.do!(|t| {
        ids.add(t.token_id(), true)
    });

    minted_events.do!(|t| {
        ids.add(t.token_id(), true)
    });

    // verify all token id mint
    6021u64.do!(|i| {
        assert_eq!(ids.contains((i + 1) as u16), true);
    });
    sui::test_utils::destroy(ids);
    scenario.end();
}
