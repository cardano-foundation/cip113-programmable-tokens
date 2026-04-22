use list.{has_or_fail, skip_assert_or_fail}

// ----------------------------------------------------------------- has_or_fail

test has_or_fail_matrix() {
  let vkh1 = #"aabbccdd"
  let vkh2 = #"ddeeff00"
  let vkh3 = #"11223344"
  and {
    has_or_fail([vkh1], vkh1)?,
    has_or_fail([vkh1, vkh2], vkh2)?,
    has_or_fail([vkh1, vkh2, vkh3], vkh2)?,
  }
}

test has_or_fail_empty() fail {
  let vkh1 = #"aabbccdd"
  has_or_fail([], vkh1)
}

test has_or_fail_absent() fail {
  let vkh1 = #"aabbccdd"
  let vkh2 = #"ddeeff00"
  has_or_fail([vkh1], vkh2)
}

// --------------------------------------------------------- skip_assert_or_fail

fn is_non_negative(n) {
  n >= 0
}

test skip_assert_or_fail_matrix() {
  and {
    (skip_assert_or_fail([0, 1, 2, 3], -1, is_non_negative) == [0, 1, 2, 3])?,
    (skip_assert_or_fail([0, 1, 2, 3], 0, is_non_negative) == [0, 1, 2, 3])?,
    (skip_assert_or_fail([0, 1, 2, 3], 1, is_non_negative) == [1, 2, 3])?,
    (skip_assert_or_fail([0, 1, 2, 3], 2, is_non_negative) == [2, 3])?,
    (skip_assert_or_fail([0, 1, 2, 3], 3, is_non_negative) == [3])?,
    (skip_assert_or_fail([0, 1, 2, 3], 4, is_non_negative) == [])?,
    (skip_assert_or_fail([0, 1, -2, -3], 2, is_non_negative) == [-2, -3])?,
  }
}

test skip_assert_or_fail_out_of_bound() fail {
  skip_assert_or_fail([0, 1, 2, 3], 5, is_non_negative) == []
}

test skip_assert_or_fail_empty_list() fail {
  skip_assert_or_fail([], 1, is_non_negative) == []
}

test skip_assert_or_fail_assert_fail_first() fail {
  skip_assert_or_fail([-1, 2, 3], 1, is_non_negative) == [2, 3]
}

test skip_assert_or_fail_assert_fail_last() fail {
  skip_assert_or_fail([1, 2, -3], 3, is_non_negative) == []
}

test skip_assert_or_fail_assert_fail_middle() fail {
  skip_assert_or_fail([1, -2, 3], 3, is_non_negative) == []
}
