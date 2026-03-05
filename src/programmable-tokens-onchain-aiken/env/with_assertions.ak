use aiken/collection/dict.{Dict}
use cardano/assets.{PolicyId, ada_policy_id}

/// Enforces that the given value has no ada.
pub fn assert_no_ada_policy(value: Dict<PolicyId, v>) -> Dict<PolicyId, v> {
  trace @"assert_no_ada_policy"
  expect None = dict.get(value, ada_policy_id)
  value
}
