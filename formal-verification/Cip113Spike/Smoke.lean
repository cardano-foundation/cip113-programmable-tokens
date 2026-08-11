/-
Tier-1 smoke test: can IOG's PlutusCoreBlaster (upstream `main`) decode
the UPLC that Aiken v1.1.22 emits for the CIP-113 validators?

Each `#import_uplc` below parses the blueprint's `compiledCode` (a
single-CBOR-wrapped flat-encoded PlutusV3 program, extracted verbatim
from `plutus.json` at cip113-programmable-tokens branch
`test/blaster-tier0-properties`) through PCB's flat decoder. Success ⇒
Aiken's term/builtin surface is covered by stock PCB and no fork is
needed for decode (answers question 2 for Phil empirically). Failure
names the unsupported construct.

Sizes: base 141 B, unfracking 1736 B, registry_mint 1928 B, PLG 2996 B —
all well under the Plutarch equivalents (192/2594/–/5624 B).
-/
import PlutusCore

-- Smallest first: the PLB spend validator (141 bytes).
#import_uplc plbBase PlutusV3 single_cbor_hex "flats/programmable_logic_base.flat"

-- The standalone unfracking withdraw-0 engine (1736 bytes).
#import_uplc unfracking PlutusV3 single_cbor_hex "flats/unfracking.flat"

-- The registry linked-list mint policy (1928 bytes).
#import_uplc registryMint PlutusV3 single_cbor_hex "flats/registry_mint.flat"

-- The PLG coordinator (2996 bytes) — the real prize.
#import_uplc plgGlobal PlutusV3 single_cbor_hex "flats/programmable_logic_global.flat"

-- If everything above elaborates, the imported terms exist; print one as
-- a visible success marker.
#check plbBase
