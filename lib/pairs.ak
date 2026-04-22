use list

/// Search a specific key in an associative list, and fail if not found.
pub fn has_key_or_fail(self: List<Pair<k, v>>, k: k) -> Bool {
  list.head(self).1st == k || has_key_or_fail(list.tail(self), k)
}

/// Drop elements from an associative list until a given key is encountered. Fails loudly otherwise.
/// Returns the value at that key, and the rest of the list.
pub fn pop_until(
  self: Pairs<ByteArray, v>,
  until: fn(ByteArray) -> Bool,
  return: fn(v, Pairs<ByteArray, v>) -> result,
) -> result {
  let head = list.head(self)
  if until(head.1st) {
    return(head.2nd, list.tail(self))
  } else {
    pop_until(list.tail(self), until, return)
  }
}
