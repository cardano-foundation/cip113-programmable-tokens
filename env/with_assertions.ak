use aiken/collection/pairs
use cardano/assets.{PolicyId, ada_policy_id}

/// Enforces that the given value has no ada. Enforced only under `--env
/// with_assertions`: the default build compiles `env/default.ak`'s identity
/// instead, so this is NOT a rail in the deployed script.
pub fn assert_no_ada_policy(value: Pairs<PolicyId, v>) -> Pairs<PolicyId, v> {
  trace @"assert_no_ada_policy"
  expect None = pairs.get_first(value, ada_policy_id)
  value
}
