use aiken/collection/list
use aiken/fuzz
use cardano/assets.{PolicyId, ada_asset_name, ada_policy_id} as value
use cardano/fuzz as cardano
use cardano/transaction.{InlineDatum, Input, Output}
use registry_node.{
  RegistryNode, new_registry_node_getter, with_key_and_3rd_party_logic,
  with_key_and_next_key, with_key_and_transfer_logic,
}

// ---------------------------------------------------- new_registry_node_getter

const registry_policy: PolicyId = "registry"

fn any_registry_node_reference_input() -> Fuzzer<Input> {
  let output_reference <- fuzz.and_then(cardano.output_reference())
  let address <- fuzz.and_then(cardano.address())
  let registry_node <- fuzz.and_then(any_registry_node())
  let min_ada_value = value.zero
    |> value.add(ada_policy_id, ada_asset_name, 1000000)
  fuzz.constant(
    Input {
      output_reference,
      output: Output {
        address,
        value: min_ada_value
          |> value.add(registry_policy, "", 1),
        datum: InlineDatum(as_data(registry_node)),
        reference_script: None,
      },
    },
  )
}

fn any_registry(min_nodes: Int, max_nodes: Int) -> Fuzzer<(Int, List<Input>)> {
  let before <- fuzz.and_then(fuzz.list_between(cardano.input(), 0, 2))
  let between <- fuzz.and_then(
    fuzz.list_between(any_registry_node_reference_input(), min_nodes, max_nodes),
  )
  let after <- fuzz.and_then(fuzz.list_between(cardano.input(), 0, 2))

  let len_before = list.length(before)

  let len_between = list.length(between)

  let ix <- fuzz.and_then(
    fuzz.int_between(len_before, len_before + len_between - 1),
  )

  fuzz.constant(
    (
      ix,
      before
        |> list.concat(between)
        |> list.concat(after),
    ),
  )
}

test prop_registry_lookup((ix, registry) via any_registry(1, 2)) {
  let get_registry_node = new_registry_node_getter(
    registry_policy,
    0,
    registry,
    fn(_) { fail },
  )
  expect _: RegistryNode = get_registry_node(ix)
}

test prop_registry_lookup_fail_no_node(
  (ix, registry) via any_registry(0, 0),
) fail {
  let get_registry_node = new_registry_node_getter(
    registry_policy,
    0,
    registry,
    fn(_) { fail },
  )
  get_registry_node(ix) != as_data(Void)
}

test prop_registry_lookup_fail_wrong_policy(
  (ix, registry) via any_registry(1, 1),
) fail {
  let get_registry_node = new_registry_node_getter(
    "foo",
    0,
    registry,
    fn(_) { fail },
  )
  get_registry_node(ix) != as_data(Void)
}

// -------------------------------------------------------------- with_key_and_*

fn any_registry_node() -> Fuzzer<RegistryNode> {
  let key <- fuzz.and_then(fuzz.bytearray_between(0, 32))
  let next <- fuzz.and_then(fuzz.bytearray_between(0, 32))
  let transfer_logic_script <- fuzz.and_then(cardano.credential())
  let third_party_transfer_logic_script <- fuzz.and_then(cardano.credential())
  let global_state_cs <- fuzz.and_then(cardano.policy_id())
  fuzz.constant(
    RegistryNode {
      key,
      next,
      transfer_logic_script,
      third_party_transfer_logic_script,
      global_state_cs,
    },
  )
}

test prop_with_key_and_transfer_logic_roundtrip(node via any_registry_node()) {
  let key, transfer_logic_script <- with_key_and_transfer_logic(node)
  and {
    (key == node.key)?,
    (transfer_logic_script == node.transfer_logic_script)?,
  }
}

test prop_with_key_and_next_key_roundtrip(node via any_registry_node()) {
  let key, next <- with_key_and_next_key(node)
  and {
    (key == node.key)?,
    (next == node.next)?,
  }
}

test prop_with_key_and_3rd_party_roundtrip(node via any_registry_node()) {
  let key, third_party_transfer_logic_script <- with_key_and_3rd_party_logic(
    node,
  )
  and {
    (key == node.key)?,
    (third_party_transfer_logic_script == node.third_party_transfer_logic_script)?,
  }
}
