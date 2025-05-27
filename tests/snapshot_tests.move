#[test_only]
module governance_voting::snapshot_tests;

use governance_voting::snapshot;
use std::unit_test::assert_eq;
use sui::test_utils::destroy;
use sui::vec_map::{Self, VecMap};

#[test]
fun test_snapshot() {
    let mut ctx = tx_context::dummy();
    let mut all_stake: VecMap<address, u64> = vec_map::empty();
    let mut ignored_stake: VecMap<address, u64> = vec_map::empty();

    all_stake.insert(@0, 100);
    all_stake.insert(@1, 200);
    all_stake.insert(@2, 100);

    ignored_stake.insert(@1, 40);
    ignored_stake.insert(@2, 100);

    let (snapshot, cap) = snapshot::new_for_testing(all_stake, ignored_stake, &mut ctx);

    let (_, all_stakes) = snapshot.all_stake().into_keys_values();
    let (_, ignored_stakes) = snapshot.ignored_stake().into_keys_values();
    let (_, finalized_stakes) = snapshot.finalized_stake().into_keys_values();

    assert_eq!(all_stakes.fold!(0, |acc, stake| acc + stake), 400);
    assert_eq!(ignored_stakes.fold!(0, |acc, stake| acc + stake), 140);
    assert_eq!(finalized_stakes.fold!(0, |acc, stake| acc + stake), 260);

    assert_eq!(*snapshot.finalized_stake().get(&@2), 0);
    assert_eq!(*snapshot.finalized_stake().get(&@1), 160);
    assert_eq!(*snapshot.finalized_stake().get(&@0), 100);

    destroy(snapshot);
    destroy(cap);
}
