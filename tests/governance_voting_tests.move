#[test_only]
#[allow(dead_code, unused_let_mut)]
module governance_voting::governance_voting_tests;

use governance_voting::e2e_tests::test_tx;
use governance_voting::governance_voting;
use sui::clock;
use sui::test_utils::destroy;
use sui::vec_map;

#[test]
fun unit_test() {
    let mut ctx = tx_context::dummy();
    let mut clock = clock::create_for_testing(&mut ctx);

    let mut voting_obj = governance_voting::new_for_testing(0, 5, 10, &mut ctx);

    assert!(voting_obj.is_open_for_voting(&clock));

    clock.increment_for_testing(4);

    assert!(voting_obj.is_open_for_voting(&clock));

    clock.increment_for_testing(6);

    assert!(voting_obj.is_completed(&clock));

    destroy(voting_obj);
    destroy(clock);
}

#[test]
fun e2e() {
    test_tx!(@0x0, |voting, snapshot, system, clock, _, scenario| {
        clock.set_for_testing(5);

        scenario.next_tx(@1);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@2);
        voting.vote(system, b"No".to_string(), clock, scenario.ctx());

        scenario.next_tx(@3);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@4);
        voting.vote(system, b"No".to_string(), clock, scenario.ctx());

        scenario.next_tx(@5);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        clock.set_for_testing(15);
        voting.finalize(snapshot, clock, scenario.ctx());

        assert!(voting.passed());
    });
}

#[test, expected_failure(abort_code = governance_voting::EVotingNotOpen)]
fun try_vote_before_voting_started() {
    test_tx!(@0x0, |voting, _snapshot, system, clock, _, scenario| {
        scenario.next_tx(@1);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());
        abort
    });
}

#[test, expected_failure(abort_code = governance_voting::ENotActiveValidator)]
fun try_vote_as_non_active_validator() {
    test_tx!(@0x0, |voting, _snapshot, system, clock, _, scenario| {
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());
        abort
    });
}

#[test, expected_failure(abort_code = governance_voting::EInvalidVote)]
fun try_vote_with_invalid_vote() {
    test_tx!(@0x0, |voting, _snapshot, system, clock, _, scenario| {
        scenario.next_tx(@1);
        clock.set_for_testing(5);
        voting.vote(system, b"Invalid".to_string(), clock, scenario.ctx());
        abort
    });
}

#[test, expected_failure(abort_code = governance_voting::EVotingStillOpen)]
fun try_finalize_before_end_timestamp() {
    test_tx!(@0x0, |voting, snapshot, _system, clock, _, scenario| {
        voting.finalize(snapshot, clock, scenario.ctx());
        abort
    });
}

#[test]
fun vote_not_passed() {
    test_tx!(@0x0, |voting, snapshot, system, clock, snapshot_cap, scenario| {
        // just before the cutoff period.
        clock.set_for_testing(9);

        scenario.next_tx(@1);
        voting.vote(system, b"No".to_string(), clock, scenario.ctx());

        scenario.next_tx(@2);
        voting.vote(system, b"No".to_string(), clock, scenario.ctx());

        scenario.next_tx(@3);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        // set stakes for just three validators in our final snapshot. Vote NO with all 2 out of 3.
        let all_stakes = vec_map::from_keys_values(vector[@1, @2, @3], vector[100, 100, 100]);
        snapshot.update_all_stake(snapshot_cap, all_stakes, scenario.ctx());

        // after the end, we finalize.
        clock.set_for_testing(15);
        voting.finalize(snapshot, clock, scenario.ctx());

        assert!(!voting.passed());
    });
}

#[test]
fun vote_not_passed_due_to_delegation_deduction() {
    test_tx!(@0x0, |voting, snapshot, system, clock, snapshot_cap, scenario| {
        clock.set_for_testing(9);

        scenario.next_tx(@1);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@2);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@3);
        voting.vote(system, b"No".to_string(), clock, scenario.ctx());

        // finalized!
        clock.set_for_testing(15);

        let all_stakes = vec_map::from_keys_values(vector[@1, @2, @3], vector[100, 100, 100]);
        let ignored_stakes = vec_map::from_keys_values(vector[@1, @2], vector[90, 90]);
        snapshot.update_all_stake(snapshot_cap, all_stakes, scenario.ctx());
        snapshot.update_ignored_stake(snapshot_cap, ignored_stakes, scenario.ctx());

        voting.finalize(snapshot, clock, scenario.ctx());

        assert!(!voting.passed());
    });
}

#[test, expected_failure(abort_code = governance_voting::EVotingNotPassed)]
fun vote_not_passed_assert_passed() {
    test_tx!(@0x0, |voting, snapshot, system, clock, _, scenario| {
        clock.set_for_testing(9);

        // in this example, we should fail because even if we have 2 yes, that's 200 out of total 500 stake (which is not > 50%)
        scenario.next_tx(@1);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@2);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        clock.set_for_testing(15);

        voting.finalize(snapshot, clock, scenario.ctx());

        voting.assert_can_be_executed();
    });
}

#[test, expected_failure(abort_code = governance_voting::EVotingNotPassed)]
fun test_removed_validator_not_counted() {
    test_tx!(@0x0, |voting, snapshot, system, clock, snapshot_cap, scenario| {
        clock.set_for_testing(9);

        scenario.next_tx(@1);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@2);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@3);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        clock.set_for_testing(15);

        // we update the snapshot to remove validator @1. That means that our total stake becomes 400, and we have 200 in Yes
        // so the vote does not pass.
        let all_stakes = vec_map::from_keys_values(
            vector[@2, @3, @4, @5],
            vector[100, 100, 100, 100],
        );
        snapshot.update_all_stake(snapshot_cap, all_stakes, scenario.ctx());

        voting.finalize(snapshot, clock, scenario.ctx());

        voting.assert_can_be_executed();
    });
}

#[test]
fun test_half_stake_not_reached_even_if_yes_is_greater_than_no() {
    test_tx!(@0x0, |voting, snapshot, system, clock, snapshot_cap, scenario| {
        clock.set_for_testing(9);

        scenario.next_tx(@1);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@2);
        voting.vote(system, b"No".to_string(), clock, scenario.ctx());

        scenario.next_tx(@3);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        clock.set_for_testing(15);

        // We have 7 validators with 100 stake each, and total votes across "Yes" and "No"
        // is 300/700 which is not > 50%, even if `200 > 100` for "yes/no" checking.
        let all_stake = vec_map::from_keys_values(
            vector[@1, @2, @3, @4, @5, @6, @7],
            vector[100, 100, 100, 100, 100, 100, 100],
        );
        snapshot.update_all_stake(snapshot_cap, all_stake, scenario.ctx());

        voting.finalize(snapshot, clock, scenario.ctx());

        assert!(!voting.passed());
    });
}

#[test, expected_failure(abort_code = governance_voting::EVoteAlreadyCast)]
fun test_vote_twice() {
    test_tx!(@0x0, |voting, _, system, clock, _, scenario| {
        clock.set_for_testing(9);

        scenario.next_tx(@1);
        voting.vote(system, b"Abstain".to_string(), clock, scenario.ctx());

        voting.vote(system, b"Abstain".to_string(), clock, scenario.ctx());
        abort
    });
}

#[test, expected_failure(abort_code = governance_voting::ESnapshotNotUpdated)]
fun test_snapshot_not_updated() {
    test_tx!(@0x0, |voting, snapshot, _, clock, _, scenario| {
        scenario.next_epoch(@0x0);
        voting.finalize(snapshot, clock, scenario.ctx());
        abort
    });
}

#[test]
fun test_can_end_early_if_supermajority_reached() {
    test_tx!(@0x0, |voting, snapshot, system, clock, _, scenario| {
        // 5 is the beginning timestamp.
        clock.set_for_testing(5);

        scenario.next_tx(@1);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@2);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@3);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@4);
        voting.vote(system, b"No".to_string(), clock, scenario.ctx());

        // 10 is our "end early" timestamp.
        clock.set_for_testing(10);

        voting.finalize(snapshot, clock, scenario.ctx());
        assert!(voting.passed());
    });
}

#[test, expected_failure(abort_code = governance_voting::EVotingStillOpen)]
fun test_cannot_end_early_if_supermajority_not_reached() {
    test_tx!(@0x0, |voting, snapshot, system, clock, _, scenario| {
        clock.set_for_testing(5);

        scenario.next_tx(@1);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@2);
        voting.vote(system, b"No".to_string(), clock, scenario.ctx());

        clock.set_for_testing(10);

        voting.finalize(snapshot, clock, scenario.ctx());
        abort
    });
}

#[test, expected_failure(abort_code = governance_voting::EVotingStillOpen)]
fun test_cannot_end_early_if_supermajority_reached_but_not_minimum_period_reached() {
    test_tx!(@0x0, |voting, snapshot, system, clock, _, scenario| {
        // 5 is the beginning timestamp.
        clock.set_for_testing(5);

        scenario.next_tx(@1);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@2);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@3);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());

        scenario.next_tx(@4);
        voting.vote(system, b"No".to_string(), clock, scenario.ctx());

        // we have super-majority (300 > 200), but `early voting timestamp` has not been reached.
        voting.finalize(snapshot, clock, scenario.ctx());

        abort
    });
}

#[test]
fun test_finalize_without_participation_as_failure() {
    test_tx!(@0x0, |voting, snapshot, _, clock, _, scenario| {
        clock.set_for_testing(15);
        voting.finalize(snapshot, clock, scenario.ctx());
        assert!(!voting.passed());
    });
}

#[test, expected_failure(abort_code = governance_voting::EVotingAlreadyFinalized)]
fun test_cannot_finalize_twice() {
    test_tx!(@0x0, |voting, snapshot, _, clock, _, scenario| {
        clock.set_for_testing(15);
        voting.finalize(snapshot, clock, scenario.ctx());

        voting.finalize(snapshot, clock, scenario.ctx());
        abort
    });
}


#[test, expected_failure(abort_code = governance_voting::EVotingNotOpen)]
fun test_cannot_vote_after_end_timestamp() {
    test_tx!(@0x0, |voting, _, system, clock, _, scenario| {
        clock.set_for_testing(15);
        scenario.next_tx(@1);
        voting.vote(system, b"Yes".to_string(), clock, scenario.ctx());
        abort
    });
}
