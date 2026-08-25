# Reply to Paolo — PR #101 review (DRAFT, for Giovanni to review/send)

Hi Paolo,

Thank you — this is the most useful review the effort has had. You attacked the
evidence rather than the code, which is exactly what it needed, and several of
your rules are now load-bearing for us.

## The headline first: EXP-0 is answered

Your pre-flight question — "does `#prep_uplc` even terminate on the PLG?" — is
answered **yes, with shaping**. You reviewed at `02c7b86`; one commit later,
`ce515dc` (already pushed, in PR #101) preps the 2996-byte PLG **shaped** at
budget 4400 in ~2.3 s and discharges the first two PLG theorems:

- `t1_escape` (SMT-VALID): acceptance forces the output payment credential to be
  the PLB credential — the anti-escape / containment theorem on the compiled
  bytes, TransferAct T1 family;
- `t1_conservation` (SMT-VALID): with the output pinned to PLB, acceptance forces
  qOut ≥ qIn.

Both ship with a vacuity probe (negation Expected-Falsified at the same prep) and
kernel-checked concrete execs. Your memory-wall prediction was correct for the
*unshaped* path — our first PrepGlobal draft died exactly as you and Phil
described (20–35 GB territory; we killed it at 0.8 GB and restructured). Shaping
the T1 leaves into the prep function's arguments is the entire difference.

## What we adopted wholesale

- **R1–R6 as standing rules**, now binding across every tier (methodology §3a).
  R2b in particular — independence must be relational or witness-set, never an
  implication — is now the intellectual spine of the doc; the narrowing-mutant
  argument (a mutant accepting only the unit redeemer keeps the implication Valid
  while the bug is live) is quoted as the sharpest instance of the decoration
  failure mode.
- **Your #1 (V13, deployment/trust-root checker)**, **#2 (EXP-0c inventory gate —
  `DELIBERATELY_UNVERIFIED` array so a blueprint title with no flat fails RED)**,
  and **#5 (V20 axiom gates + optimizer named in the trust base + fuel/build-env
  as identity coordinates 4–5)** are all in flight in batch 1. Full batch plan is
  in our triage (`formal-verification/reviews/2026-08-12-paolino-pr101/TRIAGE.md`,
  Part D).

## What your review reframed for us

Your C5 ("all real safety is in the PLG, which has no theorem") is now partially
stale — the TransferAct branch has theorems. But the *gap statement* stands and we
now state it your way, per branch, as **"enforcing check at proof tier: NONE"**:
ThirdPartyAct = NONE (TESTED only), UnfrackingAct = NONE (TESTED only), registry
validators = NONE at proof tier. That table is in FORMAL_VERIFICATION_STATUS.md.

## The few we push back on

- **V17 (integer domain)** — N/A by form: the arithmetic is arbitrary-precision,
  so there is no domain to overflow. We keep S-7 (`assets.union` zero-preservation)
  as an Aiken-tier seed.
- **S-10** — accepted your own withdrawal: peek_first→full-scan is a liveness
  improvement, and the decoy it targeted is R3-unreachable.

## Two questions back

1. Given Blaster's convergence behavior on redeemer independence (C6/V6), do you
   favour the **witness-set** form or the **relational** `accepts(ctx,r₁)↔accepts(ctx,r₂)`
   form? Witness-set is cheaper and kernel-checked for us, but I'd value your read
   on which one the SMT layer handles more robustly at width.
2. Would you be willing to review the **deployment-manifest schema** for V13? It's
   the one class where the formal work actively cannot help (a wrong `prog_logic_cred`
   is a total break with every theorem still true), so the manifest checker is the
   only catch — and you named it #1.

Thanks again — genuinely.

— Giovanni
