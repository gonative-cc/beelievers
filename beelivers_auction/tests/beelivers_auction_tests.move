// SPDX-License-Identifier: MPL-2.0

#[test_only]
module beelivers_auction::beelivers_auction_tests;

use beelivers_auction::auction::{
    create,
    create_admin_cap,
    Auction,
    finalize_continue,
    finalize_end,
    finalize_start,
    AdminCap,
    ENoBidFound,
    ENotFinalized,
    EEnded,
    ENotAdmin,
    ENotPause
};
use std::unit_test::assert_eq;
use sui::clock::create_for_testing;
use sui::coin::{mint_for_testing, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self, return_shared, Scenario, next_tx};

// uncomment this line to import the module
// use beelivers_auction::beelivers_auction;

const ONE_SUI: u64 = 1_000_000_000;
const ONE_HOUR: u64 = 60 * 60 * 1000;

fun setup(admin: address): Scenario {
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = create_for_testing(scenario.ctx());
        let admin_cap = create_admin_cap(scenario.ctx());

        create(&admin_cap, 2 * ONE_HOUR, 2 * ONE_HOUR, 5810, &clock, scenario.ctx());

        transfer::public_transfer(admin_cap, admin);
        sui::test_utils::destroy(clock);
    };
    scenario
}

fun bid_with_user(mut scenario: Scenario, bidder: address, amount: u64): Scenario {
    next_tx(&mut scenario, bidder);
    {
        let mut clock = create_for_testing(scenario.ctx());
        clock.set_for_testing(3 * ONE_HOUR);

        let coin = mint_for_testing<SUI>(amount, scenario.ctx());
        let mut auction: Auction = scenario.take_shared();

        auction.bid(coin, &clock, scenario.ctx());
        return_shared(auction);
        sui::test_utils::destroy(clock);
    };
    return scenario
}

fun final(
    mut scenario: Scenario,
    admin: address,
    winners: vector<address>,
    clean_price: u64,
): Scenario {
    scenario.next_tx(admin);
    {
        let mut clock = create_for_testing(scenario.ctx());
        clock.set_for_testing(5 * ONE_HOUR);
        let mut auction: Auction = scenario.take_shared();
        let admin_cap: AdminCap = scenario.take_from_address(admin);

        let first_part = vector::tabulate!(winners.length() - 1, |i| winners[i]);
        let second_part = vector[winners[winners.length() - 1]];
        finalize_start(&admin_cap, &mut auction, first_part, &clock);
        finalize_continue(&admin_cap, &mut auction, second_part, &clock);
        finalize_end(&admin_cap, &mut auction, clean_price, 0, scenario.ctx());

        let mut i = 0;
        while (i < winners.length()) {
            assert_eq!(auction.is_winner(winners[i]), true);
            i = i + 1;
        };

        assert_eq!(auction.clearing_price(), option::some(clean_price));

        return_shared(auction);
        scenario.return_to_sender(admin_cap);
        sui::test_utils::destroy(clock);
    };
    scenario.next_tx(admin);
    {
        let coin: Coin<SUI> = scenario.take_from_address(admin);
        assert_eq!(coin.value(), clean_price * winners.length());
        scenario.return_to_sender(coin);
    };

    scenario
}

fun withdraw(mut scenario: Scenario, bidder: address, expected_coin: u64): Scenario {
    scenario.next_tx(bidder);
    {
        let mut clock = create_for_testing(scenario.ctx());
        clock.set_for_testing(5 * ONE_HOUR);
        let mut auction: Auction = scenario.take_shared();
        auction.withdraw(scenario.ctx());
        return_shared(auction);
        sui::test_utils::destroy(clock);
    };
    scenario.next_tx(bidder);
    {
        let coin: Coin<SUI> = scenario.take_from_address(bidder);
        assert_eq!(coin.balance().value(), expected_coin);
        scenario.return_to_sender(coin);
    };
    return scenario
}

#[test]
fun flow_happy_tests() {
    let admin = @0x01;
    let bidder = vector[@0x100, @0x101, @0x102, @0x103];

    let mut scenario = setup(admin);
    scenario = bid_with_user(scenario, bidder[0], ONE_SUI);
    scenario = bid_with_user(scenario, bidder[1], 2 * ONE_SUI);
    scenario = bid_with_user(scenario, bidder[2], 5 * ONE_SUI);

    // auction 2 times from bidder[3]
    scenario = bid_with_user(scenario, bidder[3], 1 * ONE_SUI);
    scenario = bid_with_user(scenario, bidder[3], 1 * ONE_SUI);

    scenario = final(scenario, admin, vector[bidder[1], bidder[2]], 2 * ONE_SUI);

    scenario = withdraw(scenario, bidder[0], ONE_SUI);
    scenario = withdraw(scenario, bidder[1], 0);
    scenario = withdraw(scenario, bidder[2], 3 * ONE_SUI);
    scenario = withdraw(scenario, bidder[3], 2 * ONE_SUI);

    scenario.next_tx(admin);

    {
        let auction: Auction = scenario.take_shared();

        assert_eq!(auction.is_finalized(), true);
        assert_eq!(auction.is_winner(bidder[0]), false);
        assert_eq!(auction.is_winner(@0x10000), false);
        assert_eq!(auction.query_total_bid(bidder[0]), option::none());
        return_shared(auction);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = ENoBidFound)]
fun withdraw_token_without_premission_tests() {
    let admin = @0x01;
    let bidder = vector[@0x100, @0x101, @0x102];
    let mut scenario = setup(admin);

    scenario = bid_with_user(scenario, bidder[0], ONE_SUI);
    scenario = bid_with_user(scenario, bidder[1], 2 * ONE_SUI);
    scenario = bid_with_user(scenario, bidder[2], 5 * ONE_SUI);

    scenario = final(scenario, admin, vector[bidder[1], bidder[2]], 2 * ONE_SUI);

    let invalid_bidder = @0x103;
    scenario.next_tx(invalid_bidder);

    let _scenario = withdraw(scenario, invalid_bidder, ONE_SUI);

    abort
}

#[allow(unused_assignment)]
#[test, expected_failure(abort_code = ENoBidFound)]
fun withdraw_token_second_time_should_failed_tests() {
    let admin = @0x01;
    let bidder = vector[@0x100, @0x101, @0x102];
    let mut scenario = setup(admin);

    scenario = bid_with_user(scenario, bidder[0], ONE_SUI);
    scenario = bid_with_user(scenario, bidder[1], 2 * ONE_SUI);
    scenario = bid_with_user(scenario, bidder[2], 5 * ONE_SUI);

    scenario = final(scenario, admin, vector[bidder[1], bidder[2]], 2 * ONE_SUI);

    scenario = withdraw(scenario, bidder[0], ONE_SUI);
    scenario = withdraw(scenario, bidder[0], 0);

    abort
}
#[test, expected_failure(abort_code = ENotFinalized)]
fun withdraw_token_when_not_final_tests() {
    let admin = @0x01;
    let bidder = vector[@0x100, @0x101, @0x102];
    let mut scenario = setup(admin);
    scenario = bid_with_user(scenario, bidder[0], ONE_SUI);
    scenario = bid_with_user(scenario, bidder[1], 2 * ONE_SUI);
    scenario = bid_with_user(scenario, bidder[2], 5 * ONE_SUI);

    let _scenario = withdraw(scenario, bidder[0], ONE_SUI);

    abort
}

#[test, expected_failure(abort_code = EEnded)]
fun bid_when_auction_ended_test() {
    let admin = @0x01;
    let bidder = vector[@0x100, @0x101, @0x102];
    let mut scenario = setup(admin);

    next_tx(&mut scenario, bidder[0]);
    {
        let mut clock = create_for_testing(scenario.ctx());
        clock.set_for_testing(10 * ONE_HOUR);

        let coin = mint_for_testing<SUI>(ONE_SUI, scenario.ctx());
        let mut auction: Auction = scenario.take_shared();

        auction.bid(coin, &clock, scenario.ctx());
        return_shared(auction);
        sui::test_utils::destroy(clock);
    };

    abort
}

#[test, expected_failure(abort_code = ENotAdmin)]
fun should_fails_when_not_admin_finalize_test() {
    let admin = @0x01;
    let bidder = vector[@0x100, @0x101, @0x102];
    let mut scenario = setup(admin);

    scenario.next_tx(bidder[0]);
    {
        let mut clock = create_for_testing(scenario.ctx());
        clock.set_for_testing(5 * ONE_HOUR);
        let mut auction: Auction = scenario.take_shared();
        let admin_cap: AdminCap = create_admin_cap(scenario.ctx());
        finalize_end(&admin_cap, &mut auction, 0, 0, scenario.ctx());
    };
    abort
}

#[test]
fun emergency_withdraw_test() {
    let admin = @0x01;
    let bidder = vector[@0x100];
    let mut scenario = setup(admin);
    scenario = bid_with_user(scenario, bidder[0], ONE_SUI);

    scenario.next_tx(admin);
    {
        let mut auction: Auction = scenario.take_shared();
        let admin_cap: AdminCap = scenario.take_from_address(admin);
        admin_cap.set_paused(&mut auction, true);

        admin_cap.emergency_withdraw(&mut auction, scenario.ctx());

        return_shared(auction);
        scenario.return_to_sender(admin_cap);
    };

    scenario.next_tx(admin);
    {
        let coin: Coin<SUI> = scenario.take_from_sender();
        assert_eq!(coin.value(), ONE_SUI);
        scenario.return_to_sender(coin);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = ENotPause)]
fun emergency_withdraw_not_paused_test() {
    let admin = @0x01;
    let bidder = vector[@0x100];
    let mut scenario = setup(admin);
    scenario = bid_with_user(scenario, bidder[0], ONE_SUI);

    scenario.next_tx(admin);
    {
        let mut auction: Auction = scenario.take_shared();
        let admin_cap: AdminCap = scenario.take_from_address(admin);

        admin_cap.emergency_withdraw(&mut auction, scenario.ctx());

        return_shared(auction);
        scenario.return_to_sender(admin_cap);
    };

    scenario.next_tx(admin);
    {
        let coin: Coin<SUI> = scenario.take_from_sender();
        assert_eq!(coin.value(), ONE_SUI);
        scenario.return_to_sender(coin);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = ENotAdmin)]
fun emergency_withdraw_not_admin_test() {
    let admin = @0x01;
    let bidder = vector[@0x100];
    let mut scenario = setup(admin);
    scenario = bid_with_user(scenario, bidder[0], ONE_SUI);

    scenario.next_tx(admin);
    {
        let mut auction: Auction = scenario.take_shared();
        let admin_cap: AdminCap = scenario.take_from_address(admin);
        admin_cap.set_paused(&mut auction, true);
        let another_admin_cap = create_admin_cap(scenario.ctx());
        another_admin_cap.emergency_withdraw(&mut auction, scenario.ctx());

        return_shared(auction);
        scenario.return_to_sender(admin_cap);
    };

    scenario.next_tx(admin);
    {
        let coin: Coin<SUI> = scenario.take_from_sender();
        assert_eq!(coin.value(), ONE_SUI);
        scenario.return_to_sender(coin);
    };
    abort
}
