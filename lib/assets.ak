use aiken/builtin.{less_than_bytearray, less_than_equals_bytearray}
use aiken/collection/dict
use aiken/primitive/bytearray
use cardano/address.{Credential, Inline}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{DatumHash, InlineDatum, NoDatum, Output}
use env
use list
use tokens.{Tokens}

pub type Assets =
  Pairs<PolicyId, Tokens>

pub type SumStrategy<i> =
  fn(i, fn(Output) -> Assets, fn() -> Assets) -> Assets

/// A Convenient helper to extract assets from values. Comes at no cost since it is usually inlined by the compiler.
pub fn from_value(self: Value) -> Assets {
  self |> assets.to_dict |> dict.to_pairs
}

/// Split a Value into its lovelace quantity and the remaining (ada-less)
/// assets. The ada entry (empty policy id) is guaranteed present in any
/// ledger Value and sorts first, so it is peeled off the head; the function
/// fails loudly on a Value without one.
pub fn split_lovelace(self: Value, return: fn(Int, Assets) -> result) -> result {
  expect [Pair("", ada), ..rest] = from_value(self)
  expect [Pair(_, lovelace)] = dict.to_pairs(ada)
  return(lovelace, rest)
}

/// Split an dictionnary at the given key. Returning the elements before (in reverse key order), the
/// value at the key, and the elements after (in same key order).
pub fn split_at(
  self: Value,
  at: PolicyId,
  return: fn(Assets, Tokens, Assets) -> result,
) -> result {
  do_split_at(from_value(self), at, [], return)
}

pub fn assets_split_at(
  self: Assets,
  at: PolicyId,
  return: fn(Assets, Tokens, Assets) -> result,
) -> result {
  do_split_at(self, at, [], return)
}

fn do_split_at(
  self: Assets,
  at: PolicyId,
  before: Assets,
  return: fn(Assets, Tokens, Assets) -> result,
) -> result {
  when self is {
    [] -> return(before, dict.empty, [])
    [Pair(k, _) as head, ..tail] ->
      if less_than_bytearray(k, at) {
        // Skip while keys are smaller (strictly) than searched key
        do_split_at(tail, at, [head, ..before], return)
      } else {
        if k == at {
          // Done searching, get the value and return the tail after
          return(before, head.2nd, tail)
        } else {
          // The head and tail are all after the key; no need to continue searching.
          return(before, dict.empty, self)
        }
      }
  }
}

/// Lookup the first asset policy from an output, or fails loudly if the output holds no tokens (beyond Ada).
pub fn peek_first(self: Output) -> PolicyId {
  list.head(list.tail(from_value(self.value))).1st
}

/// A faster version of assets.merge that preserves empty maps. This allows to
/// bypass the null check on value since quantities can only ever increase.
/// Importantly, it is also *necessary* to ensure that policies are retained in
/// the map for later validations even if they result in no outputs (e.g. a burn
/// fully compensate a spend).
///
/// It also focuses on assets and completely ignores Ada.
///
/// The function recurses over a list or input-like objects, and let the
/// caller select whether to add an output or not.
///
/// ## Example
///
/// ```aiken
/// collect(
///   self.inputs,
///   [],
///   fn(input, select, discard) {
///     let output = input.output
///     if output.address.payment_credential == needle {
///       select(output)
///     } else {
///       discard()
///     }
///   },
/// )
/// ```
///
/// /!\ PRE-CONDITION /!\
/// The given zero assets is expected to not contain any Ada. This is enforced
/// when assertions are enabled (`--env with_assertions`).
///
/// This is generally true when the initial zero is an empty list or coming
/// from the mint value.
pub fn collect(elems: List<i>, zero: Assets, strategy: SumStrategy<i>) -> Assets {
  do_collect(elems, strategy, env.assert_no_ada_policy(zero))
}

fn do_collect(elems: List<i>, strategy: SumStrategy<i>, sum: Assets) -> Assets {
  when elems is {
    [] -> sum
    [head, ..tail] ->
      do_collect(
        tail,
        strategy,
        strategy(
          head,
          // Output is selected
          fn(output) {
            output.value
              |> from_value
              // Drop ADA, guaranteed to be present in outputs.
              |> list.tail
              // NOTE: left-optimised union
              // The `union` consumes the left argument into the right argument. So it is
              // generally better to provide the smallest argument as left value. The `sum`
              // will generally grow as large as outputs and in many scenario will no be much
              // larger. However, it is very often smaller initially (often empty). Hence why
              // we force it as first argument here.
              |> union(sum, _)
          },
          // Output is discarded
          fn() { sum },
        ),
      )
  }
}

/// Merge two Assets by summing token quantities.
/// Used to combine validated input prog value with validated mint prog value.
pub fn union(left: Assets, right: Assets) -> Assets {
  when left is {
    [] -> right
    // NOTE: Preserving null assets
    // It is primordial here to not discard assets if even they result in an
    // empty dict. This is because the 'left' assets may have negative quantities
    // coming from burns. If a burn is fully cover by a spend, we must preserve
    // the key in the map to ensure that validations necessary to that policy
    // occur as expected.
    [Pair(k, v), ..rest] -> union(rest, do_insert(right, k, v))
  }
}

fn do_insert(self: Assets, k1: PolicyId, v1: Tokens) -> Assets {
  when self is {
    [] -> [Pair(k1, v1)]
    [Pair(k2, _) as head, ..rest] ->
      if less_than_equals_bytearray(k1, k2) {
        if k1 == k2 {
          [Pair(k1, tokens.union(v1, head.2nd)), ..rest]
        } else {
          [Pair(k1, v1), ..self]
        }
      } else {
        [head, ..do_insert(rest, k1, v1)]
      }
  }
}

pub fn has_policy_nft_strictly(
  value: Value,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> Bool {
  expect Some(policy_assets) = assets.to_dict(value) |> dict.get(policy_id)
  expect [Pair(actual_asset_name, 1)] = dict.to_pairs(policy_assets)
  actual_asset_name == asset_name
}

pub fn collect_output_assets(
  outputs: List<Output>,
  prog_logic_cred: Credential,
  max_inline_datum_bytes: Int,
) -> Assets {
  collect(
    outputs,
    [],
    fn(output, select, discard) {
      if output.address.payment_credential == prog_logic_cred {
        expect Some(Inline(..)) = output.address.stake_credential
        expect is_seizable_output_shape_bounded(output, max_inline_datum_bytes)?
        select(output)
      } else {
        discard()
      }
    },
  )
}

/// A programmable-token (PLB) output must stay seizable by a third party.
///
///   * A datum HASH is forbidden: to spend a datum-hash UTxO the ledger
///     requires the datum preimage in the transaction witness, so a holder
///     could pin an output with a secret preimage and make it unspendable by
///     anyone but themselves — a third-party seizure could never be
///     constructed. Only `NoDatum` or an inline datum is allowed.
///   * A reference script is forbidden: a seizure must reproduce the paired
///     input's reference script byte-for-byte in the continuing output, so a
///     large one would bloat the (unavoidable, per-UTxO-atomic) seizure
///     transaction past `maxTxSize`. Programmable-token UTxOs have no
///     legitimate need to carry a reference script.
///   * An inline datum is BOUNDED by `max_inline_datum_bytes` (issue #106, vector 3):
///     seizure must reproduce it byte-for-byte too, so an unbounded one pushes
///     the seizure past `maxTxSize` — or, short of that, collapses how many
///     UTxOs an issuer can seize per transaction. The bound is a live datum
///     field (`ProgrammableLogicGlobalParams.max_inline_datum_bytes`), not a constant,
///     so it can be retuned as DeFi order/loan state grows without
///     re-deploying the delegates.
///
/// Enforced at every PLB-output creation site (transfer, mint, unfracking
/// destinations) so the property holds inductively for all PLB UTxOs.
pub fn is_seizable_output_shape(output: Output) -> Bool {
  let datum_is_not_hash = when output.datum is {
    DatumHash(_) -> False
    _ -> True
  }
  datum_is_not_hash && output.reference_script == None
}

/// `is_seizable_output_shape` PLUS the inline-datum size bound (issue #106,
/// vector 3): the serialised datum must fit in `max_inline_datum_bytes`, the
/// live `ProgrammableLogicGlobalParams` field.
///
/// Used at the HOLDER-driven creation sites — the transfer gate, and the fresh
/// destination outputs of a third-party or unfracking action. Deliberately NOT
/// used by `issuance_mint`:
///
///   * Minting is gated by the substandard's minting-logic withdraw-0, so the
///     party choosing a mint output's datum is the issuing side, not the
///     holder. An issuer that bloats a datum has only made its own asset
///     awkward to seize — outside the threat model, which is a HOLDER making
///     their own holdings unseizable.
///   * Bloat cannot propagate: any onward holder-driven spend goes through
///     `transfer`, whose outputs ARE bounded here, so a bloated UTxO can never
///     produce another one.
///   * CIP-68 reference tokens are legitimately minted to PLB addresses with
///     rich metadata datums; bounding the mint path would break them.
///   * It keeps the protocol-params UTxO OPTIONAL on the mint path, preserving
///     the "a first mint with zero reference inputs validates" property.
///
/// Where the mint-side rule belongs: the SUBSTANDARD's minting-logic
/// withdraw-0, not `issuance_mint`. That script already gates every mint of
/// its policy, it knows what its own outputs are supposed to look like, and it
/// is the only mint-path code that can tell an issuer-driven mint from a
/// user-driven one. The default it should enforce is NO datum at all: nothing
/// in the core reads a mint datum, and carrying one only makes that UTxO more
/// expensive to seize later. Where a datum IS needed — CIP-68 reference-token
/// metadata being the standing example — the substandard should keep it small
/// and prefer a URI over embedded bytes.
///
/// The consequence is a real narrowing: "every PLB UTxO is within the size
/// bound" is NOT a core guarantee — only "every PLB UTxO a holder created is".
/// A substandard whose minting is permissionless or user-triggered must bound
/// the datum in its own minting logic.
pub fn is_seizable_output_shape_bounded(
  output: Output,
  max_inline_datum_bytes: Int,
) -> Bool {
  let datum_ok = when output.datum is {
    DatumHash(_) -> False
    NoDatum -> True
    InlineDatum(d) ->
      bytearray.length(builtin.serialise_data(d)) <= max_inline_datum_bytes
  }
  datum_ok && output.reference_script == None
}
