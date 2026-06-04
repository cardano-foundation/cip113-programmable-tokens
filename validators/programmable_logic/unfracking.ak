//// Programmable Logic Global — Unfracking action (Finding 17)
////
//// Finding 17: lets a holder REDISTRIBUTE the programmable tokens they
//// already hold across multiple PLB UTxOs without invoking any substandard
//// transfer logic. The whole point is to break up a multi-policy PLB UTxO
//// into single-policy UTxOs so that a freeze (or other compliance action)
//// scoped to one policy stops co-locating its blast radius onto unrelated
//// policies.
////
//// Single-owner invariant
//// ----------------------
////
//// Unfracking is by design a SAME-OWNER restructuring action. All PLB
//// inputs and all PLB outputs must share ONE stake credential — the one
//// pinned by the first PLB input we encounter. A multi-credential variant
//// would let tokens cross between owners without invoking
//// `transfer_logic_script` (the bouncer that gates real transfers); that
//// is a transfer in disguise, not an unfracking. If a holder controls two
//// of their own credentials and wants to shuffle tokens between them,
//// that is a TransferAct between two owners (one of which is also them),
//// not an Unfracking.
////
//// What this action permits:
////   * Spending one or more PLB inputs the caller is authorised over —
////     either by signing for a vkey stake credential or by invoking the
////     script's withdraw-0 (same authorisation pattern as TransferAct).
////   * Reshaping the value of those inputs into any number of PLB
////     outputs, each at the same payment_credential (PLB) and the same
////     stake_credential pinned by the first PLB input.
////   * Free choice of datum and reference_script on each new PLB output.
////     Unfracking is by design a layout-restructuring action.
////
//// What this action forbids:
////   * Any mint or burn (`tx.mint` must be zero). Unfracking is strictly
////     value-preserving; mint/burn is issuance_mint's job.
////   * Sending programmable tokens to a non-PLB address. Falls out for free
////     from `total_output_at_plb == total_input_at_plb` per policy + ledger
////     value conservation + mint==0: any PLB-side surplus would have to
////     come from a non-PLB input (rare/impossible in honest setups), and
////     any leak to non-PLB would force a PLB-side deficit which the
////     equality rejects.
////   * Mixing different stake credentials across PLB inputs (or routing
////     a PLB output to a stake_cred other than the one pinned by the
////     inputs). This is the back-door we have to slam shut, otherwise
////     Unfracking becomes "transfer-without-transfer-logic".
////
//// Cost shape: O(|inputs| + |outputs|) for the per-input authorisation
//// scan and the per-output stake-credential equality check. The asset
//// equality check is O(|policies| + |tokens|) over the canonically-sorted
//// `Assets` collected from each side. Authorisation is checked exactly
//// once per transaction (on the first PLB input that pins the stake
//// credential); subsequent inputs share the same credential and inherit
//// the authorisation.

use assets.{Assets}
use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets as value
use cardano/transaction.{Input, Output, Transaction}
use list
use pairs

/// Validate an Unfracking action. See module docstring for the full
/// invariant list.
pub fn validate_unfracking(
  self: Transaction,
  prog_logic_cred: Credential,
) -> Bool {
  // Finding 17: Unfracking is value-preserving by construction. Any
  // mint/burn would silently change the policy totals we then compare
  // input-vs-output equal — easier and clearer to refuse the redeemer
  // outright when mint is non-empty than to thread mint deltas through
  // the equality check.
  expect value.is_zero(self.mint)

  let has_signatory =
    list.has_or_fail(self.extra_signatories, _)
  let has_withdrawal_cred =
    fn(cred: Credential) { pairs.has_key_or_fail(self.withdrawals, cred) }

  let
    input_assets,
    target_cred,
  <-
    collect_plb_inputs(
      self.inputs,
      prog_logic_cred,
      has_signatory,
      has_withdrawal_cred,
      [],
      None,
    )

  // The tx must consume at least one PLB UTxO — otherwise there is
  // nothing to unfrack and the redeemer is meaningless.
  expect Some(target) = target_cred

  // Output scan: collect Assets from outputs at PLB AND require every
  // such output's stake credential to equal `target`. Folding both
  // checks into the same traversal keeps the cost down.
  let output_assets =
    collect_plb_outputs(self.outputs, prog_logic_cred, target)

  // Conservation per policy/token: the total at PLB must be identical
  // input-to-output. Equality (not containment) is intentional — see
  // module docstring on why the two-way bound forces ledger
  // conservation to do the no-escape work for us.
  input_assets == output_assets
}

/// Walk PLB inputs once, accumulating (sum of non-ADA assets, target
/// stake credential pinned by the first PLB input). Authorisation is
/// checked ONCE — on the first PLB input — and every subsequent PLB
/// input must share the same stake credential, so a single
/// signatory / withdraw-0 covers them all.
fn collect_plb_inputs(
  inputs: List<Input>,
  prog_logic_cred: Credential,
  has_signatory: fn(ByteArray) -> Bool,
  has_withdrawal_cred: fn(Credential) -> Bool,
  acc_assets: Assets,
  target_cred: Option<Credential>,
  return: fn(Assets, Option<Credential>) -> result,
) -> result {
  when inputs is {
    [] -> return(acc_assets, target_cred)
    [input, ..tail] -> {
      let output = input.output
      if output.address.payment_credential == prog_logic_cred {
        expect Some(Inline(stake_cred)) = output.address.stake_credential
        let next_target =
          when target_cred is {
            None -> {
              // First PLB input — authorise the cred once and pin it.
              when stake_cred is {
                VerificationKey(pkh) -> {
                  expect has_signatory(pkh)
                }
                Script(_hash) -> {
                  expect has_withdrawal_cred(stake_cred)
                }
              }
              Some(stake_cred)
            }
            Some(existing) -> {
              // Subsequent PLB input — must match the pinned cred. The
              // authorisation already covers any input with this cred.
              expect stake_cred == existing
              target_cred
            }
          }
        let next_assets =
          assets.union(
            output.value
              |> assets.from_value
              |> list.tail,
            acc_assets,
          )
        collect_plb_inputs(
          tail,
          prog_logic_cred,
          has_signatory,
          has_withdrawal_cred,
          next_assets,
          next_target,
          return,
        )
      } else {
        collect_plb_inputs(
          tail,
          prog_logic_cred,
          has_signatory,
          has_withdrawal_cred,
          acc_assets,
          target_cred,
          return,
        )
      }
    }
  }
}

/// Walk outputs once, summing non-ADA assets of every PLB-bound output
/// and requiring its stake credential to equal `target_cred` — the
/// credential pinned by the first PLB input. Routing PLB tokens to any
/// other stake credential would be a transfer in disguise (no
/// transfer_logic invoked) — exactly what Finding 17's recommendation
/// says Unfracking must NOT permit.
fn collect_plb_outputs(
  outputs: List<Output>,
  prog_logic_cred: Credential,
  target_cred: Credential,
) -> Assets {
  when outputs is {
    [] -> []
    [output, ..tail] -> {
      let tail_assets =
        collect_plb_outputs(tail, prog_logic_cred, target_cred)
      if output.address.payment_credential == prog_logic_cred {
        expect Some(Inline(stake_cred)) = output.address.stake_credential
        // Single-owner gate: outputs may only carry the pinned cred.
        expect stake_cred == target_cred
        assets.union(
          output.value
            |> assets.from_value
            |> list.tail,
          tail_assets,
        )
      } else {
        tail_assets
      }
    }
  }
}
