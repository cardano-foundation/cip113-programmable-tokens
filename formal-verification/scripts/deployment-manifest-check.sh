#!/usr/bin/env bash
# Deployment-manifest closure checker (V13 — the reviewer's #1 priority).
#
# WHY THIS EXISTS, and why no theorem replaces it
# -----------------------------------------------
# The protocol-params datum forms a trust-root CYCLE that nothing on-chain
# validates: it is written ONCE by protocol_params_mint into a UTxO locked
# at an always-fail address, and thereafter only READ (as a reference
# input) by PLG / unfracking. The Lean theorems quantify over a
# `(.ScriptCredential param)` with the CONSTRUCTOR fixed and only the 28
# hash bytes universally quantified — so a wrong credential wired at
# deployment is a total break with EVERY theorem still true: the
# ∀-quantifier cannot see a wrong parameter, and a vkey parameterisation
# puts the deployment OUTSIDE all proven theorem families entirely. This
# pre-submission checker is the ONLY opportunity to catch it.
#
# MANIFEST SCHEMA (see examples/deployment-manifest.example.json)
# ---------------------------------------------------------------
# All hashes are hex; script/credential hashes are 28-byte blake2b-224
# (56 hex chars). A Credential is { "constructor": "Script"|"VerificationKey",
# "hash": "<hex>" } mirroring the Aiken/CIP on-chain encoding
# (VerificationKey = constructor 0, Script = constructor 1).
#
#   params_nft_policy            : hex        policy id of the params NFT
#   params_datum.registry_node_cs: hex        field 0 of ProgrammableLogicGlobalParams
#   params_datum.prog_logic_cred : Credential field 1 (PLB payment credential)
#   params_datum.unfracking_cred : Credential field 2 (unfracking w0 credential)
#   plb.script_hash              : hex        applied PLB script hash
#   plb.applied_stake_cred       : Credential PLB's `stake_cred` parameter (= PLG credential)
#   plg.script_hash              : hex        applied PLG script hash
#   plg.applied_params_policy    : hex        PLG's `params_policy` parameter
#   unfracking.script_hash       : hex        applied unfracking script hash
#   unfracking.applied_params_policy : hex    unfracking's `params_policy` parameter
#   registry_mint.script_hash    : hex        registry_mint policy id (= registry_node_cs)
#   params_utxo_value.lovelace   : int        ada in the params UTxO
#   params_utxo_value.assets     : [ {policy, asset_name_hex, quantity} ]
#
# CLOSURE CHECKS (all must hold; each row names its seed for R4):
#   1. datum.prog_logic_cred.hash == plb.script_hash            (seed: wrong prog_logic_cred)
#   2. plg.applied_params_policy  == params_nft_policy          (seed: wrong plg param)
#   3. datum.registry_node_cs     == registry_mint.script_hash  and
#      unfracking.applied_params_policy == params_nft_policy    (seed: registry/param drift)
#   4. datum.unfracking_cred.hash == unfracking.script_hash AND constructor Script (seed: unfracking mismatch)
#   5. every credential field constructor is Script             (seed: vkey constructor)
#   6. params_utxo_value holds ONLY ada + the params NFT        (seed: co-asset in value)
#
# UNVERIFIABLE (declared, not silent — see the WARN lines at runtime):
#   The blueprint (../plutus.json) still carries UNBOUND `parameters`
#   (stake_cred, params_policy, ...), so its `hash`/`compiledCode` are
#   PRE-parameterisation — they are NOT the deployed applied hashes. This
#   checker therefore CANNOT independently derive the applied PLB/PLG/
#   unfracking hashes from the blueprint; it checks the manifest's applied
#   hashes for internal CLOSURE and cross-checks the blueprint only where
#   the blueprint value is genuinely comparable (title presence, and the
#   params-NFT token name convention from protocol_params_mint). Deriving
#   applied hashes would require running `aiken blueprint apply` — out of
#   scope here and deliberately declared rather than faked.
#
# Exit: 0 green, nonzero red. Output style mirrors falsification-control.sh.
set -euo pipefail

FV="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$FV/.." && pwd)"
BLUEPRINT="$REPO/plutus.json"

MANIFEST="${1:-}"
[ -n "$MANIFEST" ] || { echo "usage: $0 <deployment-manifest.json>" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "RED: manifest not found: $MANIFEST" >&2; exit 1; }
[ -f "$BLUEPRINT" ] || { echo "RED: blueprint not found: $BLUEPRINT" >&2; exit 1; }

red()  { echo "RED: $*" >&2; exit 1; }
warn() { echo "WARN (UNVERIFIABLE): $*" >&2; }
ok()   { echo "   OK: $*"; }

# jq -er: every field extraction FAILS LOUDLY if the field is missing.
jqf() { jq -er "$1" "$MANIFEST" || red "manifest missing required field: $1"; }

# --- Load fields (fail loudly on any missing) ---
PARAMS_NFT_POLICY="$(jqf '.params_nft_policy')"
DATUM_REG_CS="$(jqf '.params_datum.registry_node_cs')"
PLC_CTOR="$(jqf '.params_datum.prog_logic_cred.constructor')"
PLC_HASH="$(jqf '.params_datum.prog_logic_cred.hash')"
UNF_CTOR="$(jqf '.params_datum.unfracking_cred.constructor')"
UNF_HASH="$(jqf '.params_datum.unfracking_cred.hash')"
PLB_HASH="$(jqf '.plb.script_hash')"
PLB_STAKE_CTOR="$(jqf '.plb.applied_stake_cred.constructor')"
PLB_STAKE_HASH="$(jqf '.plb.applied_stake_cred.hash')"
PLG_HASH="$(jqf '.plg.script_hash')"
PLG_PARAM="$(jqf '.plg.applied_params_policy')"
UNF_SCRIPT_HASH="$(jqf '.unfracking.script_hash')"
UNF_PARAM="$(jqf '.unfracking.applied_params_policy')"
REG_MINT_HASH="$(jqf '.registry_mint.script_hash')"

echo "== Deployment-manifest closure check: $MANIFEST =="

# --- UNVERIFIABLE disclosures, up front (declared, not silent) ---
# Detect whether the blueprint hashes are pre- or post-parameterisation.
UNBOUND_PARAMS="$(jq -r '[.validators[] | select((.parameters // []) | length > 0)] | length' "$BLUEPRINT")"
if [ "$UNBOUND_PARAMS" -gt 0 ]; then
  warn "blueprint validators still carry UNBOUND parameters — its hash/compiledCode are PRE-parameterisation, NOT the deployed applied hashes."
  warn "cannot independently derive applied PLB/PLG/unfracking hashes from the blueprint; checking manifest-internal closure + blueprint conventions only."
  warn "NOT CHECKED: manifest.plb.script_hash == aiken-applied hash of PLB(stake_cred)."
  warn "NOT CHECKED: manifest.plg.script_hash == aiken-applied hash of PLG(params_policy)."
  warn "NOT CHECKED: manifest.unfracking.script_hash == aiken-applied hash of unfracking(params_policy)."
else
  ok "blueprint hashes are post-parameterisation (no unbound params) — applied-hash cross-checks are in principle possible (not implemented here)."
fi

# Sanity: the blueprint must at least still DECLARE these validators
# (a renamed/removed validator invalidates the whole closure model).
for t in \
  "programmable_logic_base.programmable_logic_base.spend" \
  "programmable_logic_global.programmable_logic_global.withdraw" \
  "unfracking.unfracking.withdraw" \
  "protocol_params_mint.protocol_params_mint.mint" \
  "registry_mint.registry_mint.mint"; do
  jq -er --arg t "$t" '.validators[] | select(.title == $t) | .title' "$BLUEPRINT" >/dev/null \
    || red "blueprint no longer declares '$t' — closure model is stale, refusing to pass"
done
ok "blueprint still declares all five closure validators"

# --- Check 5 (run first so a vkey field can't masquerade past 1/4): ---
# every credential-field constructor must be Script. A VerificationKey
# parameterisation puts the deployment OUTSIDE all proven theorem
# families (the theorems fix the constructor to .ScriptCredential).
check_script_ctor() {
  # $1 = human name, $2 = constructor value
  case "$2" in
    Script) ok "$1 constructor is Script" ;;
    VerificationKey)
      red "$1 constructor is VerificationKey — a vkey parameterisation puts the deployment OUTSIDE all proven theorem families (the theorems quantify over .ScriptCredential only). REFUSE." ;;
    *) red "$1 constructor '$2' is neither Script nor VerificationKey — malformed manifest" ;;
  esac
}
check_script_ctor "params_datum.prog_logic_cred" "$PLC_CTOR"      # seed: vkey constructor
check_script_ctor "params_datum.unfracking_cred" "$UNF_CTOR"
check_script_ctor "plb.applied_stake_cred"       "$PLB_STAKE_CTOR"

# --- Check 1: prog_logic_cred == PLB script hash --------------------
[ "$PLC_HASH" = "$PLB_HASH" ] \
  || red "params_datum.prog_logic_cred.hash ($PLC_HASH) != plb.script_hash ($PLB_HASH) — PLB UTxOs would forward to a credential no PLB owns; total break. (seed: wrong prog_logic_cred)"
ok "prog_logic_cred == plb.script_hash"

# --- Check 2: PLG applied params_policy == params NFT policy ---------
[ "$PLG_PARAM" = "$PARAMS_NFT_POLICY" ] \
  || red "plg.applied_params_policy ($PLG_PARAM) != params_nft_policy ($PARAMS_NFT_POLICY) — PLG would read a DIFFERENT (or non-existent) params datum. (seed: wrong plg param)"
ok "plg.applied_params_policy == params_nft_policy"

# --- Check 3: registry_node_cs consistency + unfracking param -------
[ "$DATUM_REG_CS" = "$REG_MINT_HASH" ] \
  || red "params_datum.registry_node_cs ($DATUM_REG_CS) != registry_mint.script_hash ($REG_MINT_HASH) — node authentication would target the wrong policy. (seed: registry drift)"
ok "registry_node_cs == registry_mint.script_hash"
[ "$UNF_PARAM" = "$PARAMS_NFT_POLICY" ] \
  || red "unfracking.applied_params_policy ($UNF_PARAM) != params_nft_policy ($PARAMS_NFT_POLICY) — unfracking would read the wrong params datum. (seed: param drift)"
ok "unfracking.applied_params_policy == params_nft_policy"

# --- Check 4: unfracking_cred == unfracking script hash -------------
# (constructor already asserted Script above.)
[ "$UNF_HASH" = "$UNF_SCRIPT_HASH" ] \
  || red "params_datum.unfracking_cred.hash ($UNF_HASH) != unfracking.script_hash ($UNF_SCRIPT_HASH) — PLG's UnfrackingAct arm would gate on the wrong withdrawal. (seed: unfracking mismatch)"
ok "unfracking_cred == unfracking.script_hash (and constructor Script)"

# Soft consistency: PLB's stake_cred parameter should be the PLG hash
# (PLB forwards to PLG's withdraw-0). This is advisory, not a hard
# closure edge, since PLB's stake_cred is nominally free.
if [ "$PLB_STAKE_HASH" = "$PLG_HASH" ]; then
  ok "plb.applied_stake_cred.hash == plg.script_hash (PLB forwards to PLG)"
else
  warn "plb.applied_stake_cred.hash ($PLB_STAKE_HASH) != plg.script_hash ($PLG_HASH) — PLB would forward to a stake credential that is not this PLG. Intended only for exotic deployments."
fi

# --- Check 6: params UTxO value shape — ONLY ada + the params NFT ---
# protocol_params_mint locks the NFT (token name "ProtocolParams",
# hex 50726f746f636f6c506172616d73) at the always-fail address but does
# NOT constrain EXTRA assets on that output. A co-asset that sorts LOWER
# than the params policy permanently hides the params from peek_first
# (lib/assets.ak: `list.head(list.tail(from_value value))`) — the V11
# item-2 brick, a deployed-dead outcome no theorem can see.
PARAMS_TOKEN_HEX="50726f746f636f6c506172616d73"  # "ProtocolParams"
ASSET_COUNT="$(jq -er '.params_utxo_value.assets | length' "$MANIFEST")"
[ "$ASSET_COUNT" -eq 1 ] \
  || red "params_utxo_value carries $ASSET_COUNT non-ada assets; MUST be exactly 1 (the params NFT). A co-asset can permanently hide params from peek_first. (seed: co-asset in value)"
A_POLICY="$(jqf '.params_utxo_value.assets[0].policy')"
A_NAME="$(jqf '.params_utxo_value.assets[0].asset_name_hex')"
A_QTY="$(jqf '.params_utxo_value.assets[0].quantity')"
[ "$A_POLICY" = "$PARAMS_NFT_POLICY" ] \
  || red "the single params-UTxO asset is policy $A_POLICY, not params_nft_policy $PARAMS_NFT_POLICY. (seed: co-asset in value)"
[ "$A_NAME" = "$PARAMS_TOKEN_HEX" ] \
  || red "params NFT asset name is $A_NAME, not 'ProtocolParams' ($PARAMS_TOKEN_HEX) — protocol_params_mint enforces this name. (seed: wrong token name)"
[ "$A_QTY" -eq 1 ] \
  || red "params NFT quantity is $A_QTY, not 1 — protocol_params_mint mints strictly one. (seed: quantity)"
ok "params_utxo_value holds ONLY ada + exactly the params NFT (name ProtocolParams, qty 1)"

echo "GREEN — deployment manifest is closed on every checkable edge (see WARN lines for what is UNVERIFIABLE)."
