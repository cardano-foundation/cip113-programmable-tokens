use unsafe_list

/// Search a specific key in an associative list, and fail if not found.
pub fn has_key_or_fail(self: List<Pair<k, v>>, k: k) -> Bool {
  unsafe_list.expect_head(self).1st == k || has_key_or_fail(
    unsafe_list.expect_tail(self),
    k,
  )
}

/// Drop elements from an associative list until a given key is encountered. Fails loudly otherwise.
/// Returns the value at that key, and the rest of the list.
pub fn expect_pop_until_and_then(
  self: Pairs<ByteArray, v>,
  until: fn(ByteArray) -> Bool,
  return: fn(v, Pairs<ByteArray, v>) -> result,
) -> result {
  let head = unsafe_list.expect_head(self)
  if until(head.1st) {
    return(head.2nd, unsafe_list.expect_tail(self))
  } else {
    expect_pop_until_and_then(unsafe_list.expect_tail(self), until, return)
  }
}
