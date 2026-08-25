/-
Tier-1 smoke test: can IOG's PlutusCoreBlaster (upstream `main`) decode
the UPLC that Aiken v1.1.23 emits for the CIP-113 validators?

Each `#import_uplc` below parses the blueprint's `compiledCode` (a
single-CBOR-wrapped flat-encoded PlutusV3 program, extracted verbatim
from `plutus.json` by `scripts/extract-flats.sh`) through PCB's flat
decoder. Success ⇒ Aiken's term/builtin surface is covered by stock PCB
and no fork is needed for decode. Failure names the unsupported
construct.

Sizes (see `flats/MANIFEST.md` for the pinned sha256s): base 829 B,
registry_mint 1928 B, unfracking 1956 B, third_party 2025 B, transfer
2283 B. Decoding all five costs ~2 s and ~1 GB — decode is NOT the
scaling risk in this tree; symbolic prep is (see PrepBase.lean).
-/
import PlutusCore

-- Smallest first: the PLB spend validator (829 bytes).
#import_uplc plbBase PlutusV3 single_cbor_hex "flats/programmable_logic_base.flat"

-- The registry linked-list mint policy (1928 bytes).
#import_uplc registryMint PlutusV3 single_cbor_hex "flats/registry_mint.flat"

-- The standalone unfracking withdraw-0 engine (1956 bytes).
#import_uplc unfracking PlutusV3 single_cbor_hex "flats/unfracking.flat"

-- The standalone third-party (seize / clawback / freeze) withdraw-0
-- engine (2025 bytes).
#import_uplc thirdParty PlutusV3 single_cbor_hex "flats/third_party.flat"

-- The transfer hot path (2283 bytes) — the largest artifact.
#import_uplc transfer PlutusV3 single_cbor_hex "flats/transfer.flat"

-- If everything above elaborates, the imported terms exist; print one as
-- a visible success marker.
#check plbBase
