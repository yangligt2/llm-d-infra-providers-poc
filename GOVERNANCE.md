# Governance

## Model

`llm-d-infra-providers` is community owned. It deliberately separates two review
scopes so that core llm-d maintainers are not a bottleneck for provider-specific
changes, and provider owners are not blocked on each other.

### Provider sub-folders

* Each `providers/<name>/` and each `gateway-providers/<name>` document has an
  `OWNERS` file listing its approvers.
* Provider owners have full review and approval authority over PRs that only touch
  their sub-folder.
* A provider must list at least one documented maintainer who responds to GitHub
  issues and is reachable in the llm-d Slack channel `#sig-installation`.
* A provider whose owners are unresponsive for an extended period is marked
  "owners needed" in the root README; its content remains but is flagged as
  unmaintained.

### Root

Root maintainers (root `OWNERS`) own:

* Repository structure and cross-provider consistency.
* The conformance framework under `conformance/` (runner, check contract,
  dimension vocabulary) - jointly with llm-d maintainers, since the suite's target
  home is the core llm-d repository.
* Arbitration when a change spans multiple providers.

Root maintainers do not gate provider-internal changes.

## Quality bar

Provider tooling must be qualified against the Infra Conformance Suite:

1. Every provisioning method a provider ships must state which conformance
   [profiles](conformance/profiles/) it produces.
2. A claim of support for a profile requires a passing run of
   `llmd-infra-check --profile <profile> --microtests` on a cluster provisioned by
   that method. Record the evidence (runner output, date, cluster shape) in the
   provider's README or a `qualification/` sub-folder.
3. Changes to provisioning steps that affect a qualified profile require
   re-qualification before the claim is kept.

## Relationship to core llm-d

* Core llm-d does not host per-provider provisioning tooling or guides; this
  repository is the entry point for that content.
* Core llm-d hosts the conformance suite as the source of truth (pilot phase:
  hosted here, see [conformance/README.md](conformance/README.md)). Providers
  contribute checks for their platform via PRs labeled with the applicable
  dimensions.
* The dimension vocabulary ([conformance/dimensions.yaml](conformance/dimensions.yaml))
  follows the llm-d guides' declarative dimensions; changes to the vocabulary are
  coordinated with llm-d maintainers so infrastructure conformance, guides, the CI
  test grid, and benchmarking stay aligned on the same axes.
