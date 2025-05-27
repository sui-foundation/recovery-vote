module governance_voting::snapshot;

use sui::vec_map::{Self, VecMap};

public struct ValidatorSnapshot has key {
    id: UID,
    /// Stake per validator
    all_stake: VecMap<address, u64>,
    /// The SF stake per validator that will be deducted from all stake.
    ignored_stake: VecMap<address, u64>,
    /// Last updated epoch for the snapshot
    last_updated_epoch: u64,
}

public struct ValidatorSnapshotCap has key, store {
    id: UID,
}

fun init(ctx: &mut TxContext) {
    transfer::share_object(ValidatorSnapshot {
        id: object::new(ctx),
        all_stake: vec_map::empty(),
        ignored_stake: vec_map::empty(),
        last_updated_epoch: 0,
    });

    transfer::transfer(
        ValidatorSnapshotCap {
            id: object::new(ctx),
        },
        ctx.sender(),
    );
}

/// A standalone setter for the all_stakes, in case `ignored_stake` remains as is
/// on the following epoch.
public fun update_all_stake(
    snapshot: &mut ValidatorSnapshot,
    _: &ValidatorSnapshotCap,
    all_stake: VecMap<address, u64>,
    ctx: &TxContext,
) {
    snapshot.all_stake = all_stake;
    snapshot.last_updated_epoch = ctx.epoch();
}

/// Allows updating the "ignored stake" map
public fun update_ignored_stake(
    snapshot: &mut ValidatorSnapshot,
    _: &ValidatorSnapshotCap,
    ignored_stake: VecMap<address, u64>,
    ctx: &TxContext,
) {
    snapshot.ignored_stake = ignored_stake;
    snapshot.last_updated_epoch = ctx.epoch();
}

/// Finalized stake, after deducting all `ignored_stake` from the `all_stake` map.
public fun finalized_stake(snapshot: &ValidatorSnapshot): VecMap<address, u64> {
    let (addresses, stakes) = snapshot.all_stake.into_keys_values();
    let mut finalized_stake: VecMap<address, u64> = vec_map::empty();

    addresses.zip_do!(stakes, |addr, stake| {
        let mut ignored_stake_idx = snapshot.ignored_stake.get_idx_opt(&addr);

        let ignored_stake = if (ignored_stake_idx.is_some()) {
            let (_, ignored_stake) = snapshot
                .ignored_stake
                .get_entry_by_idx(ignored_stake_idx.extract());

            *ignored_stake
        } else {
            0
        };

        finalized_stake.insert(addr, stake - ignored_stake);
    });

    finalized_stake
}

public fun all_stake(snapshot: &ValidatorSnapshot): VecMap<address, u64> {
    snapshot.all_stake
}

public fun ignored_stake(snapshot: &ValidatorSnapshot): VecMap<address, u64> {
    snapshot.ignored_stake
}

public fun is_up_to_date(snapshot: &ValidatorSnapshot, ctx: &TxContext): bool {
    snapshot.last_updated_epoch == ctx.epoch()
}

#[test_only]
public(package) fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public(package) fun new_for_testing(
    all_stake: VecMap<address, u64>,
    ignored_stake: VecMap<address, u64>,
    ctx: &mut TxContext,
): (ValidatorSnapshot, ValidatorSnapshotCap) {
    (
        ValidatorSnapshot {
            id: object::new(ctx),
            all_stake,
            ignored_stake,
            last_updated_epoch: ctx.epoch(),
        },
        ValidatorSnapshotCap { id: object::new(ctx) },
    )
}
