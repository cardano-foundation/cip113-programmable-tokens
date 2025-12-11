# Aiken Validator Optimization Analysis

## Current Status

Our Aiken validators are approximately **~20% less efficient** than the original Plutarch implementation in [input-output-hk/wsc-poc](https://github.com/input-output-hk/wsc-poc).

### Optimization Progress

| Optimization | Status | Size Impact |
|--------------|--------|-------------|
| Dead code removal | ✅ Done | -52 chars |
| Remove pre-computed invoked_scripts | ✅ Done | -38 chars |
| Direct withdrawal checking | ✅ Done | (included above) |
| UPLC builtin experiments | ❌ Reverted | Made code larger |

**Current validator sizes:**
- `programmable_logic_global`: 6196 chars (from original 6286, **-1.4%**)
- `registry_mint`: 4404 chars
- `blacklist_mint`: 3894 chars
- `freeze_and_seize_transfer`: 2242 chars

## Key Differences Identified

### 1. List Operations

**Plutarch (efficient):**
```haskell
-- Uses pelemAtFast which directly indexes into PBuiltinList
pelemAtFast @PBuiltinList # refInputs
```

**Aiken (current):**
```aiken
-- Uses list.drop which traverses the list
fn elem_at(lst: List<a>, idx: Int) -> a {
  when list.drop(lst, idx) is {
    [elem, ..] -> elem
    [] -> fail @"Index out of bounds"
  }
}
```

**Optimization:** Aiken's `builtin.index_bytearray` won't work for lists. Consider restructuring to avoid repeated indexing or use continuation-passing style like Plutarch's `plet` pattern.

### 2. Value Accumulation

**Plutarch (efficient):**
```haskell
-- Uses pfix for efficient fixed-point recursion with plet for memoization
go = pfix #$ plam $ \self proofs inputInnerValue actualProgrammableTokenValue ->
  -- Direct manipulation of PValue internals
```

**Aiken (current):**
```aiken
-- Multiple nested iterations through value structures
fn check_transfer_and_compute_prog_value(...) -> Value {
  -- Uses assets.merge which may rebuild the entire value
}
```

**Optimization:** Use `assets.add` directly instead of `merge` where possible. The current implementation already does this in `do_check_transfer`.

### 3. Script Hash Comparisons

**Plutarch (efficient):**
```haskell
-- Uses punsafeCoerce to treat credentials as raw bytearrays
punsafeCoerce @(PAsData PByteString) $ phead #$ psndBuiltin #$ pasConstr # ownerCred
```

**Aiken (current):**
```aiken
-- Pattern matching on Credential variant
when stake_cred is {
  VerificationKey(pkh) -> ...
  Script(_hash) -> ...
}
```

**Optimization:** Pattern matching is clean but adds overhead. Consider using raw bytearray comparison where possible.

### 4. List Filtering vs Direct Fold

**Plutarch (efficient):**
```haskell
-- Single pass through inputs with plet memoization
pvalueFromCred = phoistAcyclic $ plam $ \cred sigs scripts inputs ->
  (pfix #$ plam $ \self acc ->
    pelimList (\txIn xs -> ...) acc
  )
```

**Aiken (current):**
```aiken
-- Multiple passes: filter then iterate
let prog_cred_inputs = list.filter(tx.inputs, ...)
list.map(prog_cred_inputs, ...)
```

**Optimization:** Combine filter + map into a single fold where possible.

### 5. Dict Operations

**Plutarch:**
```haskell
-- Direct access to PBuiltinList internals
pto (pto totalValue)  -- Unwraps value to inner list representation
```

**Aiken:**
```aiken
-- Uses high-level dict operations
assets.to_dict(value) |> dict.to_pairs
```

**Optimization:** Aiken's `assets` module is well-optimized, but repeated conversions should be avoided.

## Specific Optimizations to Implement

### 1. Optimize `get_signed_prog_value` (HIGH IMPACT)

Current:
```aiken
fn get_signed_prog_value(tx: Transaction, prog_logic_cred: Credential) -> Value {
  list.foldl(tx.inputs, assets.zero, fn(input, acc) {
    if input.output.address.payment_credential == prog_logic_cred {
      // ... authorization checks ...
      merge(acc, input.output.value)  // Expensive merge
    } else { acc }
  })
}
```

Optimized:
```aiken
fn get_signed_prog_value(tx: Transaction, prog_logic_cred: Credential) -> Value {
  list.foldl(tx.inputs, assets.zero, fn(input, acc) {
    if input.output.address.payment_credential == prog_logic_cred {
      expect Some(Inline(stake_cred)) = input.output.address.stake_credential
      let authorized = when stake_cred is {
        VerificationKey(pkh) -> is_signed_by(tx, pkh)
        Script(_hash) -> is_script_invoked(tx, stake_cred)
      }
      expect authorized  // Fail if not authorized
      // Use assets.merge only once per input
      assets.merge(acc, input.output.value)
    } else { acc }
  })
}
```

### 2. Optimize `elem_at` usage (MEDIUM IMPACT)

Instead of repeated `elem_at` calls, use indexed folding where possible.

### 3. Reduce trace statements in production (LOW IMPACT)

Already handled by `--trace-level silent` (default in Aiken build).

### 4. Use `expect` vs `if-then-fail` (LOW IMPACT)

`expect` compiles to slightly more efficient code than explicit if-then-fail patterns.

## Benchmarking Approach

To measure improvements:

1. Use `aiken check` to run tests with execution unit tracking
2. Compare memory and CPU usage in test output
3. Deploy to testnet and measure actual transaction costs

## Implementation Priority

1. **Combine filter+map operations** - Easy wins in multiple validators
2. **Optimize value accumulation** - Major impact in `programmable_logic_global`
3. **Reduce list traversals** - Pass data through single iterations
4. **Use builtin operations** - Where Aiken exposes them

## Plutarch Techniques We Cannot Easily Replicate

1. **`phoistAcyclic`** - Plutarch's term-level hoisting for code reuse
2. **`plet` memoization** - Explicit let-binding at UPLC level
3. **`punsafeCoerce`** - Zero-cost type coercion
4. **`pfix` fixed-point** - Efficient recursion pattern

Aiken handles some of these implicitly through its compiler, but the explicit control in Plutarch can yield better results for complex validators.

## Conclusion

The ~20% efficiency gap is expected when comparing:
- Plutarch: Low-level DSL with explicit UPLC control
- Aiken: High-level language with abstraction overhead

To close the gap:
1. Apply the optimizations above
2. Profile specific hot paths
3. Consider restructuring algorithms to match Plutarch patterns
