use aiken/collection/dict.{Dict}
use cardano/assets.{PolicyId}

pub fn assert_no_ada_policy(value: Dict<PolicyId, v>) -> Dict<PolicyId, v> {
  value
}
