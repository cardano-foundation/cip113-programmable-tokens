use aiken/collection/dict
use aiken/collection/list
// Programmable Token Issuance Minting Policy
// This policy handles minting and burning of registered programmable tokens
// Migrated from SmartTokens.Contracts.Issuance

use cardano/address.{Credential, Inline}
use cardano/assets.{PolicyId}
use cardano/transaction.{Output, ScriptPurpose, Transaction, Withdraw}
use registry_node.{RegistryNode}
use tokens
use types.{
  MintingRegistryProof, OutputIndex, ProgrammableLogicGlobalRedeemer, RefInput,
  RegistryProof, ThirdPartyAct, TokenExists, TransferAct,
}
use utils.{expect_inline_datum}

validator issuance_mint(
  // Programmable Token Script Hash
  programmable_logic_base: Credential,
  // Registry Node Currency Symbol - used to verify registry proofs for token minting
  registry_node_cs: PolicyId,
  // <- the hash of the contract of the logic for minting.
  minting_logic_cred: Credential,
  // PLGlobal stake credential. Looked up in `tx.redeemers` (as the
  // `Withdraw(plg_stake_cred)` script-purpose) to fetch PLGlobal's
  // currently-running redeemer; presence == invocation. issuance_mint
  // delegates mint-output custody to PLGlobal iff that redeemer names
  // (by `registry_node_idx` or by `TokenExists { node_idx }` proof) the
  // SAME registry node our own `RefInput { index }` already verified.
  plg_stake_cred: Credential,
) {
  mint(redeemer: MintingRegistryProof, own_policy: PolicyId, self: Transaction) {
    // Single-pass withdrawal scan for ONLY the substandard's minting-logic
    // proof. (Previously this was foldl2 with a second accumulator for
    // "is PLGlobal invoked"; that signal is now rediscovered for free by
    // the redeemer lookup below — PLGlobal is invoked iff its withdraw
    // script-purpose has an entry in `tx.redeemers`. One scan does both.)
    let minting_logic_invoked = list.foldl(
      self.withdrawals,
      False,
      fn(wdrl, acc) {
        let Pair(cred, _amount) = wdrl
        acc || cred == minting_logic_cred
      },
    )

    // Registry proof determines WHO validates outputs:
    //
    //   OutputIndex → First mint. PLGlobal doesn't know or see the registry
    //                 entry for this token. issuance_mint MUST validate
    //                 outputs. Qty always > 0.
    //
    //   RefInput { index } → PLGlobal MAY validate outputs, but only when
    //              its currently-running redeemer names the SAME registry
    //              node our `index` points at. Because our
    //              `verify_registry_node` has already bound this index to
    //              `own_policy` (NFT asset name == own_policy and
    //              datum.key == own_policy), comparing indices is
    //              sufficient — we do NOT need to re-extract a policy id
    //              from PLGlobal's redeemer.
    //              Per-mode scope:
    //                * TransferAct  → `proofs` contains
    //                                 `TokenExists { node_idx: index }`.
    //                * ThirdPartyAct → `registry_node_idx == index`.
    //              If scope covers → delegate. Otherwise issuance_mint
    //              validates outputs itself.
    //
    // Closes Finding 04: the previous broad `plg_invoked` signal silently
    // let mints of non-seized policies escape during ThirdPartyAct, and a
    // sibling TransferAct + non-PLB-route case became visible after
    // Finding 02's fix. The precise check ensures issuance_mint only trusts
    // PLGlobal for the specific registry node our own redeemer named.
    let valid_minting = when redeemer is {
      OutputIndex { index } -> {
        // FIRST MINT — registry node being (re-)created in this tx
        let output_opt = list.at(self.outputs, index)
        expect Some(output) = output_opt
        expect verify_registry_node(output, registry_node_cs, own_policy)
        // First mint ⇒ all minted tokens must go to PLB
        let minted = self.mint |> assets.tokens(own_policy)
        validate_mint_outputs(
          self.outputs,
          programmable_logic_base,
          own_policy,
          minted,
        )?
      }

      RefInput { index } -> {
        // ALREADY REGISTERED — verify registry node
        let ref_input_opt = list.at(self.reference_inputs, index)
        expect Some(ref_input) = ref_input_opt
        expect
          verify_registry_node(ref_input.output, registry_node_cs, own_policy)

        or {
          // Precise delegation: look up PLGlobal's redeemer in
          // `tx.redeemers`; if found and it names the same registry node
          // we did, delegate. Otherwise (PLGlobal not invoked, or a
          // different registry node) → fall through and validate
          // ourselves.
          plgl_delegates_for_own_registry_node(
            self.redeemers,
            plg_stake_cred,
            index,
          ),
          validate_mint_outputs(
            self.outputs,
            programmable_logic_base,
            own_policy,
            self.mint |> assets.tokens(own_policy),
          )?,
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

/// Validate that ALL minted tokens end up at PLB outputs with stake credentials.
/// Collects tokens for `own_policy` across all PLB outputs and checks exact match.
/// Reuses `tokens.union` and `value.tokens` (battle-tested in PLGlobal).
fn validate_mint_outputs(
  outputs: List<Output>,
  programmable_logic_base: Credential,
  own_policy: PolicyId,
  expected: tokens.Tokens,
) -> Bool {
  let total_at_plb = list.foldl(
    outputs,
    dict.empty,
    fn(output, acc) {
      if output.address.payment_credential == programmable_logic_base {
        expect Some(Inline(_stake_cred)) = output.address.stake_credential
        tokens.union(acc, assets.tokens(output.value, own_policy))
      } else {
        acc
      }
    },
  )
  (total_at_plb == expected)?
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
/// We only need to compare indices — `own_registry_node_idx` is the index
/// from issuance_mint's RefInput redeemer, which `verify_registry_node`
/// has already shown to correspond to `own_policy`. So "same index" ⇒
/// "same policy" without re-extracting any key.
///
/// Returns False when PLGlobal isn't invoked at all (`None` from the
/// redeemer lookup) or when PLGlobal's redeemer names a different
/// registry node.
fn plgl_delegates_for_own_registry_node(
  redeemers: Pairs<ScriptPurpose, Data>,
  plg_stake_cred: Credential,
  own_registry_node_idx: Int,
) -> Bool {
  when find_plgl_redeemer(redeemers, plg_stake_cred) is {
    None -> False
    Some(plg_redeemer) -> plgl_scope_covers(plg_redeemer, own_registry_node_idx)
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
    TransferAct { proofs } -> {
      let expected_proof = TokenExists(own_registry_node_idx)
      list.any(proofs, fn(proof: RegistryProof) { expected_proof == proof })
    }
    ThirdPartyAct { registry_node_idx, .. } ->
      registry_node_idx == own_registry_node_idx
  }
}
