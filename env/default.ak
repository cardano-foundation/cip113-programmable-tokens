/// Identity: the default build's binding for `assert_no_ada_policy`. This is
/// what ships in `plutus.json` and every deployed script — the ada-absence
/// check in `env/with_assertions.ak` runs only under `--env with_assertions`,
/// never here.
pub fn assert_no_ada_policy(value: a) -> a {
  value
}
