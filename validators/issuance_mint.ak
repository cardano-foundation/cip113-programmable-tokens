use aiken/builtin.{unconstr_fields}
use aiken/collection/dict
use aiken/collection/list
use assets as prog_assets
// Programmable Token Issuance Minting Policy
// This policy handles minting and burning of registered programmable tokens
// Migrated from SmartTokens.Contracts.Issuance

use cardano/address.{Credential, Inline}
use cardano/assets.{PolicyId}
use cardano/transaction.{Input, Output, ScriptPurpose, Transaction, Withdraw}
use programmable_logic/params
use registry_node.{RegistryNode}
use types.{
  MintingRegistryProof, OutputIndex, RefInput, RegistryProof, ThirdPartyRedeemer,
  TokenExists, TransferRedeemer,
}
use utils.{expect_inline_datum}

validator issuance_mint(
  // Programmable Token Script Hash
  programmable_logic_base: Credential,
  // Registry Node Currency Symbol - used to verify registry proofs for token minting
  registry_node_cs: PolicyId,
  // <- the hash of the contract of the logic for minting.
  minting_logic_cred: Credential,
  // One-shot protocol-params NFT policy — the protocol's permanent anchor,
  // the same parameter PLB and the three delegate validators take. Read ONLY
  // inside the `RefInput` delegation branch, where it locates the
  // coordination UTxO among `reference_inputs` and reads the LIVE delegate
  // credentials from its datum (`transfer_cred`, field 2; `third_party_cred`,
  // field 3). Delegation then keys on THOSE credentials, so an in-place
  // upgrade of either validator automatically retires the old credential as
  // a mint-custody delegate. Coordination UTxO absent ⇒ no delegation ⇒
  // local `no_escape` custody (fail-safe). The OutputIndex path never reads
  // it.
  params_policy: PolicyId,
) {
  mint(redeemer: MintingRegistryProof, own_policy: PolicyId, self: Transaction) {
    // Single-pass withdrawal scan for ONLY the substandard's minting-logic
    // proof. (Previously this was foldl2 with a second accumulator for
    // "is the transfer validator invoked"; that signal is now rediscovered
    // for free by the redeemer lookup below — a delegate is invoked iff its
    // withdraw script-purpose has an entry in `tx.redeemers`.)
    let minting_logic_invoked = list.any(
      self.withdrawals,
      fn(wdrl) {
        let Pair(cred, _amount) = wdrl
        cred == minting_logic_cred
      },
    )

    // Custody (re-audit R-04): no `own_policy` token may leave the PLB. Both
    // proof modes call it, so bind it once — sharing the 3-arg call compiles
    // ~25 bytes smaller than inlining it twice. (Laziness is the `or`'s job,
    // not the closure's: the RefInput delegate path skips it only because `or`
    // short-circuits.)
    let custody_ok = fn() {
      no_escape(self.outputs, programmable_logic_base, own_policy)
    }

    // The registry proof determines WHO enforces custody:
    //
    //   OutputIndex → the policy's registry node appears as an OUTPUT of this
    //     tx (freshly minted, OR re-emitted by a node update/insert). No
    //     delegate sees this node, so issuance_mint enforces custody itself.
    //
    //   RefInput { index } → the node is a reference input, and a delegate
    //     validator MAY enforce custody instead — but only when ITS redeemer
    //     names the SAME registry node our `index` points at.
    //     `verify_registry_node` has already bound that index to `own_policy`
    //     (NFT asset name and datum.key both == own_policy), so comparing
    //     indices suffices — no need to re-extract a policy id from the
    //     delegate's redeemer. Two delegates can cover us:
    //       * the `transfer` validator → its `TransferRedeemer.proofs`
    //         contains `TokenExists { node_idx: index }`
    //       * the `third_party` validator → its `ThirdPartyRedeemer` has
    //         `registry_node_idx == index`
    //     (`unfracking` never mints, so it can never cover a mint.)
    //     If a delegate covers us → delegate; otherwise enforce custody here.
    //
    // Closes Finding 04 / re-audit R-04: the previous broad "coordinator
    // invoked" signal let mints of non-covered policies escape; this precise
    // check trusts a delegate only for the specific node our own redeemer
    // named, and `no_escape` (below) catches any token this validator does
    // mint.
    let valid_minting = when redeemer is {
      OutputIndex { index } -> {
        // The policy's registry node is present as an OUTPUT here. That can
        // happen three ways: (1) a genuine first mint (NFT minted this tx),
        // (2) the covering node re-emitted by an insert, (3) an in-place node
        // update. In (2)/(3) the policy is ALREADY registered, so pre-existing
        // supply CAN be spent from a PLB input — e.g. preserved as a
        // non-subject token by a co-occurring third-party (seize) action, which
        // references neither this node nor that policy. So this is NOT "first
        // mint only",
        // and an output-only quantity check could be masked by that preserved
        // supply. `no_escape` sidesteps the case analysis entirely: it forbids
        // `own_policy` at any non-PLB output, so nothing minted can escape
        // regardless of how the node got here.
        let output_opt = list.at(self.outputs, index)
        expect Some(output) = output_opt
        expect verify_registry_node(output, registry_node_cs, own_policy)
        custody_ok()?
      }

      RefInput { index } -> {
        // ALREADY REGISTERED — verify the node via its reference input.
        let ref_input_opt = list.at(self.reference_inputs, index)
        expect Some(ref_input) = ref_input_opt
        expect
          verify_registry_node(ref_input.output, registry_node_cs, own_policy)

        or {
          // Delegate iff a delegate's redeemer names the same registry node
          // we did (it then enforces our PLB custody); otherwise enforce here.
          delegate_covers_own_registry_node(
            self.redeemers,
            self.reference_inputs,
            params_policy,
            index,
          ),
          custody_ok()?,
        }
      }
    }

    and {
      // Substandard's withdraw-0 logic must be invoked (proof of instance).
      // The credential to look for is the validator's `minting_logic_cred`
      // parameter — baked into the policy id at compile time, no separate
      // redeemer field needed.
      minting_logic_invoked?,
      valid_minting?,
    }
  }

  else(_) {
    fail
  }
}

/// Custody check (re-audit R-04): NO token of `own_policy` may sit at a
/// non-PLB output. Combined with ledger value-conservation this pins every
/// minted unit at the PLB — a freshly minted token cannot escape to a
/// non-programmable address, and pre-existing PLB supply cannot mask an escape
/// (the failure mode of the earlier check, which compared the absolute PLB
/// output total to the mint delta and could be satisfied by preserved supply).
///
/// Every PLB output must additionally carry an inline stake credential (so
/// ownership is well-defined). Inputs need no scan: any `own_policy` spent
/// must reappear at a PLB output or be burned, both of which this output-only
/// rule already forces through value-conservation.
///
/// Deliberately NOT enforced here: a ledger-impossible over-burn (burning more
/// than exists) — value-conservation makes the ledger reject that anyway.
fn no_escape(
  outputs: List<Output>,
  programmable_logic_base: Credential,
  own_policy: PolicyId,
) -> Bool {
  list.all(
    outputs,
    fn(output) {
      if output.address.payment_credential == programmable_logic_base {
        expect Some(Inline(_stake_cred)) = output.address.stake_credential
        // A minted programmable-token UTxO must stay seizable: no datum hash
        // (unspendable without the preimage), no reference script (bloats the
        // mandatory seizure continuing-output).
        prog_assets.is_seizable_output_shape(output)
      } else {
        dict.is_empty(assets.tokens(output.value, own_policy))
      }
    },
  )
}

fn verify_registry_node(
  output: Output,
  registry_node_cs: PolicyId,
  own_policy: PolicyId,
) -> Bool {
  // Strict: registry NFT's asset name MUST equal own_policy. This binds the
  // NFT identity to the datum key and removes implicit trust on the linked-list
  // invariant (asset_name == datum.key) enforced elsewhere.
  //
  // No need to compare `registry.minting_logic_script` against the validator's
  // `minting_logic_cred` parameter here. `registry_mint` already enforces that
  // the registered credential's inner hash is the one the policy id was
  // derived from (via `is_programmable_token_id_valid`). Since this
  // validator's `minting_logic_cred` parameter is also baked into the policy
  // id at compile time, collision-resistance of blake2b_224 implies the two
  // credentials must match. Checking again here would be redundant.
  expect assets.has_nft_strict(output.value, registry_node_cs, own_policy)?
  let registry_datum = expect_inline_datum(output)
  expect registry: RegistryNode = registry_datum
  registry.key == own_policy
}

/// True iff a delegate validator's currently-running redeemer names the
/// same registry node (by index) that our `RefInput { index }` already bound
/// to `own_policy`. If so, that delegate will validate `own_policy`'s mint
/// custody at runtime and issuance_mint can safely delegate.
///
/// The delegates' credentials are NOT parameters: they are the LIVE ones read
/// from the coordination UTxO's datum (`transfer_cred`, field 2;
/// `third_party_cred`, field 3), so delegation trust tracks in-place
/// upgrades — a retired credential can no longer act as a mint-custody
/// delegate.
///
/// We only need to compare indices — `own_registry_node_idx` is the index
/// from issuance_mint's RefInput redeemer, which `verify_registry_node`
/// has already shown to correspond to `own_policy`. So "same index" ⇒
/// "same policy" without re-extracting any key.
///
/// Every `None` case — no coordination UTxO among the reference inputs,
/// neither delegate invoked, or a delegate's redeemer naming a different
/// registry node — returns False, falling back to local custody. The
/// coordination locate is deliberately non-failing (`list.find` +
/// `has_nft_strict`) so non-delegating RefInput mints need no coordination
/// ref input.
fn delegate_covers_own_registry_node(
  redeemers: Pairs<ScriptPurpose, Data>,
  reference_inputs: List<Input>,
  params_policy: PolicyId,
  own_registry_node_idx: Int,
) -> Bool {
  when
    list.find(
      reference_inputs,
      fn(ref_input) {
        assets.has_nft_strict(
          ref_input.output.value,
          params_policy,
          params.protocol_params_token,
        )
      },
    )
  is {
    None -> False
    Some(coordination_ref) -> {
      let fields = unconstr_fields(expect_inline_datum(coordination_ref.output))
      or {
        // (a) the `transfer` validator validates our node's custody: its
        // proof walk resolves our node and `validate_transfer` contains the
        // minted supply at PLB.
        when
          find_transfer_redeemer(redeemers, params.transfer_cred_field(fields))
        is {
          None -> False
          Some(transfer_redeemer) ->
            transfer_scope_covers(transfer_redeemer, own_registry_node_idx)
        },
        // (b) the `third_party` (seize) validator does: its conservation check
        // (validate_3rd_party) covers minted subject-policy tokens, so trusting
        // it for custody is sound (Finding 04 precise delegation preserved).
        third_party_covers_own_registry_node(
          redeemers,
          params.third_party_cred_field(fields),
          own_registry_node_idx,
        ),
      }
    }
  }
}

/// Does the `third_party` (seize) validator's redeemer name the SAME
/// registry node our `RefInput { index }` did? Its `registry_node_idx` IS the
/// subject policy's node (single-policy), so "same index" ⇒ "same policy" —
/// the same reasoning as `transfer_scope_covers`.
/// None (third_party not invoked, or its redeemer names a different node) ⇒
/// no delegation, so custody falls back to local `no_escape`.
fn third_party_covers_own_registry_node(
  redeemers: Pairs<ScriptPurpose, Data>,
  third_party_cred: Credential,
  own_registry_node_idx: Int,
) -> Bool {
  when find_tp_redeemer(redeemers, third_party_cred) is {
    None -> False
    Some(ThirdPartyRedeemer { registry_node_idx, .. }) ->
      registry_node_idx == own_registry_node_idx
  }
}

/// Find the `third_party` validator's Withdraw redeemer in `tx.redeemers` and
/// decode it. Mirrors `find_transfer_redeemer`; returns None when the
/// third_party validator isn't invoked.
fn find_tp_redeemer(
  redeemers: Pairs<ScriptPurpose, Data>,
  cred: Credential,
) -> Option<ThirdPartyRedeemer> {
  when redeemers is {
    [] -> None
    [Pair(purpose, data), ..tail] ->
      when purpose is {
        Withdraw(c) ->
          if c == cred {
            expect tp: ThirdPartyRedeemer = data
            Some(tp)
          } else {
            find_tp_redeemer(tail, cred)
          }
        _ -> find_tp_redeemer(tail, cred)
      }
  }
}

/// Find the `transfer` validator's Withdraw redeemer in `tx.redeemers` and
/// decode it. Linear in `|redeemers|`. Returns None when the transfer
/// validator isn't invoked.
fn find_transfer_redeemer(
  redeemers: Pairs<ScriptPurpose, Data>,
  cred: Credential,
) -> Option<TransferRedeemer> {
  when redeemers is {
    [] -> None
    [Pair(purpose, data), ..tail] ->
      when purpose is {
        Withdraw(c) ->
          if c == cred {
            expect transfer_redeemer: TransferRedeemer = data
            Some(transfer_redeemer)
          } else {
            find_transfer_redeemer(tail, cred)
          }
        _ -> find_transfer_redeemer(tail, cred)
      }
  }
}

/// Scope check: does the given transfer redeemer name the SAME registry node
/// our `RefInput { index }` did? `proofs` must contain
/// `TokenExists { node_idx }` with `node_idx == own_registry_node_idx`. The
/// transfer validator's `verify_proofs` walks `proofs` in lockstep with
/// `input_assets`; if any input asset's policy lines up with this proof, it
/// resolves our index and validates against it. If positions don't line up,
/// it aborts and the tx fails — no escape path.
///
/// The `unfracking` validator is deliberately NOT a delegate: unfracking is
/// value-preserving, same-owner PLB restructuring with NO mint, so it never
/// validates an issuance's custody and cannot cover one (Finding 04 precise
/// delegation).
fn transfer_scope_covers(
  transfer_redeemer: TransferRedeemer,
  own_registry_node_idx: Int,
) -> Bool {
  let TransferRedeemer { proofs, .. } = transfer_redeemer
  let expected_proof = TokenExists(own_registry_node_idx)
  list.any(proofs, fn(proof: RegistryProof) { expected_proof == proof })
}
