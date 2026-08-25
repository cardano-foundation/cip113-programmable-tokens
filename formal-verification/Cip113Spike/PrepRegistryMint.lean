/-
Tier-1: import the `registry_mint` minting policy — the registry linked
list — and record its parameter application.

Parameter evidence for `registry_mint` — THREE parameters, then ctx (the
only multi-parameter artifact under verification; they are applied left
to right, in declaration order). Aiken source:
`validators/registry_mint.ak`:

    validator registry_mint(
      utxo_ref: OutputReference,
      issuance_cbor_hex_cs: PolicyId,
      registry_spend_cred: Credential,
    )

1. `utxo_ref : OutputReference` — the one-shot seed input.
   IsData: `Constr 0 [B txid, I index]`, which is exactly CLAB's V3
   `TxOutRef` encoding (`CardanoLedgerApi/V3/Tx.lean`), so the Lean-side
   type is `TxOutRef` and no hand-rolled `Data` is needed.
2. `issuance_cbor_hex_cs : PolicyId` — IsData: `Data.B bytes`.
3. `registry_spend_cred : Credential` — IsData: `Constr 0/1 [B bytes]`.

The handler is `mint(redeemer, policy_id, self)`: the ledger invokes it
with a Minting purpose, so contexts carry `scriptContextScriptInfo :=
.MintingScript ownPolicy` and are applied via `mintingInputs` (stock
upstream CLAB helper) — NOT `spendingInputs`/`rewardingInputs`, which
the other four artifacts use. The redeemer selects `RegistryInit` (the
one-shot origin node) or `RegistryInsert` (a new node), two very
different cost shapes; a fuel measured on one says nothing about the
other.

NO `#prep_uplc` HERE — same reason as `PrepTransfer.lean`, which carries
the measurements: unshaped symbolic prep of a ~2 KB artifact blows up
exponentially in the fuel long before the fuel reaches this validator's
accepting step count, so any fuel that elaborates would certify nothing.
A concrete accepting context per redeemer arm (to measure K) and a shaped
prep built on its skeleton are prerequisites, and both belong to the
slice that writes the theorems.

IDENTITY: `flats/registry_mint.flat` (1928 B), pinned by
`flats/MANIFEST.md`; semantics variant E (PlutusV3 post-Conway) via
PlutusCoreBlaster's `cekExecuteProgram` default — see `PrepBase.lean`.
The fuel coordinate is NOT yet established for this artifact.
-/
import PlutusCore.UPLC
import CardanoLedgerApi.V3
import Blaster

namespace CIP113

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (Credential ScriptContext TxOutRef mintingInputs)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.Term (Term)

#import_uplc registryMintPolicy PlutusV3 single_cbor_hex "flats/registry_mint.flat"

/-- Parameter application for `registry_mint`: the three compile-time
parameters in DECLARATION ORDER, then the minting context. Recorded here
so the theorem slice inherits the checked shape; not yet passed to
`#prep_uplc` (see the module comment). -/
def registryMintInputs (utxoRef : TxOutRef) (issuanceCborHexCs : ByteString)
    (registrySpendCred : Credential) (ctx : ScriptContext) : List Term :=
  toTerm utxoRef :: toTerm issuanceCborHexCs :: toTerm registrySpendCred ::
    mintingInputs ctx

end CIP113
