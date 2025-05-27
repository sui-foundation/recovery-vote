module governance_voting::governance_voting;

use governance_voting::snapshot::ValidatorSnapshot;
use std::string::String;
use sui::clock::Clock;
use sui::event;
use sui::vec_map::{Self, VecMap};
use sui::vec_set::from_keys;
use sui_system::sui_system::SuiSystemState;

/// Tries to vote as a non-active validator!
const ENotActiveValidator: u64 = 1;
/// Tries to vote before (or after) the limits
const EVotingNotOpen: u64 = 2;
/// Tries to vote without using "Yes", "No" or "Abstain"!
const EInvalidVote: u64 = 3;
/// Tries to finalize while `end_timestamp_ms` has not been reached.
const EVotingStillOpen: u64 = 4;
/// Tries to finalize while the vote has already been finalized.
const EVotingAlreadyFinalized: u64 = 5;
/// Tries to execute a voting that has not passed.
const EVotingNotPassed: u64 = 6;
/// Tries to vote twice.
const EVoteAlreadyCast: u64 = 7;
/// Tries to finalize vote without having finalized the snapshot
const ESnapshotNotUpdated: u64 = 8;

/// 1 day in MS, so we can derive other dates.
const DAY_MS: u64 = 24 * 60 * 60 * 1000;

const START_TIMESTAMP_MS: u64 = 1748376000 * 1_000;
const MINIMUM_DURATION_TIMESTAMP_MS: u64 = START_TIMESTAMP_MS + (2 * DAY_MS);
const END_TIMESTAMP_MS: u64 = START_TIMESTAMP_MS + (7 * DAY_MS);
const VOTE_DESCRIPTION: vector<u8> =
    b"The Sui community is being asked to decide on a proposal that enables a special transaction to return assets stolen from the Cetus protocol—currently held in two attacker addresses—back to Cetus, pursuant to the Cetus Recovery Plan.\n\n## What\nIf this vote passes, the next Sui release will include a protocol upgrade that enables a **one-time authentication of two special transactions**. These transactions will be hard-coded with the two attacker addresses, stolen asset objects, and their destination. It will verify the voting results and, if approved, transfer the stolen funds from the attacker addresses to a Cetus multi-sig wallet with Cetus, the Sui Foundation, and OtterSec acting as signers.\n\n## Voting Mechanics\n1. Voting will be open for up to 7 days.\n2. Validators may vote \"Yes,\" \"No,\" or \"Abstain.\" Once submitted, votes cannot be changed.\n3. Votes are weighted by validator stake, excluding the Sui Foundation's stake to maintain neutrality.\n4. Stakers are encouraged to delegate their stake to validators who align with their position.\n5. The proposal is considered approved **if and only if**:\n   - More than 50% of total stake (excluding Abstain) participates by voting \"Yes\" or \"No,\" and\n   - The weighted stake voting \"Yes\" exceeds the weighted stake voting \"No.\"\n6. Voting may end early (after a minimum of 2 days) if the remaining unvoted stake cannot change the outcome.";

/// The `GovernanceVoting` object, which will
public struct GovernanceVoting has key {
    id: UID,
    /// Result of the vote
    result: VotingResult,
    /// Visual description, like what a SIP would contain.
    description: String,
    /// At this timestamp, validators can start voting.
    start_timestamp_ms: u64,
    /// The timestamp at which "early determination" can be made.
    minimum_duration_timestamp_ms: u64,
    /// After reaching this,
    end_timestamp_ms: u64,
    /// A list of votes (validator address -> "Yes" | "No"). Using String for ease of
    /// visualization on explorers (when looking up the object), and simplicity in PTB crafting
    /// (`tx.pure.string("Yes")` || `tx.pure.string("No")`)
    votes: VecMap<address, String>,
}

public enum VotingResult has copy, drop, store {
    Pending,
    Passed,
    NotPassed,
}

/// This event will be emitted once when the voting ends.
public struct VotingFinalized has copy, drop, store {
    passed: bool,
    voting_id: ID,
    votes: VecMap<address, String>,
    /// The stake state when voting was finalized.
    stake_state: VecMap<address, u64>,
    /// The stake that was not used as it was SF delegation
    ignored_stake: VecMap<address, u64>,
}

public struct ValidatorVoted has copy, drop, store {
    validator_address: address,
    vote: String,
}

fun init(ctx: &mut TxContext) {
    transfer::share_object(GovernanceVoting {
        id: object::new(ctx),
        result: VotingResult::Pending,
        start_timestamp_ms: START_TIMESTAMP_MS,
        minimum_duration_timestamp_ms: MINIMUM_DURATION_TIMESTAMP_MS,
        end_timestamp_ms: END_TIMESTAMP_MS,
        description: VOTE_DESCRIPTION.to_string(),
        votes: vec_map::empty(),
    });
}

/// Called from validators to vote `Yes`, 'No', or 'Abstain'.
public fun vote(
    voting: &mut GovernanceVoting,
    system_state: &mut SuiSystemState,
    vote: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let validator_address = ctx.sender();

    assert!(
        system_state.active_validator_addresses().contains(&validator_address),
        ENotActiveValidator,
    );

    assert!(voting.is_open_for_voting(clock), EVotingNotOpen);
    assert!(vote == yes_vote!() || vote == no_vote!() || vote == abstain_vote!(), EInvalidVote);
    assert!(!voting.votes.contains(&validator_address), EVoteAlreadyCast);

    voting.votes.insert(validator_address, vote);

    event::emit(ValidatorVoted {
        validator_address,
        vote,
    });
}

/// We need to make sure that the `timestamp` of finalizing this is far away from epoch boundaries,
/// to give us enough time to "update_snapshots".
public fun finalize(
    voting: &mut GovernanceVoting,
    snapshot: &ValidatorSnapshot,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(snapshot.is_up_to_date(ctx), ESnapshotNotUpdated);
    assert!(voting.result == VotingResult::Pending, EVotingAlreadyFinalized);

    let mut yes_stakes = 0;
    let mut no_stakes = 0;
    let mut abstain_stakes = 0;

    let (addresses, finalized_stakes) = snapshot.finalized_stake().into_keys_values();

    addresses.zip_do!(finalized_stakes, |addr, stake| {
        if (voting.votes.contains(&addr)) {
            let vote = voting.votes.get(&addr);

            if (vote == yes_vote!()) {
                yes_stakes = yes_stakes + stake;
            };

            if (vote == no_vote!()) {
                no_stakes = no_stakes + stake;
            };

            if (vote == abstain_vote!()) {
                abstain_stakes = abstain_stakes + stake;
            };
        };
    });

    let total_stake = finalized_stakes.fold!(0, |acc, stake| acc + stake);

    // Max a u64 can fit (with MIST) is 18B, but our fixed supply is 10B. Upcasting to keep it safe.
    let participation_quorum_reached =
        (((yes_stakes as u128) + (no_stakes as u128)) * 2) > total_stake as u128;

    // Vote has pased if yes > no, and we have at least 50% participation between yes|no.
    let passed = yes_stakes > no_stakes && participation_quorum_reached;

    let participating_stakes = yes_stakes + no_stakes + abstain_stakes;
    let non_participating_stakes = total_stake - participating_stakes;

    let has_majority = yes_stakes > (no_stakes + non_participating_stakes);

    // Vote can end early if we reached the minimum timestamp, we have 50% participation across yes/no &
    // `non_participating_stakes` cannot change the narrative even if they voted NO.
    let can_end_early =
        voting.minimum_timestamp_reached(clock) && has_majority && participation_quorum_reached;

    assert!(voting.is_completed(clock) || can_end_early, EVotingStillOpen);

    voting.result = if (passed) {
        VotingResult::Passed
    } else {
        VotingResult::NotPassed
    };

    // This event acts as the "proof" of snapshot.
    event::emit(VotingFinalized {
        passed,
        voting_id: voting.id.to_inner(),
        votes: voting.votes,
        stake_state: snapshot.all_stake(),
        ignored_stake: snapshot.ignored_stake(),
    });
}

public fun passed(voting: &GovernanceVoting): bool {
    voting.result == VotingResult::Passed
}

public fun votes(voting: &GovernanceVoting): VecMap<address, String> {
    voting.votes
}

public fun is_open_for_voting(voting: &GovernanceVoting, clock: &Clock): bool {
    let current_timestamp_ms = clock.timestamp_ms();

    current_timestamp_ms >= voting.start_timestamp_ms && 
    current_timestamp_ms < voting.end_timestamp_ms && 
    voting.result == VotingResult::Pending
}

public fun minimum_timestamp_reached(voting: &GovernanceVoting, clock: &Clock): bool {
    clock.timestamp_ms() >= voting.minimum_duration_timestamp_ms
}

public fun is_completed(voting: &GovernanceVoting, clock: &Clock): bool {
    clock.timestamp_ms() >= voting.end_timestamp_ms
}

public fun assert_can_be_executed(voting: &GovernanceVoting) {
    assert!(voting.passed(), EVotingNotPassed);
}

public macro fun yes_vote(): String {
    b"Yes".to_string()
}

public macro fun no_vote(): String {
    b"No".to_string()
}

public macro fun abstain_vote(): String {
    b"Abstain".to_string()
}

#[test_only]
public(package) fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public(package) fun set_timestamps_for_testing(
    voting: &mut GovernanceVoting,
    start_timestamp_ms: u64,
    minimum_duration_timestamp_ms: u64,
    end_timestamp_ms: u64,
) {
    voting.start_timestamp_ms = start_timestamp_ms;
    voting.minimum_duration_timestamp_ms = minimum_duration_timestamp_ms;
    voting.end_timestamp_ms = end_timestamp_ms;
}

#[test_only]
public(package) fun new_for_testing(
    start_timestamp_ms: u64,
    minimum_duration_timestamp_ms: u64,
    end_timestamp_ms: u64,
    ctx: &mut TxContext,
): GovernanceVoting {
    GovernanceVoting {
        id: object::new(ctx),
        result: VotingResult::Pending,
        start_timestamp_ms,
        minimum_duration_timestamp_ms,
        end_timestamp_ms,
        description: VOTE_DESCRIPTION.to_string(),
        votes: vec_map::empty(),
    }
}

#[test_only]
public(package) fun share(voting: GovernanceVoting) {
    transfer::share_object(voting);
}
