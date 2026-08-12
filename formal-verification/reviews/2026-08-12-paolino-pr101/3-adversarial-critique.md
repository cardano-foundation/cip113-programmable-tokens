# Independent adversarial critique of `audit-coverage-plan.md`

Target: first draft (`AUDIT v1`, 969 lines), pinned sources at
`02c7b86397f7660c8f479b20cc544a099269a7d5`. Plan/critique only; no build or
code was run or written.

## ROUND 1 — first-draft attack

### What is already strong

- The plan correctly refuses to turn PLB forwarding into “the token is safe.”
  V13 deployment closure, V16 inventory completeness, R2 family inhabitants,
  and R3's asymmetric treatment of ledger-overapproximating counterexamples are
  valuable additions.
- V14 hook aliasing is a good CIP-113-specific double-satisfaction catch, and
  the plan is appropriately candid that it is an interface obligation rather
  than a theorem over the four tracked artifacts.
- The matrix/cost split is usable. In particular, EXP-0 makes tool reach a
  measured boundary rather than silently treating timeout as safety evidence.

### Load-bearing holes

1. **V3 / EXP-0c / Tier A** · The plan calls `issuance_mint` an
   “acknowledged open custody gap,” while §11.7 admits that the file was not
   read. At the pinned commit, the current `issuance_mint.ak` has
   `plgl_delegates_for_own_registry_node`, denies `UnfrackingAct` delegation,
   and falls back to `custody_ok`; its own comment says it closes Finding 04.
   The stale warning in `transfer.ak` conflicts with the current implementation
   and cannot establish a live bug. · **Seed:** replace the precise same-node
   predicate with “any PLG redeemer exists,” then require a mint for node A to
   a non-PLB output while PLG names node B to be rejected. · **Severity:
   load-bearing.** Keep the missing-flat coverage finding; withdraw the code-gap
   claim unless a current counterexample is supplied.

2. **V11 / protocol-params trust root** · The plan says the lower-sorting-asset
   question “depends entirely on `protocol_params_mint`'s spend side.” There is
   no live spend side: the pinned mint policy sends the unique NFT to the
   parameterised `always_fail` address. The real residual is creation/deployment
   shape: `protocol_params_mint` fully decodes the datum and strictly checks its
   own NFT, but does not visibly forbid unrelated assets in that output;
   `get_protocol_params_ref` later requires the params policy to be
   `peek_first`. · **Seed:** create the params output with an otherwise valid NFT
   plus a lower-sorting non-ada policy and require either the mint/deployment
   gate to reject it or the deployment checker to name the permanent-liveness
   hazard. · **Severity: load-bearing.** Reframe from mutable-reference attack to
   immutable trust-root construction invariant.

3. **V1(c) / Priority A #4** · The proposed
   `PLG_accepts(UnfrackingAct) -> unfracking_cred in withdrawals` theorem proves
   only a second forwarding hop. It does not prove V1(c), “every PLB input is
   constrained,” and therefore does not close double satisfaction. The chain is
   three distinct claims: PLB→PLG presence; PLG/UnfrackingAct→unfracking
   presence; unfracking acceptance→every PLB input is paired, single-owner, and
   conserved. · **Seed:** delete/relax PLG's UnfrackingAct gate and show the
   second theorem reds; independently mutate unfracking to stop its input walk
   after the first PLB input and require a two-input family to red. ·
   **Severity: load-bearing.** Label the proposed theorem a forwarding rung, not
   the second link completed.

4. **V5 purpose checks** · `plutus.json` has separate titles for `.spend`,
   `.withdraw`, `.publish`, and `.else`; the manifest imports only
   `programmable_logic_base....spend`, PLG/unfracking `.withdraw`, and
   `registry_mint....mint`. Changing `scriptContextScriptInfo` against a
   handler-specific flat can establish purpose-mismatch rejection by that
   artifact, but it does not execute the separately compiled `.else` artifact.
   The withdraw flats likewise cannot establish the `.publish` behaviour.
   · **Seed:** mutate the source `.else`/`.publish` arm and require the exact
   artifact under the claimed check to change and the corresponding run to
   flip; an unchanged tracked flat proves the check targeted the wrong bytes. ·
   **Severity: load-bearing** for the publish/deregistration claim,
   **worth-covering** for PLB mismatch rejection. Import the extra blueprint
   titles or narrow the prose.

5. **R1 twin-context rule** · An accepting twin proves the shared skeleton can
   decode. It does not locate the rejecting twin's failure after the one changed
   field; that field can itself trigger wrapper decode, purpose dispatch, or an
   earlier `expect` before the guard being credited. R1 currently upgrades the
   pair to ESTABLISHED “for the right reason” too readily. · **Control:** mutate
   only the intended guard, prove the selected flat changed, and require the
   rejecting run to flip; otherwise require a trace/error-site discriminator or
   report only “this input is rejected,” not why. · **Severity: load-bearing
   methodology.**

6. **R4 / §8 control completeness** · “Every positive check above ships with a
   seeded violation” is false as written. There is no specific mapped seed for
   TransferAct or ThirdPartyAct conservation, multi-input owner authorisation,
   V6b field selection, V9 lovelace invariance/monotonicity, V10 range
   independence, or V12 inline/hash handling. S6 covers only unfracking; S4/S5
   cover only two ThirdParty guards. · **Control:** add a matrix control column
   with a one-to-one check→seed mapping; mark `NONE — caveat named` where absent,
   as R4 itself promises. · **Severity: load-bearing.**

7. **V13 parameter quantification** · The ladder does not quantify over every
   `Credential` parameter. Each theorem applies
   `(.ScriptCredential param)` and quantifies only the inner bytes. A deployment
   parameterised by `VerificationKey h` is outside the theorem family, not a
   deployment about which the theorem remains true. · **Seed:** the proposed
   vkey-parameter accepting run is good; add a manifest assertion that the
   applied PLB parameter constructor is `Script`, and correct every “all
   parameterisations” claim to “all script-credential hashes.” · **Severity:
   load-bearing scope.**

8. **V4 authorisation family** · Four one-input accept/reject twins do not test
   the double-satisfaction case: two PLB inputs with distinct owners and only
   one owner authorisation. A first-input-only bug passes all four. ·
   **Independent seed:** alter `collect_input_assets` so only the first PLB
   input calls `authorised_stake_cred`, while later PLB inputs are still
   accumulated. The two-owner, one-signature context must reject clean bytes and
   accept the mutant. Repeat for script-owner withdrawals. · **Severity:
   load-bearing.** This ranks above PLB input-count independence because it
   tests the downstream obligation users rely on.

9. **V7 omits registry double satisfaction** · `registry_spend`'s insert arm is
   satisfied by the transaction-global positive registry mint. Its safety
   depends critically on `registry_mint` requiring exactly one registry-NFT
   covering input. The ordering theorem does not test one mint witness reused by
   multiple spend executions. · **Independent seed:** relax
   `expect [covering_input] = filter(...)` to select the first covering input;
   construct an insert that also consumes a second authentic registry node.
   Both spend handlers can see the same mint, so the extra node must still be
   rejected by the system-level fixture/control. · **Severity: load-bearing.**

10. **Missing class: attacker-controlled positional indices** ·
    `registry_node_idx`, `outputs_start_idx`, and TransferAct proof order are
    security-bearing redeemer pointers. The plan discusses malformed redeemers
    but not negative/out-of-range indices, duplicate node indices, boundary
    output partitions, or whether an output can be counted both as prefix value
    and as a paired continuation after an off-by-one error. · **Independent
    seeds:** mutate `n - 1` to `n - 2` in a drop helper, or omit one
    `list.tail(outputs)` in the pair walk; boundary fixtures at 0, 1, list
    length, and length+1 must expose reuse/omission. · **Severity:
    worth-covering, load-bearing for value accounting.** Add an explicit matrix
    row rather than hiding this under generic datum/redeemer validation.

11. **V6b Data-layout runs** · Pairwise-distinguishable fields do not by
    themselves prove which accessor was read: a run may accept without reaching
    the accessor or because another credential is also present. · **Seed:** swap
    the accessor's `tail_list` depth to the adjacent field and require an
    accept/reject pair with exactly the expected credential present to flip.
    Also prove the branch reaches that accessor. · **Severity: worth-covering.**

12. **S-10 is not a valid security falsifier yet** · Replacing `peek_first`
    with a full policy scan is more permissive, but possession of the unique
    params/node policy is the authenticity signal. On ledger-reachable state,
    the change may be a liveness improvement rather than a vulnerability; the
    proposed forged-policy decoy is unreachable by R3. · **Replacement:** use
    the protocol-params creation seed in item 2, or exhibit an authentic
    policy-bearing UTxO admitted by the scan that violates the mint/spend
    induction. · **Severity: worth-covering.** A mutation kill on an unreachable
    context must not be sold as security sensitivity.

13. **V4 seizure destination wording** · A no-stake/pointer-stake PLB output is
    unusable by holder TransferAct/unfracking, but “permanently unspendable” is
    too broad: ThirdPartyAct deliberately bypasses holder authorisation and can
    potentially move it again. · **Check:** state “holder-unspendable / admin
    recovery only” unless a fixture shows every branch rejects. · **Severity:
    minor scope correction.**

14. **Companion drift after the plan's read** · `invariants-findings.md` now has
    C12–C14: no mechanical axiom-set gate under file-wide `warn.sorry false`,
    unnamed `.prop` optimizer trust versus `.exec`, and fuel 600 as a claim
    coordinate/vacuity boundary. The plan still says C1–C11 partition the work
    and proposes wider rungs without integrating these. · **Controls:** axiom-set
    pin; prop-side accepting/rejecting controls; per-rung within-fuel witnesses
    with fuel recorded in identity. · **Severity: load-bearing methodology.**

### Priority disagreement

Keep V13 first. Replace the current #2 rationale (“one omitted validator carries
an open issuance gap”) with verified-inventory completeness *without* asserting
that stale gap. My next two are (a) the complete PLB→PLG→unfracking accounting
chain plus the two-owner TransferAct control, and (b) registry exact-covering-input
double satisfaction. EXP-0 remains the practical feasibility gate, but it is an
experiment, not itself a vulnerability class or assurance result.

## ROUND 2 — v3 re-audit

### Confirmed fixes and one accepted rebuttal

- **Resolved:** V3 no longer reports the stale `transfer.ak` comment as a
  current custody bug; the replacement three-hop issuance×PLG invariant and
  S-13/S-14/S-15 are materially stronger.
- **Resolved:** V11 now finds the deployment-time extra-asset hazard;
  V13 checks output value shape and script-credential construction.
- **Resolved:** V1(c) is explicitly a three-rung chain; the cheap PLG theorem
  no longer closes downstream accounting.
- **Resolved:** R1 now separates “rejects” from “rejects at guard X”; V4 has the
  two-owner control; V6b has a discriminating/localised control; V7 has the
  exact-covering-input double-satisfaction seed; V19 covers positional indices;
  V20/R5/R6 integrate companion C12–C14.
- **Rebuttal accepted:** the blueprint evidence shows each validator's handler
  titles carry byte-identical `compiledCode`. The tracked flat can reach purpose
  dispatch, `.publish`, and `.else`; no extra handler flat is required. Keeping
  the artifact-changed localisation leg is still correct.

### Residuals to settle

1. **R4's remaining `NONE`s** · Four are presented as if no natural mutation
   exists, but each has a direct falsifier. V1(b): add an erroneous
   exactly-one-input guard; the two-input accepting witness must red. V6: change
   ignored redeemer to require unit; the symbolic-redeemer rung must red. V9
   invariance: add equality on the allegedly free lovelace field; the
   invariance theorem must red. V10: add a bogus upper-bound/range gate; range
   independence must red. V12's inline/hash seed is already described. ·
   **Severity: load-bearing falsification duty.** “Nothing reads the field” is
   exactly why adding a bad read is the right negative control, not why no
   control exists.

2. **V20 axiom gate** · `#guard_msgs`/`#print axioms` pins only declarations
   named by a guard. A newly added, unpinned theorem containing `sorry` can
   still compile; restoring `warn.sorry` emits a warning but does not by itself
   make `lake build` fail. S-20's phrase “insert a `sorry`” is therefore too
   broad. · **Seed/criterion:** replace the proof of an existing *pinned*
   theorem with `sorry` and require the guard to red; separately enforce an
   inventory rule that every published claim has a pinned expected axiom set
   (or a no-human-`sorry` source/CI gate). Add a new unpinned theorem with
   `sorry` as the inventory seed. · **Severity: load-bearing claim integrity.**

3. **V11 check polarity** · Three “decoy runs” are grouped under
   `ESTABLISHED per decoy run`, but the lower-sorting co-asset context is
   ledger-reachable at params creation and PLG's expected rejection
   *demonstrates the permanent brick*; it does not establish safety. The safe
   gate is `protocol_params_mint` or the deployment checker rejecting that
   construction. · **Criterion:** clean deployment accepted; same deployment
   plus lower-sorting policy rejected by the pre-submission gate. If PLG later
   rejects the constructed params UTxO while the construction gate accepts it,
   mark the safety property REFUTED, not ESTABLISHED. · **Severity:
   load-bearing pass/fail inversion.**

4. **V3 method classification** · The issuance×PLG invariant is described as
   “not statable today” and matrix method `X`, immediately after explaining how
   both imported artifacts can execute against one shared context. Missing flat
   and builder make it **COULD-NOT-EVALUATE today**, not out of scope for
   on-chain proof. · **Check:** classify it as cross-artifact K first, S if a
   shaped relational theorem scales; its pass requires both validators to halt
   on the same ledger-shaped context and the negative seeds to flip the
   appropriate conjunction. · **Severity: worth-covering scope/cost.**

5. **V19 quantifier inflation** · The property says “for all
   `outputs_start_idx` and all arrangements,” while four K boundary fixtures
   establish only four executions. Those are excellent controls, not a
   universal partition theorem. · **Criterion:** label K results
   KERNEL-PROVED-at-boundaries/TESTED family; reserve ESTABLISHED for an S
   theorem over the shaped list family (with an inhabitant and S-18). ·
   **Severity: worth-covering scope.**

6. **V14 hook input claim** · “A hook receives no redeemer field telling it
   which policy” is too strong. A withdrawal validator receives its own
   redeemer and a substandard may require policy identifiers there. The core
   does not bind that redeemer to every registry node naming the shared hook;
   that is the actual gap. · **Conformance seed:** two aliased nodes, a hook
   redeemer naming only policy A, and a transaction touching A+B must reject
   unless the hook proves coverage of B too. · **Severity: worth-covering,
   load-bearing interface wording.**

7. **S-1 viability** · The proposed one-line PLB mutant calls `list.head` but
   `programmable_logic_base.ak` does not import `list`; a compile failure is not
   a killed security seed. · **Fix:** make the sealed patch include its import
   (and require mutant build success before any kill is counted), or choose a
   compile-valid first-entry extraction. · **Severity: minor but mechanical.**

8. **Internal consistency after the large revision** · The front matter still
   says C1–C11 and “four standing rules”; there are now C1–C14 and six rules.
   The cost table still says “12 seeds” although the list reaches S-20, and the
   matrix V11 still says params uniqueness+immutability are simply “closed”
   without the live construction invariant. · **Control:** a final
   matrix↔detail↔cost reconciliation pass. · **Severity: worth-covering** because
   teams will cost from the matrix, not from the revision history.

### Priority after v3

V13 remains first. V4's two-owner control and V7's covering-input control now
deserve the elevated Tier-B position they received. V20 should move ahead of
the cheap PLB width/range work once its gate is made complete: otherwise future
green claims can silently acquire an unapproved axiom before the higher-value
validator work even starts.

### ROUND 2 addendum — v4 final verification

The eight v3 residuals are genuinely integrated. Two last control definitions
still need tightening before the plan's falsification table is internally sound:

1. **S-22 can pass on the seeded bug** · If V6's “symbolic-redeemer rung” keeps
   the current implication shape (`acceptance -> forwarding`), mutating PLB to
   accept only the unit redeemer does **not** falsify it; it merely narrows the
   antecedent and makes non-unit cases vacuous. · **Required statement:** a
   relational independence theorem (`accepts(ctx,r1) ↔ accepts(ctx,r2)`) or an
   accepting witness for each discriminating redeemer shape, then S-22 must
   break equivalence/acceptance. · **Severity: load-bearing vacuity.**

2. **V8 is not `NONE by form` when a rung succeeds** · A timeout is indeed a
   measurement needing no seed. A width-5/8/16 theorem that returns Valid is a
   positive safety check and must be shown able to fail. · **Control:** add that
   exact width's statement to the existing always-accept mutant (plus a
   last-slot accepting witness at adequate fuel) and require Falsified. ·
   **Severity: load-bearing falsification duty.** Distinguish “timeout result”
   from “successful rung” in the mapping.

Two mechanical reconciliation nits remain: §10 says 21 active seeds, but the
active list is 26 (S-1…S-9, S-10′, S-11…S-19, S-20a/b, S-21…S-25); and the claim
that `falsification-control.sh` is unchanged for every seed is too broad for
cross-validator/multi-artifact seeds unless the separate sealed-seed runner is
named and costed. These are **minor/worth-covering**, respectively.

### Final verification — v5

Confirmed integrated: R2b requires relational/witness-based independence and
therefore makes S-21–S-24 capable of seeing acceptance narrowing; V8 now splits
timeout (measurement, no seed) from Valid (positive claim, S-26 plus a
within-fuel witness); the plan counts 27 active seeds and separately costs the
six multi-artifact/deployment controls. The plan is stable. No further
load-bearing adversarial objection remains from these two rounds.
