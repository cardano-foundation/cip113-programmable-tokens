-- Default build target. Every module reachable from here is compiled by
-- `lake build`; nothing else in the tree is.
--
-- DELIBERATELY NOT IMPORTED: `controls/MutantControl.lean` and
-- `controls/AuthMutantControl.lean`. They are falsification CONTROLS —
-- each one runs a mutant artifact against theorems that must come back
-- false — and they must never be part of the default build even when
-- they are healthy (`scripts/falsification-control.sh` drives them
-- explicitly, against mutant flats it builds into `controls/flats/`, a
-- gitignored directory that is normally absent).
-- `MutantControl.lean` IS healthy: it falsifies nine `PropsBase`
-- theorems on a PLB rebuilt with its custody check gutted, and leg 4 of
-- the driver runs it. `AuthMutantControl.lean` still cannot compile — it
-- imports a theorem module the PLG dissolution (#110) removed and
-- references the `programmable_logic_global` mutant flat, which no
-- longer exists — so the driver's leg 4b is a declared skip until the
-- `transfer` artifact has theorems for it to falsify. Both are outside
-- the `lean_lib` globs in `lakefile.lean` as well, so no glob widening
-- can pull them in by accident.
import Cip113Spike.Smoke
import Cip113Spike.PrepBase
import Cip113Spike.PropsBase
import Cip113Spike.PrepTransfer
import Cip113Spike.PrepThirdParty
import Cip113Spike.PrepUnfracking
import Cip113Spike.PrepRegistryMint
