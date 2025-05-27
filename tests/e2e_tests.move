#[test_only]
#[allow(unused_let_mut)]
module governance_voting::e2e_tests;

use governance_voting::governance_voting::{Self, GovernanceVoting};
use governance_voting::snapshot::{Self, ValidatorSnapshot, ValidatorSnapshotCap};
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self as ts, Scenario};
use sui::vec_map::{Self, VecMap};
use sui_system::governance_test_utils;
use sui_system::sui_system::SuiSystemState;

public macro fun test_tx(
    $admin: address,
    $f: |
        &mut GovernanceVoting,
        &mut ValidatorSnapshot,
        &mut SuiSystemState,
        &mut Clock,
        &ValidatorSnapshotCap,
        &mut Scenario,
    |,
) {
    let mut scenario = ts::begin($admin);
    let mut clock = clock::create_for_testing(scenario.ctx());
    governance_test_utils::set_up_sui_system_state(vector[@1, @2, @3, @4, @5]);
    snapshot::init_for_testing(scenario.ctx());
    governance_voting::init_for_testing(scenario.ctx());

    scenario.next_tx($admin);

    let mut system = scenario.take_shared<SuiSystemState>();
    let snapshot_cap = scenario.take_from_sender<ValidatorSnapshotCap>();
    let mut snapshot = scenario.take_shared<ValidatorSnapshot>();
    let mut voting = scenario.take_shared<GovernanceVoting>();

    voting.set_timestamps_for_testing(5, 10, 15);

    let (all_stake, ignored_stake) = default_snapshot();
    snapshot.update_all_stake(&snapshot_cap, all_stake, scenario.ctx());
    snapshot.update_ignored_stake(&snapshot_cap, ignored_stake, scenario.ctx());

    $f(
        &mut voting,
        &mut snapshot,
        &mut system,
        &mut clock,
        &snapshot_cap,
        &mut scenario,
    );

    scenario.next_tx($admin);

    ts::return_shared(voting);
    ts::return_shared(snapshot);
    scenario.return_to_sender(snapshot_cap);
    ts::return_shared(system);
    clock.destroy_for_testing();

    scenario.end();
}

public fun default_snapshot(): (VecMap<address, u64>, VecMap<address, u64>) {
    let mut all_stake = vec_map::empty();
    all_stake.insert(@1, 100);
    all_stake.insert(@2, 100);
    all_stake.insert(@3, 100);
    all_stake.insert(@4, 100);
    all_stake.insert(@5, 100);

    let mut ignored_stake = vec_map::empty();

    (all_stake, ignored_stake)
}
