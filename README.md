# llm-d-infra-providers

Community-owned infrastructure provisioning tooling and guides for preparing Kubernetes clusters to run [llm-d](https://github.com/llm-d/llm-d).

> **Status: proof of concept.** This repository implements the pilot phase of the
> *Community-Driven Infrastructure Provisioning & Conformance Strategy for llm-d*
> proposal, with GKE as the first provider.

## Scope

Setting up an environment for llm-d involves two distinct operational layers:

1. **Infrastructure provisioning** - preparing a Kubernetes cluster with hardware
   accelerators, high-performance networking (RDMA/RoCE/InfiniBand), device drivers,
   DRA drivers, and Gateway API prerequisites, so the cluster is ready to host llm-d.
2. **Stack installation** - deploying the llm-d software components, owned and
   documented by the [llm-d well-lit path guides](https://github.com/llm-d/llm-d/tree/main/guides).

This repository owns layer 1. Core llm-d owns layer 2 and does not host per-provider
provisioning tooling.

## Repository layout

```
providers/            Per-provider provisioning tooling and docs (community owned)
  gke/                Google Kubernetes Engine (pilot provider)
  aks/                Azure Kubernetes Service
  digitalocean/       DigitalOcean Kubernetes
  minikube/           minikube (single-host development)
  openshift/          OpenShift Container Platform
  openshift-aws/      OpenShift on AWS
gateway-providers/    Gateway control-plane provisioning notes (GKE Gateway, Istio, ...)
conformance/          Infra Conformance Suite: dimension-labeled executable checks
```

## Ownership model

This repository is community owned:

* Each `providers/<name>/` sub-folder has its own `OWNERS` file. Provider owners
  review and approve PRs touching their sub-folder.
* Root maintainers curate repository structure, the conformance framework, and
  cross-provider consistency. They do not gate provider-internal changes.

See [GOVERNANCE.md](GOVERNANCE.md).

## Provisioning methods

Providers may offer any combination of the following methods. All methods must
converge on the same end state: a cluster that passes the conformance suite for the
dimension profiles the provider claims to support.

| Method | Properties |
|---|---|
| Guided documentation | Transparent, easy to follow manually; prone to bit rot |
| Deterministic scripts / IaC (Terraform, shell) | Reproducible, automatable; less adaptable |
| AI skills | Interactive, adaptable to context; requires anchoring in docs to avoid drift |

## Conformance

The [Infra Conformance Suite](conformance/README.md) is the qualification bar for
everything in `providers/`. It is a collection of executable checks, each labeled with
the [dimensions](conformance/dimensions.yaml) it applies to (`infra_provider`,
`accelerator`, `rdma`, `dra`, `router_mode`, `gateway_provider`, ...). Given a target
dimension profile, the runner filters the applicable checks and executes them against
the current kubeconfig context:

```bash
conformance/bin/llmd-infra-check --profile conformance/profiles/gke-pd-disaggregation.yaml
# add active fabric tests (creates pods on GPU nodes):
conformance/bin/llmd-infra-check --profile conformance/profiles/gke-pd-disaggregation.yaml --microtests
```

Static checks verify node readiness, accelerator exposure (device plugin or DRA
ResourceSlices), RDMA network attachment, and Gateway API/Inference Extension CRDs.
Micro-tests actively validate the fabric: a two-node NCCL collective test and a
pod-to-pod NIXL transfer benchmark.

> Per the proposal, the conformance suite's target home is the core llm-d repository
> (`infrastructure/conformance/`), so that discovery and consistency checking are
> centralized. It is hosted here during the pilot; the runner and check contract are
> designed to move without modification.

## Provider status

| Provider | Owners | Methods | Qualified profiles |
|---|---|---|---|
| [gke](providers/gke/) | see `providers/gke/OWNERS` | docs, scripts, AI skill | `gke-optimized-baseline`, `gke-pd-disaggregation`, `gke-wide-ep-lws`, `gke-a4x-pd-disaggregation` |
| [aks](providers/aks/) | needed | docs (migrated from llm-d) | - |
| [digitalocean](providers/digitalocean/) | needed | docs (migrated from llm-d) | - |
| [minikube](providers/minikube/) | needed | docs (migrated from llm-d) | - |
| [openshift](providers/openshift/) | needed | docs (migrated from llm-d) | - |
| [openshift-aws](providers/openshift-aws/) | needed | docs (migrated from llm-d) | - |

"Qualified profiles" lists the conformance profiles the provider's tooling has been
validated against. Providers without owners carry documentation migrated from
`llm-d/docs/infrastructure` as-is and need a maintainer to progress.

## Adding a provider

See [CONTRIBUTING.md](CONTRIBUTING.md). Summary: create `providers/<name>/` with an
`OWNERS` file, a `README.md` entry point, at least one provisioning method, and at
least one conformance profile your tooling passes. Link out to externally hosted
tooling (Terraform registries, vendor repos) at your discretion; this repository is
the discovery entry point, not necessarily the code host.
