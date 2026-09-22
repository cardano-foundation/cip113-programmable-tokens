# Contributing to this project

Thanks for considering contributing and helping us build this project!

This repository contains the **on-chain** Aiken implementation of CIP-113 programmable tokens. For off-chain work (reference frontend, Java backend, module implementations), see the [platform repository](https://github.com/cardano-foundation/cip113-programmable-tokens-platform).

The best way to contribute right now is to try things out and provide feedback, but we also accept contributions to the documentation and obviously to the code itself.

This document contains guidelines to help you get started and how to make sure your contribution gets accepted, making you our newest contributor!

## Communication channels

Should you have any questions or need some help getting set up, you can use these communication channels to reach the team and get answers in a way others can benefit from as well:

- [CIP-113 Pull Request](https://github.com/cardano-foundation/CIPs/pull/444) — For standard-related discussions and feedback
- GitHub [Issues](../../issues) — For bug reports and implementation-specific issues

**Note:** As this implementation is based on the evolving CIP-113 standard, we encourage participation in the CIP-113 discussion while the standard is being finalized.

## Your first contribution

Contributing to the documentation, its translation, reporting bugs, or proposing features are awesome ways to get started.

Also, take a look at the tests. Making sure we have the best high-quality test suite is vital for this project.

### Documentation

Documentation is available in:

- This [README](./README.md) — Overview, quick start, and component reference
- The [`documentation/`](./documentation/) directory — Architecture, integration guides, and module development

For off-chain documentation (frontend, backend, modules), see the [platform repository](https://github.com/cardano-foundation/cip113-programmable-tokens-platform).

### Bug reports

[Submit an issue](../../issues/new) for implementation-specific bugs.

For bug reports, it's very important to explain:

* What version/commit you used
* Steps to reproduce (or steps you took)
* What behavior you saw (ideally supported by logs)
* What behavior you expected

For issues related to the CIP-113 standard itself, please use the [CIP-113 Pull Request](https://github.com/cardano-foundation/CIPs/pull/444).

### Feature ideas

Feature ideas and enhancement proposals are welcome! Since this implementation follows the CIP-113 standard, feature discussions should consider:

- **Standard-level features** — Discuss in the [CIP-113 Pull Request](https://github.com/cardano-foundation/CIPs/pull/444)
- **Implementation-specific features** — [Submit an issue](../../issues/new) in this repository

We expect a description of:

* Why you (or the user) need/want something (e.g. problem, challenge, pain, benefit)
* What this is roughly about (e.g. description of a new validator or API endpoint)

We do NOT require a detailed technical description, but are much more interested in *why* a feature is needed. This also helps in understanding the relevance and ultimately the priority of such an item.

## Making changes

When contributing code, it helps to have discussed the rationale and (ideally) how something is implemented in a feature idea or bug ticket beforehand.

### Building & Testing

**Prerequisites:**

- [Aiken](https://aiken-lang.org/installation-instructions) v1.1.23 (pinned in `aiken.toml`)

**Format check:**

```bash
aiken fmt --check
```

**Run tests:**

```bash
aiken check -D
```

The `with_assertions` environment additionally compiles runtime assertions that
the default environment no-ops (see the comment on the corresponding step in
`.github/workflows/continuous-integration.yml`):

```bash
aiken check -D --env with_assertions
```

**Build** (regenerates `plutus.json`; run last, since it reads the current source):

```bash
aiken build
```

Run `aiken fmt` (without `--check`) to apply formatting before committing.
Make sure **all** tests are successful in both environments before submitting
a pull request — this is the same sequence continuous integration runs.

### Coding standards

**Aiken code:** Follow [Aiken best practices](https://aiken-lang.org) and conventions. Run `aiken fmt` before committing.

More importantly, check that the coding style you find is consistent, and report or fix any inconsistencies by filing an issue or a pull request. File a separate pull request for style changes.

In general regarding code style, take a look at the existing sources and make your code consistent with them.

### Cross-repository changes

Changes that span on-chain and off-chain (e.g. a new module or a protocol change affecting transaction building) may require coordinated pull requests in both:

- This repository — on-chain validators and core framework
- The [platform repository](https://github.com/cardano-foundation/cip113-programmable-tokens-platform) — off-chain code and module implementations

Please reference related pull requests in both descriptions so reviewers have the full picture.

### Creating a pull request

Thank you for contributing your changes by opening a pull request! To get something merged, we usually require:

+ Description of the changes — if your commit messages are great, this is less important
+ Quality of changes is ensured — through new or updated automated tests
+ Change is related to an issue, feature (idea), or bug report — ideally discussed beforehand
+ Well-scoped — we prefer multiple PRs rather than one big one

**Note:** As the CIP-113 standard itself continues to evolve, a change here can require coordinating with the standard's own discussion thread — see [Communication channels](#communication-channels) above.
