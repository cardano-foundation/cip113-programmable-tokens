//// Programmable Logic Global — Unfracking action (Finding 17)
////
//// Finding 17: lets a holder REDISTRIBUTE the programmable tokens they
//// already hold across multiple PLB UTxOs without invoking any substandard
//// transfer logic. The whole point is to break up a multi-policy PLB UTxO
//// into single-policy UTxOs so that a freeze (or other compliance action)
//// scoped to one policy stops co-locating its blast radius onto unrelated
//// policies.
////
//// What this action permits:
////   * Spending one or more PLB inputs the caller is authorised over (vkey
////     signer, or script withdrawal — same authorisation pattern as
////     TransferAct).
////   * Reshaping the value of those inputs into any number of PLB outputs,
////     each with a stake credential drawn from the authorisation set
////     (cannot launder tokens to a third party — that would be a transfer).
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
////   * Routing outputs to a stake credential the caller did not
////     authorise. This is the back-door we have to slam shut, otherwise
////     Unfracking becomes "transfer-without-transfer-logic".
////
//// Cost shape: O(|inputs| + |outputs|) for the per-input authorisation
//// scan and the per-output stake-credential lookup. The asset equality
//// check is O(|policies| + |tokens|) over the canonically-sorted
//// `Assets` collected from each side.

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

  let has_signatory = list.has_or_fail(self.extra_signatories, _)
  let has_withdrawal_cred =
    fn(cred: Credential) { pairs.has_key_or_fail(self.withdrawals, cred) }

  let
    input_assets,
    authorised_stake_creds,
  <- collect_plb_inputs(
       self.inputs,
       prog_logic_cred,
       has_signatory,
       has_withdrawal_cred,
       [],
       [],
     )
  // Output scan: collect Assets from outputs at PLB AND require every
  // such output's stake credential to be in `authorised_stake_creds`.
  // Folding both checks into the same traversal keeps the cost down.
  let output_assets =
    collect_plb_outputs(self.outputs, prog_logic_cred, authorised_stake_creds)

  // Conservation per policy/token: the total at PLB must be identical
  // input-to-output. Equality (not containment) is intentional — see
  // module docstring on why the two-way bound forces ledger
  // conservation to do the no-escape work for us.
  input_assets == output_assets
}

/// Walk PLB inputs once, accumulating (sum of non-ADA assets, set of
/// stake credentials seen). Authorisation is checked inline per input
/// — an unauthorised PLB input halts the validator via `expect`.
fn collect_plb_inputs(
  inputs: List<Input>,
  prog_logic_cred: Credential,
  has_signatory: fn(ByteArray) -> Bool,
  has_withdrawal_cred: fn(Credential) -> Bool,
  acc_assets: Assets,
  acc_creds: List<Credential>,
  return: fn(Assets, List<Credential>) -> result,
) -> result {
  when inputs is {
    [] -> return(acc_assets, acc_creds)
    [input, ..tail] -> {
      let output = input.output
      if output.address.payment_credential == prog_logic_cred {
        expect Some(Inline(stake_cred)) = output.address.stake_credential
        when stake_cred is {
          VerificationKey(pkh) -> {
            expect has_signatory(pkh)
          }
          Script(_hash) -> {
            expect has_withdrawal_cred(stake_cred)
          }
        }
        let next_assets =
          assets.union(
            output.value
              |> assets.from_value
              |> list.tail,
            acc_assets,
          )
        let next_creds = insert_cred_unique(stake_cred, acc_creds)
        collect_plb_inputs(
          tail,
          prog_logic_cred,
          has_signatory,
          has_withdrawal_cred,
          next_assets,
          next_creds,
          return,
        )
      } else {
        collect_plb_inputs(
          tail,
          prog_logic_cred,
          has_signatory,
          has_withdrawal_cred,
          acc_assets,
          acc_creds,
          return,
        )
      }
    }
  }
}

/// O(n) credential dedup. Open-coded because the equivalent stdlib
/// `list.has` Eq-polymorphic shape trips Aiken's type checker when
/// instantiated at `Credential` in this position (the compiler exits
/// non-zero with no diagnostic). See `cred_member` below for the
/// matching read-side helper.
fn insert_cred_unique(
  cred: Credential,
  acc: List<Credential>,
) -> List<Credential> {
  when acc is {
    [] -> [cred]
    [head, ..tail] ->
      if head == cred {
        acc
      } else {
        [head, ..insert_cred_unique(cred, tail)]
      }
  }
}

/// Walk outputs once, summing non-ADA assets of every PLB-bound output
/// and rejecting any PLB output whose stake credential isn't in the
/// authorised set. Routing PLB tokens to an unauthorised stake credential
/// would be a transfer in disguise (no transfer_logic invoked) — exactly
/// what Finding 17's recommendation says Unfracking must NOT permit.
fn collect_plb_outputs(
  outputs: List<Output>,
  prog_logic_cred: Credential,
  authorised_stake_creds: List<Credential>,
) -> Assets {
  when outputs is {
    [] -> []
    [output, ..tail] -> {
      let tail_assets =
        collect_plb_outputs(tail, prog_logic_cred, authorised_stake_creds)
      if output.address.payment_credential == prog_logic_cred {
        expect Some(Inline(stake_cred)) = output.address.stake_credential
        // Authorisation gate on the destination stake credential.
        expect cred_member(stake_cred, authorised_stake_creds)
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

/// Linear membership check for credentials. We have our own copy because
/// the stdlib `list.has` Eq-polymorphic shape currently trips Aiken's
/// type checker when instantiated at `Credential` in this position (the
/// compiler exits non-zero with no diagnostic). Inlining the recursion
/// sidesteps it without losing semantics.
fn cred_member(cred: Credential, acc: List<Credential>) -> Bool {
  when acc is {
    [] -> False
    [head, ..tail] -> head == cred || cred_member(cred, tail)
  }
}
