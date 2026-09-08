//// Native-script multisig semantics in Plutus, for the upgrade authority.
////
//// `MultisigScript` and `satisfied` are copied from SundaeSwap's `aicone`
//// (`lib/sundae/multisig.ak`, Apache-2.0, main @ `753436d6caea`, fetched
//// 2026-09-07), with its `satisfying` test verbatim. Copied rather than
//// depended on: the repository is unpublished (version 0.0.0) and this repo
//// takes no on-chain dependency beyond stdlib and fuzz. The port needed no
//// source change — every stdlib module it uses exists unchanged in v3.
////
//// Left out on purpose: `satisfied_payload`, which verifies ed25519
//// signatures over an arbitrary payload. The authority decides on
//// `extra_signatories`, so it would be dead code carrying two crypto builtins.
////
//// Added here: `well_formed` and `size`. Sundae's `AtLeast` has exactly the
//// defects the reference M-of-N validator had (MINR-054, audit-3 finding 05):
//// duplicate children inflate the count, `required <= 0` is permissionless,
//// `required > length` can never be met. Adopting the tree without a
//// well-formedness rail would move that problem, not solve it — and the rail
//// is only enforceable when the tree lives in a datum someone WRITES, which is
//// why `upgrade_multisig` holds it in a config UTxO and checks it on both the
//// mint and the spend.

use aiken/collection/list
use aiken/collection/pairs
use aiken/fuzz
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/primitive/bytearray
use cardano/address.{Credential}
use cardano/assets.{Lovelace}
use cardano/transaction.{ValidityRange}

pub type MultisigScript {
  Signature { key_hash: ByteArray }
  AllOf { scripts: List<MultisigScript> }
  AnyOf { scripts: List<MultisigScript> }
  AtLeast { required: Int, scripts: List<MultisigScript> }
  Before { time: Int }
  After { time: Int }
  Script { script_hash: ByteArray }
}

pub fn satisfied(
  script: MultisigScript,
  signatories: List<ByteArray>,
  valid_range: ValidityRange,
  withdrawals: Pairs<Credential, Lovelace>,
) -> Bool {
  when script is {
    Signature { key_hash } -> list.has(signatories, key_hash)
    AllOf { scripts } ->
      list.all(
        scripts,
        fn(s) { satisfied(s, signatories, valid_range, withdrawals) },
      )
    AnyOf { scripts } ->
      list.any(
        scripts,
        fn(s) { satisfied(s, signatories, valid_range, withdrawals) },
      )
    AtLeast { required, scripts } ->
      required <= list.count(
        scripts,
        fn(s) { satisfied(s, signatories, valid_range, withdrawals) },
      )
    Before { time } ->
      when valid_range.upper_bound is {
        IntervalBound { bound_type: Finite(hi), is_inclusive: True } ->
          hi <= time
        IntervalBound { bound_type: Finite(hi), is_inclusive: False } ->
          hi < time
        _ -> False
      }
    After { time } ->
      when valid_range.lower_bound is {
        IntervalBound { bound_type: Finite(lo), is_inclusive: True } ->
          time <= lo
        IntervalBound { bound_type: Finite(lo), is_inclusive: False } ->
          time < lo
        _ -> False
      }
    Script { script_hash } ->
      pairs.has_key(withdrawals, address.Script(script_hash))
  }
}

// ---------------------------------------------------------------------------
// Well-formedness — the rail Sundae does not carry
// ---------------------------------------------------------------------------

/// Upper bound on the number of nodes (inner and leaf) a tree may hold. An
/// authority that writes itself a tree too expensive to evaluate has bricked
/// the upgrade path; this cap makes that unrepresentable.
///
/// Chosen on measurement, not on feel. The worst case at a given cap is a
/// flat `AtLeast` over cap-1 signature leaves with every member signing —
/// every leaf scans the whole signatory list, and on the UPDATE path the
/// duplicate check compares every pair of children (`list.unique` is
/// quadratic in structural equality). Measured 2026-09-07, mainnet budget
/// 14 M mem / 10 B cpu (see `update_at_max_size_tree` in the validator tests):
///
///   cap   withdraw (per upgrade)   update (per rotation)
///    16     0.90 M /  262 M         1.91 M /  682 M   (14% of mem budget)
///    20     1.23 M /  358 M         2.65 M /  970 M   (19%)
///    24     1.61 M /  468 M         3.51 M / 1.31 B   (25%)
///    32     2.52 M /  733 M         5.61 M / 2.16 B   (40%)
///
/// 20 leaves room for a 7-signer hot set, a dated cold pair and a governance
/// `Script` leaf (about 18 nodes) while keeping the worst case under a fifth
/// of one transaction's memory. A realistic federation — 2-of-3 hot, dated
/// 2-of-2 cold, one governance leaf — is 11 nodes and costs a fraction of
/// this. The cap is baked into the validator's bytes, so changing it later is
/// an authority handover, not a config update: decide it before deployment.
pub const max_size: Int = 20

/// A tree the authority may be configured with.
///
///   * every `Signature` and `Script` leaf names a 28-byte hash — a shorter
///     one can never match anything, and an authority nobody can satisfy is a
///     permanent brick;
///   * every list node is non-empty and has no duplicate children. Empty is
///     the sharp edge: `AllOf []` is vacuously TRUE, a permissionless
///     authority, and `AnyOf []` is always false. Duplicates only distort
///     `AtLeast`, but one rule for all three nodes is simpler to state, test
///     and read than a rule with an exception;
///   * every `AtLeast` has `1 <= required <= length(scripts)`;
///   * the whole tree fits under `max_size`.
///
/// Time leaves carry no constraint: any `Int` is a valid POSIX time bound.
pub fn well_formed(script: MultisigScript) -> Bool {
  and {
    size(script) <= max_size,
    shape_ok(script),
  }
}

fn shape_ok(script: MultisigScript) -> Bool {
  when script is {
    Signature { key_hash } -> bytearray.length(key_hash) == 28
    Script { script_hash } -> bytearray.length(script_hash) == 28
    Before { .. } -> True
    After { .. } -> True
    AllOf { scripts } -> children_ok(scripts)
    AnyOf { scripts } -> children_ok(scripts)
    AtLeast { required, scripts } -> and {
        required >= 1,
        required <= list.length(scripts),
        children_ok(scripts),
      }
  }
}

fn children_ok(scripts: List<MultisigScript>) -> Bool {
  let n = list.length(scripts)
  and {
    n >= 1,
    list.length(list.unique(scripts)) == n,
    list.all(scripts, shape_ok),
  }
}

/// Number of nodes in the tree, leaves included.
pub fn size(script: MultisigScript) -> Int {
  when script is {
    AllOf { scripts } -> 1 + size_all(scripts)
    AnyOf { scripts } -> 1 + size_all(scripts)
    AtLeast { scripts, .. } -> 1 + size_all(scripts)
    _ -> 1
  }
}

fn size_all(scripts: List<MultisigScript>) -> Int {
  list.foldl(scripts, 0, fn(s, acc) { acc + size(s) })
}

// ---------------------------------------------------------------------------
// Sundae's own test, verbatim
// ---------------------------------------------------------------------------

fn valid_range(lo: Int, hi: Int) -> ValidityRange {
  Interval {
    lower_bound: IntervalBound { bound_type: Finite(lo), is_inclusive: True },
    upper_bound: IntervalBound { bound_type: Finite(hi), is_inclusive: False },
  }
}

test satisfying() {
  let key_hash1 = "key1"
  let key_hash2 = "key2"
  let key_hash3 = "key3"
  let sig1 = Signature { key_hash: key_hash1 }
  trace @"Signature": sig1
  let sig2 = Signature { key_hash: key_hash2 }
  let sig3 = Signature { key_hash: key_hash3 }
  let all_of = AllOf { scripts: [sig1, sig2] }
  trace @"AllOf": all_of
  let any_of = AnyOf { scripts: [sig1, sig2] }
  trace @"AnyOf": any_of
  let at_least = AtLeast { required: 2, scripts: [sig1, sig2, sig3] }
  trace @"AtLeast": at_least
  let before = Before { time: 10 }
  trace @"Before": before
  let after = After { time: 10 }
  trace @"After": after
  let between = AllOf { scripts: [After { time: 10 }, Before { time: 15 }] }
  trace @"Between": between
  let script = Script { script_hash: "some_script" }
  trace @"Script": script
  let vesting = AnyOf {
    scripts: [
      AllOf { scripts: [before, sig1] },
      // clawback
      AllOf { scripts: [after, sig2] },
      // dao clawback
      script,
    ],
  }
  trace @"Vesting": vesting
  let no_w: Pairs<Credential, Lovelace> = []
  let correct_w = [Pair(address.Script("some_script"), 0)]
  let incorrect_w = [Pair(address.Script("other_script"), 0)]
  let both_w = [
    Pair(address.Script("some_script"), 0),
    Pair(address.Script("other_script"), 0),
  ]
  // Helper method because ? binds more tightly than !
  let unsatisfied = fn(
    n: MultisigScript,
    s: List<ByteArray>,
    v: ValidityRange,
    w: Pairs<Credential, Lovelace>,
  ) {
    !satisfied(n, s, v, w)
  }
  list.all(
    [
      satisfied(sig1, [key_hash1], valid_range(0, 1), no_w)?,
      satisfied(sig2, [key_hash1, key_hash2], valid_range(0, 1), no_w)?,
      satisfied(all_of, [key_hash1, key_hash2], valid_range(0, 1), no_w)?,
      satisfied(any_of, [key_hash2], valid_range(0, 1), no_w)?,
      satisfied(at_least, [key_hash2, key_hash3], valid_range(0, 1), no_w)?,
      satisfied(before, [], valid_range(0, 5), no_w)?,
      satisfied(after, [], valid_range(15, 20), no_w)?,
      satisfied(after, [], valid_range(10, 15), no_w)?,
      satisfied(between, [], valid_range(12, 13), no_w)?,
      satisfied(script, [], valid_range(0, 1), correct_w)?,
      satisfied(script, [], valid_range(0, 1), both_w)?,
      satisfied(vesting, [key_hash1], valid_range(0, 5), no_w)?,
      satisfied(vesting, [key_hash2], valid_range(15, 20), no_w)?,
      satisfied(vesting, [key_hash3], valid_range(0, 1), correct_w)?,
      unsatisfied(sig1, [key_hash2], valid_range(0, 1), no_w)?,
      unsatisfied(sig3, [key_hash1, key_hash2], valid_range(0, 1), no_w)?,
      unsatisfied(all_of, [key_hash1, key_hash3], valid_range(0, 1), no_w)?,
      unsatisfied(any_of, [key_hash3], valid_range(0, 1), no_w)?,
      unsatisfied(at_least, [key_hash2], valid_range(0, 1), no_w)?,
      unsatisfied(before, [], valid_range(5, 15), no_w)?,
      unsatisfied(before, [], valid_range(5, 10), no_w)?,
      unsatisfied(before, [], valid_range(10, 10), no_w)?,
      unsatisfied(after, [], valid_range(5, 15), no_w)?,
      unsatisfied(between, [], valid_range(0, 5), no_w)?,
      unsatisfied(between, [], valid_range(0, 13), no_w)?,
      unsatisfied(between, [], valid_range(0, 20), no_w)?,
      unsatisfied(between, [], valid_range(13, 20), no_w)?,
      unsatisfied(between, [], valid_range(13, 15), no_w)?,
      unsatisfied(between, [], valid_range(15, 20), no_w)?,
      unsatisfied(script, [], valid_range(0, 1), incorrect_w)?,
      unsatisfied(vesting, [key_hash2], valid_range(0, 5), no_w)?,
      unsatisfied(vesting, [key_hash1], valid_range(15, 20), no_w)?,
      unsatisfied(vesting, [key_hash3], valid_range(10, 10), no_w)?,
      unsatisfied(vesting, [key_hash3], valid_range(0, 5), no_w)?,
      unsatisfied(vesting, [key_hash3], valid_range(15, 20), no_w)?,
      unsatisfied(vesting, [key_hash3], valid_range(15, 20), incorrect_w)?,
    ],
    fn(n) { n },
  )
}

// Sundae's `satisfied` is total over an unbounded-interval range too — the
// time leaves simply refuse. Their test only covers finite ranges.
test satisfying_time_leaves_refuse_unbounded_range() {
  let no_w: Pairs<Credential, Lovelace> = []
  and {
    !satisfied(Before { time: 10 }, [], interval.everything, no_w),
    !satisfied(After { time: 10 }, [], interval.everything, no_w),
  }
}

// ---------------------------------------------------------------------------
// well_formed — unit
// ---------------------------------------------------------------------------

const k1: ByteArray =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

const k2: ByteArray =
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"

const k3: ByteArray =
  #"c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3"

const s1: MultisigScript = Signature { key_hash: k1 }

const s2: MultisigScript = Signature { key_hash: k2 }

const s3: MultisigScript = Signature { key_hash: k3 }

/// The shape a federation would actually deploy: 2-of-3 hot keys, or after a
/// date, a 2-of-2 cold pair, or a governance script's withdraw-0.
fn federation() -> MultisigScript {
  AnyOf {
    scripts: [
      AtLeast { required: 2, scripts: [s1, s2, s3] },
      AllOf {
        scripts: [
          After { time: 1_900_000_000_000 },
          AllOf { scripts: [s1, s2] },
        ],
      },
      Script { script_hash: k3 },
    ],
  }
}

test well_formed_accepts_federation_shape() {
  well_formed(federation())
}

test well_formed_accepts_every_leaf_kind() {
  and {
    well_formed(s1),
    well_formed(Script { script_hash: k1 }),
    well_formed(Before { time: 0 }),
    well_formed(After { time: -1 }),
  }
}

test well_formed_rejects_short_signature_hash() {
  !well_formed(Signature { key_hash: #"a1a1" })
}

test well_formed_rejects_short_script_hash() {
  !well_formed(Script { script_hash: #"a1a1" })
}

// `AllOf []` is vacuously true — a permissionless authority. The sharpest edge
// in the whole ADT, and the reason list nodes must be non-empty.
test well_formed_rejects_empty_all_of() {
  !well_formed(AllOf { scripts: [] })
}

test well_formed_rejects_empty_any_of() {
  !well_formed(AnyOf { scripts: [] })
}

test well_formed_rejects_empty_at_least() {
  !well_formed(AtLeast { required: 1, scripts: [] })
}

// MINR-054 / finding 05, defect 1: `[A, A, B]` at threshold 2 is met by A alone.
test well_formed_rejects_duplicate_children() {
  !well_formed(AtLeast { required: 2, scripts: [s1, s1, s2] })
}

// Defect 2a: a non-positive threshold authorises with no signatures.
test well_formed_rejects_zero_threshold() {
  !well_formed(AtLeast { required: 0, scripts: [s1, s2] })
}

// Defect 2b: a threshold above the member count can never be met.
test well_formed_rejects_threshold_above_count() {
  !well_formed(AtLeast { required: 3, scripts: [s1, s2] })
}

test well_formed_accepts_threshold_at_count() {
  well_formed(AtLeast { required: 2, scripts: [s1, s2] })
}

// A defect buried three levels down is still found.
test well_formed_rejects_nested_defect() {
  !well_formed(
    AnyOf {
      scripts: [
        s1,
        AllOf { scripts: [s2, AtLeast { required: 0, scripts: [s3] }] },
      ],
    },
  )
}

test size_counts_every_node() {
  and {
    size(s1) == 1,
    size(AllOf { scripts: [s1, s2] }) == 3,
    // AnyOf(1) + AtLeast(1) + 3 sigs + AllOf(1) + After(1) + AllOf(1) + 2 sigs + Script(1)
    size(federation()) == 11,
  }
}

test well_formed_rejects_tree_over_max_size() {
  let leaves = list.map(
    list.range(0, max_size),
    fn(i) { Signature { key_hash: bytearray.push(bytearray.drop(k1, 1), i) } },
  )
  // max_size + 1 distinct leaves under one node: size = max_size + 2.
  !well_formed(AllOf { scripts: leaves })
}

// ---------------------------------------------------------------------------
// Property tests
// ---------------------------------------------------------------------------

fn any_key() -> Fuzzer<ByteArray> {
  fuzz.bytearray_fixed(28)
}

fn signature_leaf() -> Fuzzer<MultisigScript> {
  fuzz.map(any_key(), fn(k) { Signature { key_hash: k } })
}

/// A well-formed, TIME-FREE tree of bounded depth, built the way an authority
/// would be: distinct children (fuzz's `set_between`), `required` inside its
/// bounds, at most 2 children per node so 3 levels stay under `max_size`.
fn well_formed_tree(depth: Int) -> Fuzzer<MultisigScript> {
  if depth <= 0 {
    signature_leaf()
  } else {
    fuzz.either4(
      signature_leaf(),
      fuzz.map(children(depth), fn(cs) { AllOf { scripts: cs } }),
      fuzz.map(children(depth), fn(cs) { AnyOf { scripts: cs } }),
      fuzz.and_then(
        children(depth),
        fn(cs) {
          fuzz.map(
            fuzz.int_between(1, list.length(cs)),
            fn(k) { AtLeast { required: k, scripts: cs } },
          )
        },
      ),
    )
  }
}

fn children(depth: Int) -> Fuzzer<List<MultisigScript>> {
  fuzz.set_between(well_formed_tree(depth - 1), 1, 2)
}

fn any_tree() -> Fuzzer<MultisigScript> {
  well_formed_tree(3)
}

/// Every signature key hash in the tree, in order.
fn leaf_keys(script: MultisigScript) -> List<ByteArray> {
  when script is {
    Signature { key_hash } -> [key_hash]
    AllOf { scripts } -> list.flat_map(scripts, leaf_keys)
    AnyOf { scripts } -> list.flat_map(scripts, leaf_keys)
    AtLeast { scripts, .. } -> list.flat_map(scripts, leaf_keys)
    _ -> []
  }
}

const no_w: Pairs<Credential, Lovelace> = []

// The generator and the rail agree on what a good tree is.
test prop_generated_trees_are_well_formed(t via any_tree()) {
  well_formed(t)
}

// THE property the rail exists for: a well-formed, time-free tree can never be
// satisfied with no evidence at all. This is what "no permissionless
// authority" means, and it is exactly what `AllOf []` and `AtLeast { 0, .. }`
// would violate.
test prop_no_evidence_never_satisfies(t via any_tree()) {
  !satisfied(t, [], valid_range(0, 1), no_w)
}

// The complement: with every key present, a time-free tree is satisfied.
test prop_all_keys_satisfy(t via any_tree()) {
  satisfied(t, leaf_keys(t), valid_range(0, 1), no_w)
}

// Satisfaction is monotone in evidence — the ADT has no negation, so adding a
// signatory can never turn a satisfied tree unsatisfied. Labelled so the run
// shows how often the premise actually held.
fn tree_with_subset() -> Fuzzer<(MultisigScript, List<ByteArray>)> {
  fuzz.and_then(
    any_tree(),
    fn(t) { fuzz.map(fuzz.subset(leaf_keys(t)), fn(p) { (t, p) }) },
  )
}

test prop_more_signatories_never_unsatisfy((t, present) via tree_with_subset()) {
  let before = satisfied(t, present, valid_range(0, 1), no_w)
  fuzz.label(
    if before {
      @"premise held"
    } else {
      @"premise vacuous"
    },
  )
  let after = satisfied(t, leaf_keys(t), valid_range(0, 1), no_w)
  !before || after
}

// `AtLeast` means exactly counting: satisfied iff at least `required` distinct
// members are present.
fn keys_threshold_subset() -> Fuzzer<(List<ByteArray>, Int, List<ByteArray>)> {
  fuzz.and_then(
    fuzz.set_between(any_key(), 1, 8),
    fn(keys) {
      fuzz.map2(
        fuzz.int_between(1, list.length(keys)),
        fuzz.subset(keys),
        fn(required, present) { (keys, required, present) },
      )
    },
  )
}

test prop_at_least_is_counting(
  (keys, required, present) via keys_threshold_subset(),
) {
  let tree = AtLeast {
    required,
    scripts: list.map(keys, fn(k) { Signature { key_hash: k } }),
  }
  satisfied(tree, present, valid_range(0, 1), no_w) == (
    list.length(present) >= required
  )
}

// Duplicating any member of a well-formed `AtLeast` makes it ill-formed —
// whatever the threshold, whatever the size.
fn keys_with_threshold() -> Fuzzer<(List<ByteArray>, Int)> {
  fuzz.and_then(
    fuzz.set_between(any_key(), 1, 8),
    fn(keys) {
      fuzz.map(fuzz.int_between(1, list.length(keys)), fn(r) { (keys, r) })
    },
  )
}

test prop_duplicate_member_rejected((keys, required) via keys_with_threshold()) {
  expect Some(first) = list.head(keys)
  let members = list.map(keys, fn(k) { Signature { key_hash: k } })
  let dup = AtLeast {
    required,
    scripts: [Signature { key_hash: first }, ..members],
  }
  let clean = AtLeast { required, scripts: members }
  and {
    well_formed(clean),
    !well_formed(dup),
  }
}

// A threshold outside `1..n` is rejected on either side, for every n.
test prop_threshold_bounds(keys via fuzz.set_between(any_key(), 1, 8)) {
  let members = list.map(keys, fn(k) { Signature { key_hash: k } })
  let n = list.length(keys)
  and {
    !well_formed(AtLeast { required: 0, scripts: members }),
    !well_formed(AtLeast { required: n + 1, scripts: members }),
    well_formed(AtLeast { required: 1, scripts: members }),
    well_formed(AtLeast { required: n, scripts: members }),
  }
}

// Any tree whose node count exceeds the cap is rejected, however well-shaped.
fn oversized_key_set() -> Fuzzer<List<ByteArray>> {
  fuzz.set_between(any_key(), max_size, max_size + 8)
}

test prop_oversized_rejected(keys via oversized_key_set()) {
  let members = list.map(keys, fn(k) { Signature { key_hash: k } })
  !well_formed(AnyOf { scripts: members })
}
