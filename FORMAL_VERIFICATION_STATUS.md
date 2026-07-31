# Formal verification & test-hardening — status, blockers, next steps

Working file (local, like `CONTRACT_SURFACE_CHANGES.md`). Branch:
`test/blaster-tier0-properties`. Last update: 2026-07-31.

## Done

- **Tier-0 property suite** (`21a5535`): 15 Blaster-shaped properties —
  unfracking conservation/strip (7), ThirdPartyAct ratchet + conservation
  + escape (4), registry credential/ordering equivalences (4). Shaped to
  aiken PR #1311 capabilities: arity-1 tuple fuzzers, bounded domains,
  boolean-equivalence bodies where possible.
- **Ledger-realism layer** (`a75cd29`): `programmable_logic/ledger_shape`
  module (rules ported from wsc-poc `Builder.hs` [LEDGER-RULE]s + Phil's
  Lean LR-CTX audit), all canonical fixtures reshaped (positive fee,
  ledger withdrawal order = Script<VKey then bytewise, min-UTxO 2 ada
  floor incl. resolved/ref inputs, sorted outref sets via
  `with_sequential_outrefs`), `is_ledger_shaped` audit + negatives.
  Suite stayed green under reshaping ⇒ validators are withdrawal-order-
  and fee-insensitive.
- **TransferAct properties** (4): conservation ∀ quantities, shortfall
  rejection, burn/mint reconciliation ∀ amounts.
- **Registry insert-chain property**: inserted+updated node pair valid ∀
  ordered 28-byte key triples; node output valid ∀ lovelace (min-ada
  robustness).
- **Golden Data-layout tests** (6): RegistryNode 7-field order (minting
  logic at index 2!), params 3-field, PLG redeemer indices 0/1/2,
  registry proofs 0/1, unfracking redeemer, Credential encoding.
- **Param-sensitivity analysis**:
  `documentation/design/protocol-param-sensitivity.md` — no action
  bricks under any audited param change; #96 hazard class proven absent
  on every surface (ratchet/ada-free/any-lovelace props).
- Suite: **326/326**.

## Blockers

1. **Tier-1 (Lean/Blaster on our UPLC) toolchain**: needs Lean 4.24.0
   (elan) + Z3 **4.15.2 built from source** (newer Z3 regresses; see
   Lean-blaster README) — not installed here; ~GBs + a long build.
   Decision needed: local install vs container vs wait for the CBDE
   (Q4 2026). Also pick base: IOG upstream `main` vs Phil's
   Anastasia-Labs forks (PCB `cip153-value-builtins` @ `3fdd3fb`,
   Lean-blaster D6 @ `4d320dd`) — Aiken output probably decodes on stock
   PCB (we don't emit CIP-153 builtins), but the D6 tactic fix may still
   be needed; unverifiable until the toolchain exists.
2. **Full symbolic proofs don't scale yet** (upstream): Phil's unshaped
   P3 gets no verdict in 93 min; the shaped-contexts methodology is the
   only viable route today. Not our blocker to fix — but it bounds what
   Tier 1 can promise.
3. **Permission gate**: harness blocked self-granting broad permissions
   (correctly). Giovanni: if wanted, add allow-rules to
   `.claude/settings.local.json` manually for smoother long runs.

## Open questions

- **For Giovanni**: (a) publish `ledger_shape`/realism docs into
  `documentation/` proper or keep as code-side docs? (b) benches now run
  on reshaped fixtures — the stored benchmark baselines shift slightly;
  re-baseline when? (c) is the 2-ada test floor OK, or prefer the real
  size-based formula ((160 + |serialized|) × coinsPerUTxOByte)?
- **Conway cert rules**: can a third party deregister a script stake
  credential (slashing its registration and blocking withdraw-0 gated
  actions until re-registration)? Affects the stakeAddressDeposit risk
  note in the param-sensitivity doc. Needs a ledger-rules check
  (cardano-ledger Conway certs), not guesswork.
- **For Phil** (from the 2026-07-31 investigation):
  1. Upstreaming timeline for the three forks (PCB CIP-153 / Blaster D6
     / CLAB fixes) — build on forks or wait?
  2. Does stock PCB decode Aiken 1.1.x PlutusV3 output (term/builtin
     coverage)? What's the quickest smoke test?
  3. Would he take our Aiken validators as a second verification target
     (wsc-poc already benchmarks our harness side-by-side)? Is the
     `WSC/` layout meant to be reusable?
  4. His keystone P3 only closes with ≤2 withdrawal entries
     (`WdrlPairShaped`); our unfracking composition carries FOUR
     withdraw-0s — same `pdropList`-class cliff on our bytecode?
  5. Vacuity-probe tooling: automated or by hand?

## Next steps (in order)

1. Third-party **input-side** fuzzing (quantities, co-resident policies,
   input count) — needs a parametric variant of
   `validate_third_party_with_outputs`.
2. **Mutation-verification pass** (task #6): per property, mutate the
   guarded line, confirm exactly the matching test reddens, restore;
   record the matrix. Spot-checks DONE 2026-07-31:
   - `third_party.ak` ratchet `>=`→`>`: **18 tests redden** (unit
     baselines + `prop_third_party_lovelace_ratchet_accepts_any_topup`)
     — invariant heavily covered.
   - `unfracking.ak` conservation `==`→`tokens.contains`: **exactly 2
     redden** — `unfracking_fails_acted_surplus` +
     `prop_unfracking_rejects_any_fabrication_of_acted_tokens` — a
     surgical kill proving the fabrication guard is non-vacuous and
     uniquely owned by those tests.
   Remaining: transfer containment removal, strip-walk skip, registry
   28-byte checks, golden-layout reorder (needs a type-level mutation).
3. Registry insert **end-to-end** property through `registry_mint`
   (fuzz keys through the real Insert tx, not just the lib helpers).
4. **Benchmark-vs-ceiling CI pin** (from param doc): worst-case bench
   scenarios as % of mainnet maxTxExUnits.
5. **Tier-1 spike** once toolchain decision lands: export
   `plutus.json` compiledCode → `.flat`, `#import_uplc` smallest
   validator, restate one unfracking conservation prop as a Lean
   theorem, record where the CEK budget wall sits for our bytecode.
6. Unfracking **shape-shrinking** test (maxValueSize mitigation claim).
7. `aiken check --max-success 500` nightly job.
