# Contributing

## Adding a new provider

Create `providers/<name>/` containing at minimum:

1. **`OWNERS`** - at least one approver. Owners review all PRs for the sub-folder
   and are reachable in llm-d Slack `#sig-installation`.
2. **`README.md`** - the entry point. It must state:
   * Supported machine shapes / accelerators and version floors.
   * The provisioning methods offered (docs, scripts, IaC, AI skill) and where they
     live. External links (Terraform registry, vendor repo) are acceptable; this
     repository is the discovery entry point.
   * The conformance profiles the tooling is qualified against, with evidence
     (see [GOVERNANCE.md](GOVERNANCE.md), "Quality bar").
3. **At least one provisioning method** that produces a cluster passing
   `conformance/bin/llmd-infra-check --profile <claimed profile> --microtests`.

Use [`providers/gke/`](providers/gke/) as the reference layout:

```
providers/<name>/
  OWNERS
  README.md                 # entry point: methods, coverage matrix, qualification
  docs/                     # guided documentation
  scripts/                  # deterministic provisioning scripts / IaC
  skills/                   # AI skills (optional)
```

## Contributing conformance checks

Checks live under `conformance/checks/<scope>/` where `<scope>` is `common` or a
provider name. Each check is a self-contained executable script with a metadata
header; see [conformance/README.md](conformance/README.md#check-contract) for the
contract. Provider-specific checks are reviewed by the provider's owners plus one
root maintainer (the framework contract must stay portable to core llm-d).

New dimension keys or values must be proposed to the llm-d maintainers first
(the vocabulary is shared with guides, CI, and benchmarking), then added to
[conformance/dimensions.yaml](conformance/dimensions.yaml).

## Style

* Shell scripts: `bash`, `set -euo pipefail`, pass `shellcheck`.
* Scripts that create cloud resources must print what they are about to create and
  the target project/region before doing it, and must be idempotent or fail fast
  with a clear message on conflict.
* Kubernetes manifests: plain YAML, no templating unless necessary; parameterize
  via environment variables consumed by a wrapper script.

## Developer Certificate of Origin

Contributions require a DCO sign-off (`git commit -s`), matching the llm-d project
policy.
