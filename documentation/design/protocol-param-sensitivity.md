# Protocol-parameter sensitivity of the CIP-113 base validators

Status: analysis pass 2026-07-31 (part of the formal-verification /
test-realism track). Question answered: **if a relevant protocol
parameter changes — a little or a lot, up or down — which protocol
actions keep working, which get bricked, and which merely get more
expensive?**

Validators never *read* protocol parameters; sensitivity enters only
through the value shapes a validator **enforces** (equalities/ratchets
on ada or value size) meeting the shapes the ledger **requires**
(min-UTxO, size/budget ceilings). A conflict between the two is the
hazard class of audit issue #96 (a min-ADA rise made every ThirdPartyAct
on an existing UTxO unsatisfiable, because a per-pair ada *equality*
forbade the top-up). This document audits every action against that
class and its relatives.

## Per-parameter analysis

### `coinsPerUTxOByte` (min-UTxO floor) — the #96 class

Existing UTxOs are grandfathered (the rule applies to new outputs), so
the question is always: *can every continuing/new output absorb a higher
floor?* Audit result — *no action bricks*, each for a proven reason:

| Action | Ada constraint enforced | Rise (small or large) | Property locking it |
|---|---|---|---|
| TransferAct | none — the walk drops ada before comparing | holder tops up freely | walk is ada-free by construction (`assets.collect` drops ada) |
| ThirdPartyAct | per-pair ratchet `output >= input` | admin tops up; ratchet absorbs any rise | `prop_third_party_lovelace_ratchet_accepts_any_topup` |
| Unfracking | none — ada deliberately unread in pairs | free | module invariant (documented in `unfracking.ak`) |
| Registry init/insert/update | node value = ada (any amount) + NFT | top up at the action itself | `prop_registry_node_valid_for_any_lovelace` |
| Issuance mint | no lovelace constraint (audited 2026-07-31) | n/a | — |
| Protocol-params UTxO | minted once, locked; no lovelace constraint | grandfathered | — |

A **decrease** bricks nothing (floors only get easier) but has a
second-order effect: dust UTxOs become economical, which *amplifies
fracking* — more, smaller PLB UTxOs per holder. Unfracking (v2) is the
designed mitigation; the wallet-UX guidance (single-policy change
outputs) matters more in a low-floor regime, not less.

### `maxTxExUnits` / execution prices

A **decrease** in the ceiling is the live risk: multi-policy transfers
and the PLG coordinator run closest to the memory budget (see
`UPGRADABILITY_BENCHMARKS.md`; the Finding-15 multi-policy ThirdPartyAct
variant was rejected partly for crossing the mem budget). A large
decrease could make the *largest currently-valid* transfers
unbuildable — a liveness degradation, not a fund loss: holders split the
action into several smaller transactions (fewer policies/inputs each).
No validator invariant depends on the ceiling, so nothing bricks
permanently. Price (**cost-per-unit**) changes are purely economic.

Action item (open): pin the benchmark suite's worst-case scenarios as a
fraction of the mainnet ceiling in CI, so a proposed ceiling decrease
can be checked against real headroom in minutes.

### `maxValueSize` / `maxTxSize`

A **decrease** threatens *fracked* UTxOs: a UTxO whose value packs many
policies may exceed the new per-output value-size limit in any
transaction that recreates it. The escape hatch is exactly unfracking —
its paired continuing outputs carry the input's value *minus* the acted
policy (strictly smaller), and regrouped outputs are single-policy, so
an unfracking transaction is *shape-shrinking* and remains buildable
when a plain transfer of the whole UTxO is not. Candidate future test:
assert per-output policy count in unfracking outputs never exceeds the
input's.

### `minFeeA/B`, `minFeeRefScriptCostPerByte`

Purely economic; no validator reads the fee. Two notes: (a) reference
scripts are the deployment mode for PLG/PLB, so the ref-script fee
param scales every action's cost — large rises make third-party churn
(the R-03 no-op-respend concern) *more* self-limiting, not less; (b)
the test-realism floor (`ledger_shape.realistic_fee`) is deliberately a
constant, not a fee calculation — it only needs to be non-zero and
plausible.

### `stakeAddressDeposit`

All four withdraw-0 patterns (PLG, transfer logic, third-party logic,
unfracking + issuer hooks) require their script stake credential to be
**registered**. Deposit changes affect the one-time registration cost
only. The operational risk is *deregistration* (slashing the deposit
back): a deregistered credential makes every action gated on its
withdraw-0 fail phase-1 until re-registered at the new deposit rate.
Who may (re)register a script stake credential — and whether a hostile
deregistration is possible under Conway cert rules — is flagged as an
open question in `FORMAL_VERIFICATION_STATUS.md` rather than asserted
here.

### Governance-only params (`govActionDeposit`, `drepDeposit`, pool params)

No interaction with the validators. Explicitly out of scope.

## Method note

The robustness rows above are not just claims: where the invariant is
value-level, a property test quantifies it over the whole bounded
domain (top-ups 0..10⁹, any node lovelace 1..10¹²), so a future patch
that re-introduces an ada equality turns a test red immediately. That
is the intended division of labour — **parameters change at the ledger,
robustness is enforced in the test suite.**
