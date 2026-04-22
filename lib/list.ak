use aiken/builtin.{head_list, tail_list}

/// A proxy to the builtin; gets erased by the compiler automatically, but reads better in code.
pub fn head(self: List<a>) -> a {
  head_list(self)
}

/// A proxy to the builtin; gets erased by the compiler automatically, but reads better in code.
pub fn tail(self: List<a>) -> List<a> {
  tail_list(self)
}

/// Check quickly if an element is an list; fails loudly otherwise.
pub fn has_or_fail(xs: List<a>, x: a) -> Bool {
  head(xs) == x || has_or_fail(tail(xs), x)
}

/// Drop n element from a list while enforcing that any dropped element satisfies
/// a given predicate. Fails loudly otherwise.
pub fn skip_assert_or_fail(
  self: List<a>,
  n: Int,
  assert: fn(a) -> Bool,
) -> List<a> {
  if n > 0 {
    expect assert(head(self))
    skip_assert_or_fail(tail(self), n - 1, assert)
  } else {
    self
  }
}
