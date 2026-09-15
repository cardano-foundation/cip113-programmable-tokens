use aiken/builtin.{head_list, tail_list}

/// `head_list`, aborting on an empty list — use it only where an empty list
/// must fail the script.
pub fn expect_head(self: List<a>) -> a {
  head_list(self)
}

/// `tail_list`, aborting on an empty list — use it only where an empty list
/// must fail the script.
pub fn expect_tail(self: List<a>) -> List<a> {
  tail_list(self)
}

/// Check whether an element is in a list: returns `True` if present,
/// otherwise ABORTS — never returns `False`.
pub fn has_or_fail(xs: List<a>, x: a) -> Bool {
  expect_head(xs) == x || has_or_fail(expect_tail(xs), x)
}

/// Drop n elements from a list while enforcing that any dropped element
/// satisfies a given predicate. A list shorter than `n` aborts; for `n <= 0`,
/// including a negative `n`, this is a no-op and the predicate runs zero
/// times.
pub fn skip_assert_or_fail(
  self: List<a>,
  n: Int,
  assert: fn(a) -> Bool,
) -> List<a> {
  if n > 0 {
    expect assert(expect_head(self))
    skip_assert_or_fail(expect_tail(self), n - 1, assert)
  } else {
    self
  }
}
