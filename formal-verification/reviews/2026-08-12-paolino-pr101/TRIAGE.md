# Triage — Paolo Veronelli review of PR #101 (formal-verification)

Triage performed 2026-08-12 against branch HEAD `ce515dc`. Paolo reviewed
at `02c7b86` — one commit earlier, WITHOUT `Cip113Spike/PropsGlobal.lean`
(the PLG T1 containment theorems `t1_escape` / `t1_conservation`, vacuity
probe, 3 kernel execs, SHAPED `#prep_uplc` at budget 4400). Every item
below was checked against actual source before acceptance, not taken from
his prose.

**Critical framing fact:** his EXP-0 pre-flight ("does `#prep_uplc`
terminate on the PLG?") is answered YES-with-shaping by `ce515dc`, and
his central premise "PLG has no theorem tier" is stale for the
TransferAct branch. Roughly a third of his plan reframes from
"gated/COULD-NOT-EVALUATE" to "the template now exists."

---

## PART A — The C-gaps (1-invariants-findings.md, C1–C14)

### C1 — Multi-input forwarding (PLB input count / own-ref independence)
**Claim:** every rung hardcodes one PLB input; "N PLB spends each forwarded" unproven at bytes.
**STATUS: PROOF-WORK (S).** Source-verified benign (PLB reads only `self.withdrawals`, ignores `_own_ref`/`_datum`), but unproven at bytes. Add a 2-PLB-input `native_decide` accepting witness (+ optionally a symbolic-inputs rung). Template: `PropsBase.lean` `exec_accepts`. No hazard (PLB, budget 600). Per R2b: implication-shaped "∀ inputs, accepts→forwarding" is vacuously satisfiable — must be a witness or relational statement.

### C2 — Uniqueness of the PLG entry
**STATUS: CHEAP-FIX (docs).** `has_key_or_fail` returns at first hit; ledger map keying makes duplicates unreachable; restrictive-only composition. One methodology sentence. Agree with his COVERED label.

### C3 — Withdrawal amount / zero not load-bearing
**STATUS: ALREADY-ADDRESSED (symbolic amounts in all rungs) + CHEAP-FIX:** one Aiken test that the PLG/unfracking `publish` arm accepts only `RegisterCredential` (locks the withdraw-0 liveness argument; answers the Conway self-deregistration question favourably). Overlaps V5.

### C4 — Non-ledger-encodable skeleton (treasury fields)
**STATUS: CHEAP-FIX (fixture, BOTH PropsBase and PropsGlobal).** Confirmed: both `mkCtx` and `mkT1` fill `txInfoCurrentTreasuryAmount`/`txInfoTreasuryDonation` with bare `Data.I 1`, outside the V3 `Maybe Lovelace` encoder image — strictly, no ledger-produced context is in any proven family. Change to `Data.Constr 1 []` in both files, re-discharge (expected identical; COULD-NOT-EVALUATE until run). Optional `validWithdrawals`-shaped ladder rung deferred.

### C5 — "All real safety is in PLG, which has no theorem"
**STATUS: PARTIALLY ALREADY-ADDRESSED by `ce515dc`** — `t1_escape` + `t1_conservation` are the first PLG theorems (TransferAct containment + conservation on the compiled 2996 B bytes). Premise stale. Remaining true: ThirdPartyAct + UnfrackingAct branches, registry theorems — mark those "enforcing check at proof tier: NONE" in the claims framing. His UnfrackingAct-arm suggestion → PROOF-WORK (M), see V1(c).

### C6 — Redeemer independence
**STATUS: PROOF-WORK (S), R2b-shaped.** PLB ignores `_redeemer` (source-confirmed) but every theorem concretizes it. Do NOT state as implication (vacuous under narrowing; seed S-22 would survive). Either relational `accepts(ctx,r₁)↔accepts(ctx,r₂)` or accepting witnesses at discriminating redeemer shapes. Witness-set form is cheaper, kernel-checked.

### C7 — Rejection "for the right reason" (¬Halt ambiguity)
**STATUS: CHEAP-FIX (twin-context comment near `exec_rejects_foreign_withdrawal`) + optional S:** re-run rejecting context at 10× fuel asserting same Error. His COVERED label agreed (twin-context argument carries PLB).

### C8 — Width 5+ and the fuel wall
**STATUS: DEFER (PROOF-WORK L, blocked on C10/C14).** `.prop` bakes fuel 600 → an accepting run needing >600 steps gives a vacuous Valid. Ladder to 5/8/16 must carry per-rung within-fuel accepting witnesses and raise prep budget with width; record genuine stops as COULD-NOT-EVALUATE.

### C9 — Mixed-credential withdrawal maps
**STATUS: PROOF-WORK (S; the twin is tiny).** Already on the status file's next-rungs list. The cheap high-value part: a rejecting `native_decide` twin whose only entry is `VerificationKeyCredential "PLG"` (same bytes, wrong tag) — pins tag-sensitivity, no SMT. = V5b, seed S-3.

### C10 — Rungs 2 and 4 lack non-vacuity witnesses + mutant control
**STATUS: PROOF-WORK (S) — high-value, cheap.** Add one `native_decide` accepting witness per rung with the param in the LAST slot (exercises full scan depth); add the 4-entry statement to `MutantControl.lean`; add one independently-seeded Lean-tier mutation. No new SMT.

### C11 — Non-spend invocations of the PLB unproven
**STATUS: PROOF-WORK (S, trivial — the single cheapest addition).** `else(_){fail}` confirmed. One `native_decide` rejecting run with `scriptContextScriptInfo := .RewardingScript …`. Note: blueprint `.else` handler carries byte-identical `compiledCode` to `.spend`, so the tracked flat exercises the else arm — no extra import (his settled v3 point). Seed S-2.

### C12 — `warn.sorry false` silences axiom disclosure; no axiom gate
**STATUS: CHEAP-FIX (harness) — guards the PR's own central claim.** Confirmed: file-wide `set_option warn.sorry false` in PropsBase.lean:34 and PropsGlobal.lean:54. Add `#guard_msgs` around each `#print axioms` (build fails on axiom drift, CI-enforced), drop/scope the file-wide option. Caveat V20/S-20b: `#guard_msgs` pins only NAMED declarations — an unpinned new theorem with `sorry` still compiles → also need an inventory rule/source gate. One methodology sentence: `blasterProven` inhabits every type (operational meaning only).

### C13 — `.prop` vs `.exec` linked only by unnamed optimizer trust
**STATUS: CHEAP-FIX (docs) + optional PROOF-WORK.** Confirmed: SMT ladder quantifies `.prop` (Blaster.Optimize.main output, noncomputable), kernel pair runs `.exec` (raw cekExecuteProgram); no connecting theorem; invisible to `#print axioms`. (i) Name the prep optimizer in methodology §7 trust base. (ii) Optional prop-side `#blaster` concrete controls mirroring the exec pair. = R5.

### C14 — Fuel is part of every claim; identity is a quadruple+
**STATUS: CHEAP-FIX (docs) + PROOF-WORK (S, tiny).** Confirmed budgets 600/4400; `isHaltB` accepts any `.Halt _` while CIP-117 requires unit. (i) Fuel + any-halt convention → MANIFEST/§7 as identity coordinates (R6). (ii) per-rung witnesses = C10. (iii) upgrade `exec_accepts` to assert halt value = `.VCon .Unit` via `fromHaltState` (confirm the v1.1.22 V3 wrapper returns unit first).

---

## PART B — Vulnerability classes (2-audit-coverage-plan.md)

### EXP-0 — prep termination on PLG/unfracking
**ALREADY-ADDRESSED by `ce515dc`** for PLG (shaped, 4400, ~2.3 s; exec reaches Halt kernel-checked). `unfracking` (1736 B) still open but smaller. **Relay to Paolo first.**

### EXP-0b — builtin dispatch under the pinned CEK (blake2b_224, less_than_bytearray)
**DEFER (COULD-NOT-EVALUATE, needs build).** One RegistryInit + one RegistryInsert concrete run; harness must report WHICH stop reason. Blocked on exercising the `registry_mint` flat.

### EXP-0c — extraction inventory is a silent subset
**CHEAP-FIX (harness, no build) — his #2 priority, highest coverage-per-effort.** `TITLES` has exactly 4 titles; `registry_spend`, `protocol_params_mint`, `issuance_mint` have no flat. Extend `--check`: blueprint title not in `TITLES` fails RED unless in an explicit `DELIBERATELY_UNVERIFIED` array with a reason. Falsification: add/remove a title → RED (seed S-12). = V16.

### V1 — Double satisfaction
(a) widths {1,2,4}: ALREADY-ADDRESSED. (b) input-count independence: PROOF-WORK (S) = C1, witness form. (c) PLG live-branch accounts for every PLB input: PROOF-WORK (M, now unblocked). Cheapest instance = **UnfrackingAct forwarding arm** (PLB-shaped `has_key_or_fail` against params field 2) — but that is **rung 2 of 3** (forwarding, not accounting); rung 3 = unfracking pairing/conservation is the real obligation. Template now: `PropsGlobal.lean`. Seed S-1 (compile-valid form only — PLB doesn't import `list`).

### V2 — Value preservation / leakage
**PARTIALLY ADDRESSED** (`t1_conservation`, T1 family). Remaining: multi-input/multi-policy conservation, ThirdPartyAct lovelace ratchet, unfracking strict equality. First target per Paolo: the `!dict.is_empty(input_tokens_at)` guard in `third_party.ak` (Finding 12; doubles as origin-node protection), seed S-5. SHAPED prep mandatory.

### V3 — Unauthorized mint / name control
Registry NFT shape: PROOF-WORK (M), gated EXP-0b, seed S-8. Issuance×PLG three-hop composition: DEFER (blocked on EXP-0c flat + rewarding builder), seeds S-13/14/15. **CHEAP-FIX: `transfer.ak:73–85` comment is STALE** (describes the pre-tightening `or{plg_invoked, validate_mint_outputs}`; code already has `or{plgl_delegates_for_own_registry_node, custody_ok}`) — fix before an external auditor chases it.

### V4 — Authorization / freeze / seize
**PROOF-WORK (M) — his elevated Tier B, ranks ABOVE V1(b).** `authorised_stake_cred` kernel. Single-input twins insufficient: a first-input-only auth bug passes all of them. Load-bearing context = **two PLB inputs, distinct owners, only one authorized** → clean bytes reject, mutant (auth-first-input-only) accepts. Both flavours (vkey+sig, script+withdrawal). Seed S-16. Plus two CHEAP-FIX disclosures: seizure destinations are "holder-unspendable, admin-recovery-only"; programmable tokens are issuer-mutable (seizing hook installable post-issuance).

### V5 — Purpose confusion
PROOF-WORK (S). PLB else-arm rejecting run = C11 (T0, cheapest). PLG/unfracking publish-arm accepts only RegisterCredential (+Aiken test per C3). registry_mint else reachable from existing flat. registry_spend blocked on EXP-0c. Adopt R1 localisation leg.

### V5b — Credential-tag confusion
PROOF-WORK (S) = C9; rejecting twin is T0 no-SMT. Seed S-3.

### V6 — Datum/redeemer validation
Redeemer rung = C6 (R2b form, seed S-22); malformed-redeemer PLG runs = T2. **Datum/ref-script continuity is enforced in ThirdPartyAct + unfracking but NOT TransferAct — interface obligation, documentation finding, not a bug.** One integration-guide paragraph.

### V6b — Data-layout contract (field indices)
PROOF-WORK (M, gated EXP-0). Concrete run per accessor over pairwise-distinguishable credential fields + R1 localisation leg (mutate accessor tail_list depth, prove flat changed, require flip). Seed S-19. Lean-tier upgrade of the golden tests.

### V7 — Replay / uniqueness / thread token
Ordering (`covering.key<key<covering.next` via less_than_bytearray): PROOF-WORK (S/M), friendliest SMT shape, seed S-9. **Sharp new catch:** registry_spend's insert arm authorizes on a tx-GLOBAL signal (node NFT minted >0) — one-witness-N-executions double-satisfaction; the stopper lives in registry_mint's `expect [covering_input]`, a cross-validator dependency neither validator's tests express. Seed **S-17**. registry_spend flat blocked on EXP-0c.

### V8 — Unbounded / DoS
DEFER = C8 ladder + CHEAP-FIX disclosures: `new_withdrawal_checker` O(policies×withdrawals) multi-party DoS; maxValueSize on fracked UTxOs (bench pin exists). R4 refinement: a Valid rung is a positive check owing seed S-26; only a timeout is NONE-by-form.

### V9 — Min-UTxO / ada / dust
PROOF-WORK (S, plausible early win). Reverse direction is the interesting one (the #96 hazard: does the validator make a legal ada amount unsatisfiable?). Relational ∀-lovelace rung (R2b, seed S-23) + monotone `ℓ_out≥ℓ_in` for the ThirdPartyAct ratchet. Re-proves the param-sensitivity doc at byte tier.

### V10 — Validity range / time
PROOF-WORK (S, T0 on PLB) — provable N/A. No validator reads `validity_range` (grep-confirmed). Symbolic range, RELATIONAL statement (S-24's bogus gate survives the implication form). Batch with V5/V5b.

### V11 — Reference-input / script trust
Mixed: (1) first-match params selection CLOSED (one-shot + always_fail). (2) **Decoy co-asset on the params output: construction invariant LIVE** — `protocol_params_mint` doesn't constrain extra assets; a lower-sorting co-asset permanently hides params from `peek_first`. This is T4 deployment-checker work (or one `expect` in protocol_params_mint). Seed S-10′. **Polarity (his v3): PLG rejecting the co-asset UTxO demonstrates the BRICK, is not safety — safety = the construction gate refuses to build it; gate-accepts-while-PLG-rejects ⇒ REFUTED (deployed dead).** (3) Decoy node: closed by registry_mint×registry_spend induction — but registry_spend is the least-verified thing in the repo. (4) Ref scripts on TransferAct outputs: open (=V6). **REJECT S-10 as withdrawn** (peek_first→full-scan mutant is a liveness improvement; killing decoy R3-unreachable).

### V12 — Datum-hash vs inline
PROOF-WORK (S, mostly closed at source). One rejecting run per read site, twin-paired (T2, batch with V11). Seed S-25.

### V13 — Deployment / trust-root closure — **HIS #1 PRIORITY, correct**
CHEAP-FIX / T4 (no build). The params datum forms a cycle nothing validates, write-once at an always-fail address → a pre-submission deployment-manifest checker is the ONLY opportunity to catch misconfiguration. A wrong `prog_logic_cred` = total break with all theorems still true — **the ∀-quantifier cannot see a wrong parameter**. Sharpening: theorems quantify `(.ScriptCredential param)` — constructor FIXED, only the 28 bytes quantified: honest statement is "∀ script-credential hash," not "∀ deployment"; nothing requires PLB's stake_cred to be Script. Closers: vkey-parameter `native_decide` demonstration + manifest assertion (constructor is Script) + shell+jq closure checker RED on any unclosed edge. **The one class where the formal work actively cannot help.**

### V14 — Substandard-hook aliasing
CHEAP-FIX (docs + conformance fixture). Two nodes can name the same hook; one withdrawal entry satisfies both; the core never binds the hook's redeemer to the node-set naming it. (`minting_logic_script` can't alias — policy = blake2b of it.) Normative sentence + fixture (aliased nodes, hook naming only A, tx touching A+B must reject unless hook proves B).

### V15 — Fracking / freeze collateral damage
CHEAP-FIX (disclosure). Unfracking rescue default-forbidden (`empty_vkey`) → mitigation opt-in by the hostile issuer. Attack bounded (contamination needs victim spend-auth). Residual = consolidation → wallet-UX obligation.

### V16 = EXP-0c. V17 — Integer domain: **REJECT (N/A by form)** — arbitrary-precision; keep S-7 (`assets.union` zero-preservation) as an Aiken-tier seed. V18 = R3 paragraph (CHEAP-FIX).

### V19 — Attacker-controlled positional indices
PROOF-WORK (M, gated EXP-0). Boundary fixtures for `outputs_start_idx` ∈ {0,1,len,len+1}: every output counted EXACTLY once. Seed S-18 (off-by-one in drop helper). Label honestly: KERNEL-PROVED-at-boundaries, not ESTABLISHED. Shares V2 fixtures.

### V20 — Claim-integrity gates — his #5, deliberately ahead of validator work
CHEAP-FIX (harness) = C12+C13+C14: axiom pin (`#guard_msgs`, seeds S-20a/S-20b) + optimizer trust named + fuel/build-env as identity coordinates 4-5. "A gate on the honesty of the evidence that has never been shown able to fail is the purest instance of the decoration failure mode."

---

## PART C — Standing rules R1–R6 (adopt verbatim into the methodology doc)

**R1 — twin-context rule + localisation leg.** `isHaltB … = false` cannot distinguish validator-logic rejection from decode failure / wrapper expect / refused builtin. Every rejecting run ships with an accepting twin in the same skeleton differing in exactly one field, or its outcome is COULD-NOT-EVALUATE. For load-bearing reasons: mutate only the intended guard, prove the flat's sha256 changed, require that run to flip — else report the weaker "this context is rejected," not "rejected by check X."

**R2 — no ∀-family without an inhabitant.** Every new symbolic family ships one `native_decide` accepting witness inside it, param in the LAST slot (exercises scan depth).

**R2b — independence cannot be an implication.** "∀ x, accepts→forwarding" does not state the validator ignores x: narrowing acceptance can never falsify an implication (mutant accepting only unit redeemer keeps the theorem Valid — the seeded bug survives its own control). State relationally `accepts(ctx,x₁)↔accepts(ctx,x₂)`, or by inhabitants per discriminating value.

**R3 — reachability cuts by polarity.** Over-approximated ESTABLISHED ∀-safety = strictly stronger, free — do not narrow for realism. A REFUTED counterexample needs a ledger-reachability check before it's a finding.

**R4 — every positive check ships a seeded violation it must catch.** An independence theorem's control is to INTRODUCE the dependence. Every check row names its seed or "NONE — caveat named."

**R5 — `.prop` and `.exec` are different objects.** `.exec` = raw cekExecuteProgram (computable); `.prop` = prep-optimizer output (noncomputable, what `blaster` quantifies). No theorem connects them; invisible to `#print axioms`. Name the optimizer in the trust base; add prop-side concrete controls.

**R6 — identity is five coordinates.** compiler, variant, **fuel** (600/4400 baked into `.exec`/`.prop`; acceptance formally = "halts within N steps"), **build environment** (`env/default.ak` vs `env/with_assertions.ak`), function/artifact. Record fuel next to each claim.

---

## PART D — Execution order

**Batch 1 — cheap, no lake build:**
1. EXP-0c/V16/S-12 — `DELIBERATELY_UNVERIFIED` in extract-flats.sh --check (his #2).
2. V13 deployment-manifest checker + vkey-param demonstration + params-value-shape assert (V11.2) (his #1).
3. V20 axiom gates + trust-base/MANIFEST coordinates (C12/C13/C14/R5/R6) (his #5). *(needs one lake build to verify guards)*
4. Docs: adopt R1–R6; C2/C7 notes; C4 fixture fix (both files); claims reframing (C5); disclosures (V4/V6/V8/V14/V15/V18); stale `transfer.ak` comment (V3).

**Batch 2 — cheap PLB Lean additions, one build:** C11 else-arm reject; C9 vkey-tag twin; C10 slot-2/4 witnesses + MutantControl 4-entry + independent mutation; C1 2-input witness; C6 redeemer witnesses; V10 relational range rung; C14(iii) unit-halt upgrade. Plus from the ce515dc review: `exec_rejects_no_transfer_logic` control + symbolic non-vacuity probe for `t1_conservation`.

**Batch 3 — proof work (PLG prep template now exists):** V4 two-owner auth (S-16, elevated) · V7 covering-input double-sat (S-17, elevated) · V1(c) UnfrackingAct forwarding rung (label as rung 2/3) · V7 ordering · V2 per-branch conservation · V19 boundaries · V9 ∀-lovelace · V11/V12 decoy+datum runs · V6b layout.

**Batch 4 — DEFER:** V8/C8 width ladder (after C14) · EXP-0b builtin probe · C4 ledger-shaped witness rung · V3 issuance×PLG composition.

---

## PART E — Where Paolo's review is stale or self-corrected

1. **EXP-0 answered YES (shaped) by `ce515dc`** — relay first; reframes ~⅓ of his plan.
2. **C5 "PLG has no theorem tier" stale** for TransferAct (escape + conservation now SMT-VALID).
3. **C4 treasury-field fix must touch `PropsGlobal.lean` too** (he couldn't see it).
4. **Already self-corrected in his v3 — do not re-litigate:** stale-custody-gap claim (withdrawn), S-10 (withdrawn), "permanently unspendable"→"holder-unspendable", "∀ deployment"→"∀ script-credential hash", per-handler-artifact objection (settled: byte-identical compiledCode).
5. **No outright source misreads found.** His S-1 compile hazard (PLB doesn't import `list`) is correct — use his compile-valid mutant form.
