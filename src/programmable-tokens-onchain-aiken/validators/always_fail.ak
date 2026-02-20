// Always-fail validator parameterized by a nonce.
// Used to permanently lock the IssuanceCborHex NFT so it can never be spent.
// The nonce parameter ensures each deployment produces a unique script hash.

validator always_fail(_nonce: ByteArray) {
  spend(_d, _r, _oref, _tx) {
    fail
  }

  else(_) {
    fail
  }
}
