use aiken/builtin.{equals_bytearray, less_than_bytearray}
use aiken/collection/dict.{Dict}
use assets.{Assets}
use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId} as value
use cardano/transaction.{Input, Output, Transaction}
use list
use pairs
use registry_node.{with_key_and_next_key, with_key_and_transfer_logic}
use tokens
use types.{RegistryProof, TokenDoesNotExist, TokenExists}

/// Validate a transfer action
pub fn validate_transfer(
  self: Transaction,
  prog_logic_cred: Credential,
  get_registry_node: fn(Int) -> Data,
  proofs: List<RegistryProof>,
) -> Bool {
  // NOTE: The programmable logic global is alway invoked via a withdrawal, so
  // we know there's AT LEAST ONE withdrawal.
  let first_withdrawal = list.head(self.withdrawals).1st
  let has_withdrawal =
    new_withdrawal_checker(
      fn(script_hash) { script_hash == first_withdrawal },
      list.tail(self.withdrawals),
    )

  // Collect all programmable tokens across inputs and minted/burned values.
  let input_assets = collect_input_assets(self, has_withdrawal, prog_logic_cred)

  // Collect all outputs that carry programmable tokens. We use them to ensure that
  // prog tokens cannot escape their fate.
  let output_assets =
    assets.collect_output_assets(self.outputs, prog_logic_cred)

  // Check transfer logic for each programmable token type and filter to only programmable tokens.
  [] == verify_proofs(
    proofs,
    choose_registered_token_with(get_registry_node, has_withdrawal, _, _, _, _),
    input_assets,
    output_assets,
  )
}

fn new_withdrawal_checker(
  has_withdrawal: fn(Credential) -> Bool,
  withdrawals: Pairs<Credential, Int>,
) -> fn(Credential) -> Bool {
  when withdrawals is {
    [] -> has_withdrawal
    [Pair(head, _), ..tail] ->
      new_withdrawal_checker(
        fn(script_hash) { head == script_hash || has_withdrawal(script_hash) },
        tail,
      )
  }
}

fn collect_input_assets(
  tx: Transaction,
  has_withdrawal: fn(Credential) -> Bool,
  prog_logic_cred: Credential,
) -> Assets {
  let has_signatory =
    list.has_or_fail(tx.extra_signatories, _)

  assets.collect(
    tx.inputs,
    assets.from_value(tx.mint),
    fn(input, select, discard) {
      let output = input.output
      if output.address.payment_credential == prog_logic_cred {
        expect Some(Inline(stake_cred)) = output.address.stake_credential
        when stake_cred is {
          VerificationKey(pkh) -> {
            expect has_signatory(pkh)
          }
          Script(_hash) -> {
            expect has_withdrawal(stake_cred)
          }
        }
        select(output)
      } else {
        discard()
      }
    },
  )
}

/// Get inputs from prog_logic_cred and verify ALL have proper authorization
/// This function enforces ownership by requiring that every input from prog_logic_cred
/// is authorized by its stake credential (signature or script invocation).
/// If ANY input lacks authorization, the transaction FAILS.
/// Sum values from a list of inputs
/// Check transfer logic for each currency symbol and filter to only programmable tokens
fn verify_proofs(
  proofs: List<RegistryProof>,
  choose_registered_token: fn(
    PolicyId,
    RegistryProof,
    fn() -> List<RegistryProof>,
    fn() -> List<RegistryProof>,
  ) ->
    List<RegistryProof>,
  input_assets: Pairs<PolicyId, Dict<AssetName, Int>>,
  output_assets: Pairs<PolicyId, Dict<AssetName, Int>>,
) -> List<RegistryProof> {
  when input_assets is {
    [] -> proofs
    [Pair(policy, head_input_tokens), ..tail_input_assets] ->
      // We expect one proof per policy, if not, this blows up and halts the validation.
      choose_registered_token(
        policy,
        list.head(proofs),
        fn() {
          let tail_output_assets =
            if head_input_tokens == dict.empty {
              // Tokens have been entirely consumed (a.k.a burned) so they won't appear in outputs.
              output_assets
            } else {
              // Existing programmable token, must be in output.

              // Outputs must be a superset of inputs, so they may contain extra
              // policies not found in validated inputs. Yet, both input assets and
              // output assets are in ascending policy order.
              let
                head_output_tokens,
                tail_output_assets,
              <- pairs.pop_until(output_assets, equals_bytearray(policy, _))
              expect
                tokens.contains(
                  dict.to_pairs(head_output_tokens),
                  dict.to_pairs(head_input_tokens),
                )

              tail_output_assets
            }

          verify_proofs(
            list.tail(proofs),
            choose_registered_token,
            tail_input_assets,
            tail_output_assets,
          )
        },
        fn() {
          // Not a programmable token, skip it
          verify_proofs(
            list.tail(proofs),
            choose_registered_token,
            tail_input_assets,
            output_assets,
          )
        },
      )
  }
}

/// Validate a single currency symbol against its proof
/// Returns True if the token IS a programmable token (TokenExists with valid proof)
/// Returns False if the token is NOT a programmable token (TokenDoesNotExist with valid proof)
/// FAILS the transaction if any proof is invalid
fn choose_registered_token_with(
  get_registry_node: fn(Int) -> Data,
  has_withdrawal: fn(Credential) -> Bool,
  policy: PolicyId,
  proof: RegistryProof,
  when_registered: fn() -> result,
  when_not_registered: fn() -> result,
) -> result {
  when proof is {
    TokenExists { node_idx } -> {
      let
        key,
        transfer_logic_script,
      <- with_key_and_transfer_logic(get_registry_node(node_idx))

      // Validate the node's key matches the currency symbol
      expect key == policy

      // Validate the transfer logic script is invoked
      expect has_withdrawal(transfer_logic_script)

      when_registered()
    }

    TokenDoesNotExist { node_idx } -> {
      let key, next <- with_key_and_next_key(get_registry_node(node_idx))

      // Validate the node covers the currency symbol (node.key < policy < node.next)
      expect less_than_bytearray(key, policy)
      expect less_than_bytearray(policy, next)

      // This is NOT a programmable token (proof is valid)
      when_not_registered()
    }
  }
}
