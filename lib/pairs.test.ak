use aiken/builtin.{equals_bytearray}
use pairs

// ------------------------------------------------------------- has_key_or_fail

test has_key_or_fail_matrix() {
  and {
    pairs.has_key_or_fail([Pair("a", 1)], "a")?,
    pairs.has_key_or_fail([Pair("a", 1), Pair("b", 2)], "a")?,
    pairs.has_key_or_fail([Pair("a", 1), Pair("b", 2)], "b")?,
    pairs.has_key_or_fail([Pair("b", 2), Pair("a", 1), Pair("c", 3)], "a")?,
    pairs.has_key_or_fail([Pair("b", 2), Pair("a", 1), Pair("c", 3)], "b")?,
    pairs.has_key_or_fail([Pair("b", 2), Pair("a", 1), Pair("c", 3)], "c")?,
  }
}

test has_key_or_fail_empty() fail {
  pairs.has_key_or_fail([], "a")
}

test has_key_or_fail_not_in_list_1() fail {
  pairs.has_key_or_fail([Pair("a", 1)], "b")
}

test has_key_or_fail_not_in_list_2() fail {
  pairs.has_key_or_fail([Pair("a", 1), Pair("b", 2)], "")
}

test has_key_or_fail_not_in_list_3() fail {
  pairs.has_key_or_fail([Pair("b", 2), Pair("a", 1), Pair("c", 3)], "aa")
}

// ------------------------------------------------------------------- pop_until

test pop_until_first_and_only() {
  let v, rest <- pairs.pop_until([Pair("a", 1)], equals_bytearray("a", _))
  and {
    (v == 1)?,
    (rest == [])?,
  }
}

test pop_until_first_and_rest() {
  let
    v,
    rest,
  <- pairs.pop_until([Pair("a", 1), Pair("b", 2)], equals_bytearray("a", _))
  and {
    (v == 1)?,
    (rest == [Pair("b", 2)])?,
  }
}

test pop_until_middle() {
  let
    v,
    rest,
  <-
    pairs.pop_until(
      [Pair("b", 1), Pair("a", 2), Pair("c", 3)],
      equals_bytearray("a", _),
    )
  and {
    (v == 2)?,
    (rest == [Pair("c", 3)])?,
  }
}

test pop_until_last() {
  let
    v,
    rest,
  <-
    pairs.pop_until(
      [Pair("b", 1), Pair("a", 2), Pair("c", 3)],
      equals_bytearray("c", _),
    )
  and {
    (v == 3)?,
    (rest == [])?,
  }
}

test pop_until_empty() fail {
  let v, _rest <- pairs.pop_until([], equals_bytearray("a", _))
  v >= 0
}

test pop_until_not_found() fail {
  let
    v,
    _rest,
  <-
    pairs.pop_until(
      [Pair("b", 1), Pair("a", 2), Pair("c", 3)],
      equals_bytearray("aa", _),
    )
  v >= 0
}
