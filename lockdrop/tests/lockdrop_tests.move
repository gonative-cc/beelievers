module beelievers_lockdrop::lockdrop_tests;

use beelievers_lockdrop::lockdrop::{Self, Lockdrop, AdminCap};
use std::type_name::{Self, with_defining_ids};
use sui::clock::{Self, Clock};
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};

public struct TestCoin has drop {}
public struct NBTC has drop {}

// === Test Helpers ===

#[allow(lint(self_transfer))]
#[test_only]
fun setup(start: u64, end: u64): (Scenario, AdminCap, Clock) {
    let mut scenario = test_scenario::begin(@0x1);
    let admin_cap = lockdrop::create_admin_cap(scenario.ctx());
    lockdrop::new<SUI>(&admin_cap, start, end, scenario.ctx());
    // let accepted = vector[with_defining_ids<SUI>()];

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
fun test_set_time() {
    let (scenario, admin, clock) = setup(1000, 2000);
    let mut lockdrop = take_lockdrop(&scenario);

    lockdrop.set_time(&admin, 2000, 3000);

    assert!(lockdrop.get_start_time() == 2000);
    assert!(lockdrop.get_end_time() == 3000);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
fun test_set_pause() {
    let (scenario, admin, clock) = setup(1000, 2000);
    let mut lockdrop = take_lockdrop(&scenario);
    assert!(!lockdrop.is_paused());

    lockdrop.set_status(&admin, 1);
    assert!(lockdrop.is_paused());

    lockdrop.set_status(&admin, 2);
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

    let withdrawn = lockdrop.withdraw_deposit_to_swap<SUI>(&admin, &clock, scenario.ctx());
    assert!(withdrawn.value() == 1000);
    coin::burn_for_testing(withdrawn);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
fun test_deposit_nbtc() {
    let (mut scenario, admin, clock) = setup(1000, 2000);

    let nbtc_coin = coin::mint_for_testing<SUI>(2000, scenario.ctx());
    let mut lockdrop = take_lockdrop(&scenario);

    lockdrop.deposit_nbtc<SUI>(&admin, nbtc_coin);

    assert!(lockdrop.get_nbtc_type().is_some());
    assert!(*lockdrop.get_nbtc_type().borrow() == type_name::with_defining_ids<SUI>());

    cleanup(scenario, lockdrop, admin, clock);
}

fun setup_claim(): (Scenario, AdminCap, Clock, Lockdrop) {
    let (mut scenario, admin, mut clock) = setup(1000, 2000);
    let mut lockdrop = take_lockdrop(&scenario);
    lockdrop.add_accepted_coin<TestCoin>(&admin, &clock);
    {
        let (idx, typename) = lockdrop.get_cointype<SUI>();
        assert!(idx == 0);
        assert!(typename == with_defining_ids<SUI>());

        let (idx, typename) = lockdrop.get_cointype<TestCoin>();
        assert!(idx == 1);
        assert!(typename == with_defining_ids<TestCoin>());
    };

    // First Deposit
    scenario.next_tx(@0x2);
    clock.set_for_testing(1500);
    {
        let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        lockdrop.deposit(&clock, coin, scenario.ctx());
    };

    (scenario, admin, clock, lockdrop)
}

fun setup_claim_failing(): (Scenario, AdminCap, Clock, Lockdrop) {
    let (mut scenario, admin, mut clock, mut lockdrop) = setup_claim();

    scenario.next_tx(@0x1);
    clock.set_for_testing(2100);

    let nbtc_coin = coin::mint_for_testing<NBTC>(140, scenario.ctx());
    lockdrop.deposit_nbtc<NBTC>(&admin, nbtc_coin);

    let rates = vector[2, 60];
    lockdrop.set_rates(&admin, rates, 100);

    scenario.next_tx(@0x2);
    clock.set_for_testing(2200);
    let claimed = lockdrop.claim<NBTC>(scenario.ctx());
    coin::burn_for_testing(claimed);

    (scenario, admin, clock, lockdrop)
}

#[test]
fun test_simple_claim() {
    let (scenario, admin, clock, lockdrop) = setup_claim_failing();
    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
fun test_double_claim() {
    let (mut scenario, admin, mut clock, mut lockdrop) = setup_claim_failing();

    // second claim should fail
    scenario.next_tx(@0x2);
    clock.set_for_testing(2300);
    let claimed = lockdrop.claim<NBTC>(scenario.ctx());
    coin::burn_for_testing(claimed);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
fun test_claim_no_deposit() {
    let (mut scenario, admin, mut clock, mut lockdrop) = setup_claim_failing();

    // second claim should fail
    scenario.next_tx(@0x200);
    clock.set_for_testing(2300);
    let claimed = lockdrop.claim<NBTC>(scenario.ctx());
    coin::burn_for_testing(claimed);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[expected_failure(abort_code = lockdrop::EWrongCoin)]
fun test_claim_wrong_token() {
    let (mut scenario, admin, mut clock, mut lockdrop) = setup_claim_failing();

    // second claim should fail
    scenario.next_tx(@0x200);
    clock.set_for_testing(2300);
    let claimed = lockdrop.claim<SUI>(scenario.ctx());
    coin::burn_for_testing(claimed);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
#[expected_failure(abort_code = lockdrop::EWrongCoin)]
fun test_claim_wrong_token2() {
    let (mut scenario, admin, mut clock, mut lockdrop) = setup_claim_failing();

    // second claim should fail
    scenario.next_tx(@0x200);
    clock.set_for_testing(2300);
    let claimed = lockdrop.claim<TestCoin>(scenario.ctx());
    coin::burn_for_testing(claimed);

    cleanup(scenario, lockdrop, admin, clock);
}

#[test]
fun test_claim() {
    let (mut scenario, admin, mut clock, mut lockdrop) = setup_claim();

    scenario.next_tx(@0x3);
    clock.set_for_testing(1600);
    {
        let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        lockdrop.deposit(&clock, coin, scenario.ctx());

        let coin = coin::mint_for_testing<TestCoin>(100, scenario.ctx());
        lockdrop.deposit(&clock, coin, scenario.ctx());
    };

    scenario.next_tx(@0x4);
    clock.set_for_testing(1700);
    {
        let coin = coin::mint_for_testing<SUI>(2000, scenario.ctx());
        lockdrop.deposit(&clock, coin, scenario.ctx());
    };

    // 4k sui total, 100 TestCoin.
    // Let's say 100 testcoin == 3k SUI, so we have 7k worth of SUI and 1k is 20 nBTC
    // in total we deposit 20 * 7 = 140 nBTC

    scenario.next_tx(@0x10);
    clock.set_for_testing(2100);
    let nbtc_coin = coin::mint_for_testing<NBTC>(140, scenario.ctx());
    lockdrop.deposit_nbtc<NBTC>(&admin, nbtc_coin);

    check_balance(&lockdrop, @0x1, vector[]);
    check_balance(&lockdrop, @0x2, vector[1000, 0]);
    check_balance(&lockdrop, @0x3, vector[1000, 100]);
    check_balance(&lockdrop, @0x4, vector[2000, 0]);

    // Set rates
    let rates = vector[2, 60];
    lockdrop.set_rates(&admin, rates, 100);

    // Claim
    scenario.next_tx(@0x2);
    let claimed = lockdrop.claim<NBTC>(scenario.ctx());
    assert!(claimed.value() == 20);
    coin::burn_for_testing(claimed);
    check_deposit_removed(&lockdrop, @0x2);

    scenario.next_tx(@0x3);
    clock.set_for_testing(2200);
    let claimed = lockdrop.claim<NBTC>(scenario.ctx());
    assert!(claimed.value() == 80);
    coin::burn_for_testing(claimed);
    check_deposit_removed(&lockdrop, @0x3);

    scenario.next_tx(@0x4);
    let claimed = lockdrop.claim<NBTC>(scenario.ctx());
    assert!(claimed.value() == 40);
    coin::burn_for_testing(claimed);
    check_deposit_removed(&lockdrop, @0x4);

    cleanup(scenario, lockdrop, admin, clock);
}

fun check_balance(lockdrop: &Lockdrop, user: address, expected: vector<u64>) {
    let deposits = lockdrop.get_user_deposits(user);
    assert!(deposits.length() == expected.length());
    let len = deposits.length();
    let mut i = 0;
    while (i < len) {
        assert!(deposits[i] == expected[i]);
        i = i +1;
    };
}

fun check_deposit_removed(lockdrop: &Lockdrop, user: address) {
    let deposits = lockdrop.get_user_deposits(user);
    assert!(deposits.length() == 0);
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
