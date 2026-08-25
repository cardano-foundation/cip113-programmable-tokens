-- Default build target. Every module reachable from here is compiled by
-- `lake build`; nothing else in the tree is.
--
-- DELIBERATELY NOT IMPORTED: `controls/MutantControl.lean` and
-- `controls/AuthMutantControl.lean`. They are falsification CONTROLS —
-- each one runs a mutant artifact against a theorem that must come back
-- Falsified — and they must never be part of the default build even when
-- they are healthy (`scripts/falsification-control.sh` drives them
-- explicitly, against mutant flats it builds into `controls/flats/`).
-- Right now they also cannot compile: they import theorem modules that
-- the PLG dissolution (#110) removed and reference the `programmable_logic_global`
-- mutant flat, which no longer exists. Their content is preserved
-- verbatim for the slice that re-derives the theorems they falsify; that
-- slice restores them by re-pointing their imports and mutant flats at
-- the current five-title surface. Both are outside the `lean_lib` globs
-- in `lakefile.lean` as well, so no glob widening can pull them in by
-- accident.
import Cip113Spike.Smoke
import Cip113Spike.PrepBase
import Cip113Spike.PrepTransfer
import Cip113Spike.PrepThirdParty
import Cip113Spike.PrepUnfracking
import Cip113Spike.PrepRegistryMint
