use aiken/builtin.{unconstr_fields}
use aiken/collection/dict
use aiken/collection/list
// Programmable Token Issuance Minting Policy
// This policy handles minting and burning of registered programmable tokens
// Migrated from SmartTokens.Contracts.Issuance

use cardano/address.{Credential, Inline}
use cardano/assets.{PolicyId}
use cardano/transaction.{Input, Output, ScriptPurpose, Transaction, Withdraw}
use programmable_logic/params
use registry_node.{RegistryNode}
use types.{
  MintingRegistryProof, OutputIndex, ProgrammableLogicGlobalRedeemer, RefInput,
  RegistryProof, ThirdPartyAct, TokenExists, TransferAct, UnfrackingAct,
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
  // the same parameter PLB and PLGlobal take. Read ONLY inside the
  // `RefInput` delegation branch, where it locates the coordination UTxO
  // among `reference_inputs` and reads the LIVE PLGlobal credential from
  // its datum (field 3, `prog_logic_global_cred`). Delegation then keys on
  // THAT credential, so an in-place PLG upgrade automatically retires the
  // old credential as a mint-custody delegate. Coordination UTxO absent ⇒
  // no delegation ⇒ local `no_escape` custody (fail-safe). The OutputIndex
  // path never reads it.
  params_policy: PolicyId,
) {
  mint(redeemer: MintingRegistryProof, own_policy: PolicyId, self: Transaction) {
    // Single-pass withdrawal scan for ONLY the substandard's minting-logic
    // proof. (Previously this was foldl2 with a second accumulator for
    // "is PLGlobal invoked"; that signal is now rediscovered for free by
    // the redeemer lookup below — PLGlobal is invoked iff its withdraw
    // script-purpose has an entry in `tx.redeemers`. One scan does both.)
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
    //     tx (freshly minted, OR re-emitted by a node update/insert). PLGlobal
    //     does not see this node, so issuance_mint enforces custody itself.
    //
    //   RefInput { index } → the node is a reference input, and PLGlobal MAY
    //     enforce custody instead — but only when its redeemer names the SAME
    //     registry node our `index` points at. `verify_registry_node` has
    //     already bound that index to `own_policy` (NFT asset name and
    //     datum.key both == own_policy), so comparing indices suffices — no
    //     need to re-extract a policy id from PLGlobal's redeemer. Scope:
    //       * TransferAct   → `proofs` contains `TokenExists { node_idx: index }`
    //       * ThirdPartyAct → `registry_node_idx == index`
    //     If PLGlobal covers us → delegate; otherwise enforce custody here.
    //
    // Closes Finding 04 / re-audit R-04: the previous broad `plg_invoked`
    // signal let mints of non-covered policies escape; this precise check
    // trusts PLGlobal only for the specific node our own redeemer named, and
    // `no_escape` (below) catches any token this validator does mint.
    let valid_minting = when redeemer is {
      OutputIndex { index } -> {
        // The policy's registry node is present as an OUTPUT here. That can
        // happen three ways: (1) a genuine first mint (NFT minted this tx),
        // (2) the covering node re-emitted by an insert, (3) an in-place node
        // update. In (2)/(3) the policy is ALREADY registered, so pre-existing
        // supply CAN be spent from a PLB input — e.g. preserved as a
        // non-subject token by a co-occurring ThirdPartyAct, which references
        // neither this node nor that policy. So this is NOT "first mint only",
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
          // Delegate iff PLGlobal's redeemer names the same registry node we
          // did (it then enforces our PLB custody); otherwise enforce here.
          plgl_delegates_for_own_registry_node(
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
        True
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

/// True iff PLGlobal's currently-running redeemer names the same registry
/// node (by index) that our `RefInput { index }` already bound to
/// `own_policy`. If so, PLGlobal will validate `own_policy`'s mint custody
/// at runtime and issuance_mint can safely delegate.
///
/// PLGlobal's credential is NOT a parameter: it is the LIVE one read from
/// the coordination UTxO's datum (field 3, `prog_logic_global_cred`), so
/// delegation trust tracks in-place PLG upgrades — a retired credential
/// can no longer act as a mint-custody delegate.
///
/// We only need to compare indices — `own_registry_node_idx` is the index
/// from issuance_mint's RefInput redeemer, which `verify_registry_node`
/// has already shown to correspond to `own_policy`. So "same index" ⇒
/// "same policy" without re-extracting any key.
///
/// Every `None` case — no coordination UTxO among the reference inputs,
/// PLGlobal not invoked at all, or PLGlobal's redeemer naming a different
/// registry node — returns False, falling back to local custody. The
/// coordination locate is deliberately non-failing (`list.find` +
/// `has_nft_strict`) so non-delegating RefInput mints need no coordination
/// ref input.
fn plgl_delegates_for_own_registry_node(
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
      let plg_cred = params.prog_logic_global_cred_field(
        unconstr_fields(expect_inline_datum(coordination_ref.output)),
      )
      when find_plgl_redeemer(redeemers, plg_cred) is {
        None -> False
        Some(plg_redeemer) ->
          plgl_scope_covers(plg_redeemer, own_registry_node_idx)
      }
    }
  }
}

/// Find PLGlobal's Withdraw redeemer in `tx.redeemers` and decode it.
/// Linear in `|redeemers|`. Returns None when PLGlobal isn't invoked.
fn find_plgl_redeemer(
  redeemers: Pairs<ScriptPurpose, Data>,
  cred: Credential,
) -> Option<ProgrammableLogicGlobalRedeemer> {
  when redeemers is {
    [] -> None
    [Pair(purpose, data), ..tail] ->
      when purpose is {
        Withdraw(c) ->
          if c == cred {
            expect plg: ProgrammableLogicGlobalRedeemer = data
            Some(plg)
          } else {
            find_plgl_redeemer(tail, cred)
          }
        _ -> find_plgl_redeemer(tail, cred)
      }
  }
}

/// Per-mode scope check: does the given PLGlobal redeemer name the SAME
/// registry node our `RefInput { index }` did?
///
///   * TransferAct  → `proofs` must contain `TokenExists { node_idx }`
///                    where `node_idx == own_registry_node_idx`. PLGlobal's
///                    `verify_proofs` walks `proofs` in lockstep with
///                    `input_assets`; if any input asset's policy lines up
///                    with this proof, PLGlobal will resolve our index and
///                    validate against it. If positions don't line up,
///                    PLGlobal aborts and the tx fails — no escape path.
///   * ThirdPartyAct → `registry_node_idx == own_registry_node_idx`.
///                    Current ThirdPartyAct is single-policy; the index in
///                    the redeemer IS the seized policy's registry node.
///                    Identical to ours ⇒ identical policy.
fn plgl_scope_covers(
  plg_redeemer: ProgrammableLogicGlobalRedeemer,
  own_registry_node_idx: Int,
) -> Bool {
  when plg_redeemer is {
    TransferAct { proofs, .. } -> {
      let expected_proof = TokenExists(own_registry_node_idx)
      list.any(proofs, fn(proof: RegistryProof) { expected_proof == proof })
    }
    ThirdPartyAct { registry_node_idx, .. } ->
      registry_node_idx == own_registry_node_idx
    // UnfrackingAct (Finding 17) is value-preserving, same-owner PLB
    // restructuring with NO mint — it never validates an issuance's custody, so
    // it cannot cover one. Deny delegation (Finding 04 precise delegation):
    // issuance_mint must validate the mint outputs itself, not trust unfracking.
    UnfrackingAct { .. } -> False
  }
}
