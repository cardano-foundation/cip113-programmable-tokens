import Lake
open Lake DSL

package «Cip113Spike» where
  -- Deps pinned by exact git rev (stock upstream, zero forks) — part of
  -- the identity discipline: a stranger's build and CI resolve the same
  -- toolchain bytes we proved against. Bump deliberately, never track a
  -- branch.
  --
  -- Require Blaster BEFORE PlutusCore/CardanoLedgerApi: both downstream
  -- lakefiles require Blaster by git URL (PCB @ "main", CLAB @
  -- "beta-lambda-cache-optimization"), and lake resolves a package name
  -- at first encounter — the pin below must win (lesson from the
  -- wsc-containment-proofs lakefile).
  require Blaster from git
    "https://github.com/input-output-hk/Lean-blaster" @
    "083bae7971414d894b56b5bbf4108c63e17bc42a"
  require PlutusCore from git
    "https://github.com/input-output-hk/PlutusCoreBlaster" @
    "a04042c4b7b19c66e7e6fa5bbcc3b1c985894ed0"
  require CardanoLedgerApi from git
    "https://github.com/input-output-hk/CardanoLedgerApiBlaster" @
    "5dab3c43f042b8735b6d067223baaa8d32ed28a1"

@[default_target]
lean_lib «Cip113Spike» where
