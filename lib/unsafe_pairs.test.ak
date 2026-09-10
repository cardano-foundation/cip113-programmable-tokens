use aiken/builtin.{equals_bytearray}
use unsafe_pairs

// ------------------------------------------------------------- has_key_or_fail

test has_key_or_fail_matrix() {
  and {
    unsafe_pairs.has_key_or_fail([Pair("a", 1)], "a")?,
    unsafe_pairs.has_key_or_fail([Pair("a", 1), Pair("b", 2)], "a")?,
    unsafe_pairs.has_key_or_fail([Pair("a", 1), Pair("b", 2)], "b")?,
    unsafe_pairs.has_key_or_fail(
      [Pair("b", 2), Pair("a", 1), Pair("c", 3)],
      "a",
    )?,
    unsafe_pairs.has_key_or_fail(
      [Pair("b", 2), Pair("a", 1), Pair("c", 3)],
      "b",
    )?,
    unsafe_pairs.has_key_or_fail(
      [Pair("b", 2), Pair("a", 1), Pair("c", 3)],
      "c",
    )?,
  }
}

test has_key_or_fail_empty() fail {
  unsafe_pairs.has_key_or_fail([], "a")
}

test has_key_or_fail_not_in_list_1() fail {
  unsafe_pairs.has_key_or_fail([Pair("a", 1)], "b")
}

test has_key_or_fail_not_in_list_2() fail {
  unsafe_pairs.has_key_or_fail([Pair("a", 1), Pair("b", 2)], "")
}

test has_key_or_fail_not_in_list_3() fail {
  unsafe_pairs.has_key_or_fail([Pair("b", 2), Pair("a", 1), Pair("c", 3)], "aa")
}

// ------------------------------------------------------------------- pop_until

test pop_until_first_and_only() {
  let v, rest <- unsafe_pairs.expect_pop_until_and_then(
    [Pair("a", 1)],
    equals_bytearray("a", _),
  )
  and {
    (v == 1)?,
    (rest == [])?,
  }
}

test pop_until_first_and_rest() {
  let v, rest <- unsafe_pairs.expect_pop_until_and_then(
    [Pair("a", 1), Pair("b", 2)],
    equals_bytearray("a", _),
  )
  and {
    (v == 1)?,
    (rest == [Pair("b", 2)])?,
  }
}

test pop_until_middle() {
  let v, rest <- unsafe_pairs.expect_pop_until_and_then(
    [Pair("b", 1), Pair("a", 2), Pair("c", 3)],
    equals_bytearray("a", _),
  )
  and {
    (v == 2)?,
    (rest == [Pair("c", 3)])?,
  }
}

test pop_until_last() {
  let v, rest <- unsafe_pairs.expect_pop_until_and_then(
    [Pair("b", 1), Pair("a", 2), Pair("c", 3)],
    equals_bytearray("c", _),
  )
  and {
    (v == 3)?,
    (rest == [])?,
  }
}

test pop_until_empty() fail {
  let v, _rest <- unsafe_pairs.expect_pop_until_and_then(
    [],
    equals_bytearray("a", _),
  )
  v >= 0
}

test pop_until_not_found() fail {
  let v, _rest <- unsafe_pairs.expect_pop_until_and_then(
    [Pair("b", 1), Pair("a", 2), Pair("c", 3)],
    equals_bytearray("aa", _),
  )
  v >= 0
}
