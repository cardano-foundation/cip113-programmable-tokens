use aiken/collection/pairs
use cardano/assets.{PolicyId, ada_policy_id}

/// Enforces that the given value has no ada.
pub fn assert_no_ada_policy(value: Pairs<PolicyId, v>) -> Pairs<PolicyId, v> {
  trace @"assert_no_ada_policy"
  expect None = pairs.get_first(value, ada_policy_id)
  value
}
