#!/usr/bin/env bash
# Regenerate flats/ + flats/MANIFEST.md from the CIP-113 blueprint — the
# non-Nix staleness guard (pattern: cardano-mpfs-onchain PR #51
# scripts/extract-blaster-uplc.sh, hardened per the identity-triple
# discipline in paolino's aiken-blaster-verification skill).
#
# `jq -er` makes a renamed or missing validator title FAIL LOUDLY instead
# of silently producing an empty flat.
#
# Modes:
#   (none)   regenerate flats/ and flats/MANIFEST.md
#   --check  RED if the committed flats or MANIFEST diverge from the
#            current blueprint/repo state (CI freshness mode). Any
#            divergence is COULD-NOT-EVALUATE for downstream claims.
#
# The MANIFEST is deterministic (no timestamps): same repo state in,
# same manifest out — so `--check` is a plain byte diff.
set -euo pipefail

# The Aiken sources, blueprint, and these flats live in the SAME repo
# (formal-verification/ is a subdirectory of cip113-programmable-tokens),
# so the source-commit axis of the identity triple is implicit: it is the
# commit containing this file.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BLUEPRINT="$REPO/plutus.json"
FLATS="$(cd "$(dirname "$0")/.." && pwd)/flats"
LEAN_SRC="$(cd "$(dirname "$0")/.." && pwd)/Cip113Spike"
MANIFEST="$FLATS/MANIFEST.md"
MODE="${1:-generate}"

declare -a TITLES=(
  "programmable_logic_base.programmable_logic_base.spend:programmable_logic_base"
  "transfer.transfer.withdraw:transfer"
  "third_party.third_party.withdraw:third_party"
  "unfracking.unfracking.withdraw:unfracking"
  "registry_mint.registry_mint.mint:registry_mint"
)

# --- Completeness gate (EXP-0c / V16, seed S-12) ---
#
# The blueprint carries MANY validator titles; the flats above are a
# strict SUBSET. A subset that is silent is a coverage lie: a title that
# is neither extracted (TITLES) nor explicitly declared here would slip
# through --check with no flat and no theorem, and no one would know.
#
# So every blueprint title must be accounted for. The named-purpose
# titles below (name.name.purpose) are the validators we have DECIDED not
# to verify yet, each with a one-line reason. `--check' goes RED if the
# blueprint grows a title that is in neither list — you must then either
# add a flat (TITLES) or declare the omission here.
#
# Dedup note: the blueprint lists a `.else` handler per validator whose
# `compiledCode` is byte-identical to the primary purpose (the tracked
# flat therefore exercises the else arm too — see extract-flats' own
# `.spend`/`.else` identity). The completeness check dedupes by
# compiledCode the same way TITLES tracks one flat per validator, so
# `.else` twins do not need their own DELIBERATELY_UNVERIFIED entry.
declare -a DELIBERATELY_UNVERIFIED=(
  "registry_spend.registry_spend.spend:no flat yet — decoy-node authentication rests on registry_mint×registry_spend induction; least-verified item in the repo (V7/V11.3, seed S-17)"
  "protocol_params_mint.protocol_params_mint.mint:no flat yet — write-once one-shot mint; deployment-time construction gate, covered instead by scripts/deployment-manifest-check.sh (V11.2/V13)"
  "issuance_mint.issuance_mint.mint:no flat yet — issuance×PLB×delegate composition deferred (blocked on the rewarding-context builder, seeds S-13/14/15)"
  "issuance_cbor_hex_mint.issuance_cbor_hex_mint.mint:no flat yet — CBOR-hex issuance variant; same deferral as issuance_mint"
  "always_fail.always_fail.spend:no flat needed — unconditional fail (the params-NFT lock target); nothing to verify beyond \`fail\`"
  "coordination_spend.coordination_spend.spend:no flat yet — the in-place upgrade gate (#99): decides who may rewrite the protocol-params datum, which carries every delegate credential and max_inline_datum_bytes. High-value target, deferred to a later tier."
  "upgrade_multisig.upgrade_multisig.withdraw:no flat yet — the federated upgrade authority (#99), deferred alongside coordination_spend."
)

if command -v shasum >/dev/null; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
  sha256_str() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
else
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
  sha256_str() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
fi

# --- Identity triple, read mechanically (never from prose) ---
COMPILER="$(jq -er '.compiler.name + " " + .compiler.version' <(jq .preamble "$BLUEPRINT"))"
PLUTUS_VERSION="$(jq -er '.preamble.plutusVersion' "$BLUEPRINT")"
BLUEPRINT_SHA="$(sha256 "$BLUEPRINT")"

# --- R6 identity coordinates (fuel + Aiken build environment) ---
#
# Fuel: acceptance formally means "halts within N CEK steps", and N is
# baked per-artifact into the Lean prep commands under Cip113Spike/.
# `prep_fuel` below reads it MECHANICALLY from those lines and never from
# prose or from a number typed into this script: the `#import_uplc` that
# names `flats/<name>.flat` gives the Lean binding, and the `#prep_uplc`
# that names that binding gives N. An artifact that is imported but not
# yet prepped reports `not prepped` — the coordinate is then declared
# ABSENT rather than invented, and any claim citing that flat is
# COULD-NOT-EVALUATE on this axis alone.
#
# Aiken build environment: a validator can branch on `env/<module>.ak`
# (e.g. with_assertions vs default), so which env the committed blueprint
# was built under is an identity coordinate. Aiken's default when `aiken
# build` is run with no `--env` flag is `env/default.ak`.
ENV_DIR="$REPO/env"
if [ -d "$ENV_DIR" ]; then
  AIKEN_ENV="default (env/default.ak — repo has an env/ dir; \`aiken build\` with no --env uses default)"
else
  AIKEN_ENV="default env (no env/ dir present)"
fi

# Read the prep fuel for one flat out of the Lean sources. Two hops, both
# mechanical: flat path -> `#import_uplc` binding -> `#prep_uplc` budget.
# Prints the number, or `not prepped` / `not imported`.
prep_fuel() {
  local flat="$1" ident fuel
  ident="$(grep -hE "^#import_uplc[[:space:]]+[^[:space:]]+[[:space:]].*\"flats/${flat}\.flat\"" \
    "$LEAN_SRC"/*.lean 2>/dev/null | awk '{print $2}' | head -1 || true)"
  if [ -z "$ident" ]; then echo "not imported"; return; fi
  fuel="$(grep -hE "^#prep_uplc[[:space:]]+[^[:space:]]+[[:space:]]+${ident}([[:space:]]|\$)" \
    "$LEAN_SRC"/*.lean 2>/dev/null | awk '{print $NF}' | head -1 || true)"
  if [ -z "$fuel" ]; then echo "not prepped"; else echo "$fuel"; fi
}

# Completeness gate: every blueprint title must be either extracted
# (TITLES) or explicitly declared unverified (DELIBERATELY_UNVERIFIED),
# deduped by compiledCode so `.else` twins ride along with their primary.
# Prints offending titles to stderr; returns nonzero if any are silent.
check_completeness() {
  # Build a newline-delimited set of accounted-for compiledCode sha256s
  # from both lists (macOS bash 3.2 has no associative arrays).
  local accounted="" entry title code
  for entry in "${TITLES[@]}" "${DELIBERATELY_UNVERIFIED[@]}"; do
    title="${entry%%:*}"
    code="$(jq -er --arg t "$title" \
      '.validators[] | select(.title == $t) | .compiledCode' "$BLUEPRINT")" \
      || { echo "COMPLETENESS: declared title '$title' not found in blueprint" >&2; return 1; }
    accounted="$accounted$(sha256_str "$code")"$'\n'
  done

  local rc=0 t c
  # Every blueprint title's compiledCode must be accounted for.
  while IFS=$'\t' read -r t c; do
    if ! printf '%s' "$accounted" | grep -qxF "$c"; then
      echo "COMPLETENESS: blueprint title '$t' is neither in TITLES nor DELIBERATELY_UNVERIFIED — add a flat or declare the omission" >&2
      rc=1
    fi
  done < <(jq -er '.validators[] | [.title, (.compiledCode)] | @tsv' "$BLUEPRINT" \
             | while IFS=$'\t' read -r tt cc; do printf '%s\t%s\n' "$tt" "$(sha256_str "$cc")"; done)
  return "$rc"
}

emit_manifest() {
  cat <<EOF
# Flat artifact manifest — identity triple for every Lean claim

Mechanically generated by \`scripts/extract-flats.sh\`. Do not edit by
hand. \`--check\` fails RED on any divergence from the blueprint or repo
state; a claim citing flats whose manifest does not check out is
COULD-NOT-EVALUATE.

## Identity triple (commit + toolchain + semantics variant)

- **Source commit**: implicit — the Aiken sources, \`plutus.json\`, and
  these flats live in the same repository, so the source commit for every
  claim is the commit containing this manifest. CI enforces per push that
  a clean \`aiken build\` reproduces the committed blueprint and that
  these flats match it (\`--check\`).
- **Toolchain**: $COMPILER (from the blueprint's own \`.preamble.compiler\`,
  not from prose or from whatever \`aiken\` is currently installed)
- **Plutus version**: $PLUTUS_VERSION
- **BuiltinSemanticsVariant**: \`defaultFunSemanticsVariantE\` (PlutusV3,
  post-Conway). Evidence: PlutusCoreBlaster \`#prep_uplc\` builds
  \`.exec\`/\`.prop\` via \`cekExecuteProgram = cekExecuteProgramWithSemanticVariant default\`
  (\`PlutusCore/UPLC/CekMachine.lean\`), and
  \`Inhabited BuiltinSemanticsVariant := .defaultFunSemanticsVariantE\`
  (\`PlutusCore/Default/Basic.lean:54\`) — the correct variant for our
  mainnet deployment target.
- **CBOR wrapping**: \`single_cbor_hex\` — an Aiken blueprint's
  \`compiledCode\` is ONE CBOR bytestring layer around flat-encoded UPLC
  (verified empirically 2026-08-06: inner bytes start \`010100\`, the
  flat version header, not another CBOR major-type-2 byte). The
  double-wrapped form is the on-chain tx-witness encoding, not the
  blueprint encoding.
- **Prep fuel** (R6, identity coordinate 3): acceptance formally means
  "halts within N CEK steps". N is baked per-artifact into the Lean
  \`#prep_uplc\` commands under \`Cip113Spike/\`, and the **prep fuel**
  column of the Flats table below is read MECHANICALLY from those lines —
  the \`#import_uplc\` naming the flat gives the Lean binding, the
  \`#prep_uplc\` naming that binding gives N. It is never typed into the
  generator. Fuel BELOW a validator's accepting step count silently turns
  every acceptance into \`State.Error\`, indistinguishable from a
  rejection, so it is measured on concrete accepting contexts
  (\`scripts/fuel-probe.lean\`), never guessed. \`not prepped\` in that
  column means the artifact decodes and its parameter application is
  recorded but no \`#prep_uplc\` exists for it yet: the coordinate is
  ABSENT, and ANY claim citing that flat is COULD-NOT-EVALUATE on this
  axis alone.
- **Aiken build environment** (R6, identity coordinate 4): $AIKEN_ENV.

## Blueprint

- \`plutus.json\` sha256: \`$BLUEPRINT_SHA\`
- Source→blueprint reproducibility is NOT asserted by this manifest;
  it is established separately by the baseline leg of
  \`scripts/falsification-control.sh\` (clean rebuild must reproduce
  \`compiledCode\` byte-for-byte).

## Flats

| flat | blueprint title | bytes | prep fuel | sha256 |
|---|---|---|---|---|
EOF
  for entry in "${TITLES[@]}"; do
    title="${entry%%:*}"
    name="${entry##*:}"
    code="$(jq -er --arg t "$title" \
      '.validators[] | select(.title == $t) | .compiledCode' "$BLUEPRINT")"
    printf '| `%s.flat` | `%s` | %d | %s | `%s` |\n' \
      "$name" "$title" "$((${#code} / 2))" "$(prep_fuel "$name")" \
      "$(sha256_str "$code")"
  done

  cat <<'EOF'

## Deliberately unverified (declared subset — EXP-0c / V16, seed S-12)

The flats above are a strict SUBSET of the blueprint's validators. The
titles below are present in the blueprint but carry NO flat and NO
theorem — the omission is DECLARED here, not silent. `extract-flats.sh
--check` goes RED if the blueprint grows any title that is in neither
this list nor the extracted set, so the subset can never drift open
quietly.

| blueprint title | reason unverified |
|---|---|
EOF
  for entry in "${DELIBERATELY_UNVERIFIED[@]}"; do
    title="${entry%%:*}"
    reason="${entry#*:}"
    printf '| `%s` | %s |\n' "$title" "$reason"
  done
}

if [ "$MODE" = "--check" ]; then
  status=0
  # Leg 0: completeness — every blueprint title is extracted or declared.
  check_completeness || status=1
  # Leg 1: each committed flat byte-matches the current blueprint title.
  for entry in "${TITLES[@]}"; do
    title="${entry%%:*}"
    name="${entry##*:}"
    code="$(jq -er --arg t "$title" \
      '.validators[] | select(.title == $t) | .compiledCode' "$BLUEPRINT")"
    if [ "$code" != "$(cat "$FLATS/$name.flat")" ]; then
      echo "STALE: $name.flat does not match blueprint title '$title'" >&2
      status=1
    fi
  done
  # Leg 2: the committed manifest byte-matches a regeneration.
  if ! diff -u "$MANIFEST" <(emit_manifest) >&2; then
    echo "STALE: MANIFEST.md does not match current blueprint/repo state" >&2
    status=1
  fi
  [ "$status" = 0 ] && echo "flats + manifest are fresh"
  exit "$status"
fi

# Refuse to regenerate against a blueprint whose title set is not fully
# accounted for — otherwise the generated MANIFEST would omit a live
# validator without a word.
check_completeness || {
  echo "refusing to regenerate: blueprint has undeclared titles (see above)" >&2
  exit 1
}

for entry in "${TITLES[@]}"; do
  title="${entry%%:*}"
  name="${entry##*:}"
  code="$(jq -er --arg t "$title" \
    '.validators[] | select(.title == $t) | .compiledCode' "$BLUEPRINT")"
  printf '%s' "$code" > "$FLATS/$name.flat"
  echo "wrote $name.flat ($((${#code} / 2)) bytes)"
done
emit_manifest > "$MANIFEST"
echo "wrote MANIFEST.md ($COMPILER, variant E)"
