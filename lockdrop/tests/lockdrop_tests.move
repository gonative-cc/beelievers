module beelievers_lockdrop::lockdrop_tests;

use beelievers_lockdrop::lockdrop::{Self, Lockdrop, AdminCap};
use std::type_name;
use sui::clock::{Self, Clock};
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};

public struct TestCoin has drop {}

// === Test Helpers ===

#[allow(lint(self_transfer))]
#[test_only]
fun setup(start: u64, end: u64): (Scenario, AdminCap, Clock) {
    let mut scenario = test_scenario::begin(@0x1);
    let admin_cap = lockdrop::create_admin_cap(scenario.ctx());
    lockdrop::new(&admin_cap, start, end, scenario.ctx());
    // transfer::public_transfer(admin_cap, scenario.ctx().sender());
    scenario.next_tx(@0x1);
    let clock = clock::create_for_testing(scenario.ctx());
    (scenario, admin_cap, clock)
}

#[test_only]
fun take_lockdrop(scenario: &Scenario): Lockdrop {
    scenario.take_shared<Lockdrop>()
}

fun cleanup(sc: Scenario, lockdrop: Lockdrop, ac: AdminCap, clock: Clock) {
    test_scenario::return_shared(lockdrop);
    transfer::public_transfer(ac, @0x1);
    clock.destroy_for_testing();
    sc.end();
}

#[test]
fun test_new() {
    let (scenario, admin, clock) = setup(1000, 2000);
    let lockdrop = take_lockdrop(&scenario);

    assert!(lockdrop.get_start_time() == 1000);
    assert!(lockdrop.get_end_time() == 2000);
    assert!(!lockdrop.is_paused());
    assert!(lockdrop.get_accepted().length() == 1);
    assert!(lockdrop.get_accepted()[0] == type_name::with_defining_ids<SUI>());
    assert!(lockdrop.get_nbtc_type().is_none());
    assert!(lockdrop.get_rates().is_empty());
    assert!(lockdrop.get_rates_divisor() == 0);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
fun test_multiple_deposits() {
    let (mut scenario, admin, mut clock) = setup(1000, 2000);
    clock.set_for_testing(1500);
    let mut lockdrop = take_lockdrop(&scenario);

    let coin1 = coin::mint_for_testing<SUI>(500, scenario.ctx());
    lockdrop.deposit(&clock, coin1, scenario.ctx());

    let coin2 = coin::mint_for_testing<SUI>(300, scenario.ctx());
    lockdrop.deposit(&clock, coin2, scenario.ctx());

    let deposits = lockdrop.get_user_deposits(@0x1);
    assert!(deposits[0] == 800);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[expected_failure(abort_code = lockdrop::EInvalidTime)]
fun test_deposit_before_start() {
    let (mut scenario, admin, mut clock) = setup(1000, 2000);
    clock.set_for_testing(500);
    let mut lockdrop = take_lockdrop(&scenario);

    let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
    lockdrop.deposit(&clock, coin, scenario.ctx());

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[allow(unused)]
fun test_set_time() {
    let (mut scenario, admin, clock) = setup(1000, 2000);
    let mut lockdrop = take_lockdrop(&scenario);

    admin.set_time(&mut lockdrop, 2000, 3000);

    assert!(lockdrop.get_start_time() == 2000);
    assert!(lockdrop.get_end_time() == 3000);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[allow(unused)]
fun test_set_pause() {
    let (mut scenario, admin, clock) = setup(1000, 2000);
    let mut lockdrop = take_lockdrop(&mut scenario);

    admin.set_pause(&mut lockdrop, true);
    assert!(lockdrop.is_paused());

    lockdrop::set_pause(&admin, &mut lockdrop, false);
    assert!(!lockdrop.is_paused());

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[allow(unused)]
fun test_withdraw_deposit_to_swap() {
    let (mut scenario, admin, mut clock) = setup(1000, 2000);
    clock.set_for_testing(1500);
    let mut lockdrop = take_lockdrop(&mut scenario);

    // Deposit
    let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
    scenario.next_tx(@0x1);
    lockdrop.deposit(&clock, coin, scenario.ctx());

    // After end
    clock.set_for_testing(2500);
    scenario.next_tx(@0x1);

    let withdrawn = admin.withdraw_deposit_to_swap<SUI>(&mut lockdrop, &clock, scenario.ctx());
    assert!(withdrawn.value() == 1000);
    coin::burn_for_testing(withdrawn);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[allow(unused)]
fun test_deposit_nbtc() {
    let (mut scenario, admin, clock) = setup(1000, 2000);

    let nbtc_coin = coin::mint_for_testing<SUI>(2000, scenario.ctx());
    let mut lockdrop = take_lockdrop(&mut scenario);

    admin.deposit_nbtc<SUI>(&mut lockdrop, nbtc_coin);

    assert!(lockdrop.get_nbtc_type().is_some());
    assert!(*lockdrop.get_nbtc_type().borrow() == type_name::with_defining_ids<SUI>());

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[allow(unused)]
fun test_set_rates() {
    let (mut scenario, admin, clock) = setup(1000, 2000);
    let mut lockdrop = take_lockdrop(&mut scenario);

    let rates = vector[2]; // for SUI
    lockdrop::set_rates(&admin, &mut lockdrop, rates, 1);

    assert!(lockdrop.get_rates() == rates);
    assert!(lockdrop.get_rates_divisor() == 1);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[allow(unused)]
fun test_claim() {
    let (mut scenario, admin, mut clock) = setup(1000, 2000);
    clock.set_for_testing(1500);
    let mut lockdrop = take_lockdrop(&mut scenario);

    // Deposit
    let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
    lockdrop.deposit(&clock, coin, scenario.ctx());

    scenario.next_tx(@0x2);
    clock.set_for_testing(1600);
    let coin = coin::mint_for_testing<SUI>(3000, scenario.ctx());
    lockdrop.deposit(&clock, coin, scenario.ctx());

    // Deposit nbtc
    let nbtc_amount: u64 = 2000;
    let nbtc_coin = coin::mint_for_testing<SUI>(nbtc_amount, scenario.ctx());
    scenario.next_tx(@0x10);
    clock.set_for_testing(2100);
    admin.deposit_nbtc<SUI>(&mut lockdrop, nbtc_coin);

    // Set rates
    // 4k sui total, 2k nbtc, so rate is 0.5
    let rates = vector[5];
    admin.set_rates(&mut lockdrop, rates, 10);

    // Claim
    scenario.next_tx(@0x1);
    let claimed = lockdrop.claim<SUI>(scenario.ctx());
    assert!(claimed.value() == nbtc_amount / 4);
    coin::burn_for_testing(claimed);

    scenario.next_tx(@0x2);
    clock.set_for_testing(2200);
    let claimed = lockdrop.claim<SUI>(scenario.ctx());
    assert!(claimed.value() == nbtc_amount * 3 / 4);
    coin::burn_for_testing(claimed);

    // Check deposits removed
    let deposits = lockdrop.get_user_deposits(@0x1);
    assert!(deposits.length() == 0);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
fun test_get_user_deposits_empty() {
    let (scenario, admin, clock) = setup(1000, 2000);
    let lockdrop = take_lockdrop(&scenario);

    let deposits = lockdrop.get_user_deposits(@0x2);
    assert!(deposits.is_empty());
    // std::debug::print(&deposits.length());

    cleanup(scenario, lockdrop, admin, clock);
}
