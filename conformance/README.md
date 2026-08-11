# llm-d Infra Conformance Suite

Executable, dimension-labeled checks that answer one question: **is this cluster
ready to deploy llm-d for a given configuration?**

> **Pilot location.** Per the community proposal, the canonical home of this
> suite is the core llm-d repository (`infrastructure/conformance/`), keeping
> discovery and consistency checking centralized while providers contribute the
> checks. It lives here during the llm-d-infra-providers pilot; the runner and
> check contract have no dependency on this repository's layout beyond the
> `conformance/` subtree and can be moved (or wrapped by a future
> `llm-d-ctl check-infra`) without modification.

## Concepts

* **Dimension** - one axis of an llm-d configuration (`infra_provider`,
  `accelerator`, `rdma`, `dra`, `router_mode`, `gateway_provider`,
  `model_server`). The vocabulary in [dimensions.yaml](dimensions.yaml) mirrors
  the declarative dimensions of the llm-d well-lit path guides, so conformance,
  docs, CI, and benchmarks share one coordinate system.
* **Profile** - one value per dimension, describing the target deployment
  (see [profiles/](profiles/)). Profiles correspond to guide + platform
  combinations, e.g. `gke-pd-disaggregation`.
* **Check** - a self-contained executable labeled with dimension constraints.
  The runner selects a check when every constraint matches the profile;
  unconstrained dimensions match anything.
* **Micro-test** - a check that creates workloads (pods) to actively exercise
  the fabric: two-node [NCCL collectives](microtests/nccl/) and pod-to-pod
  [NIXL transfers](microtests/nixl/). Only run with `--microtests`.

## Usage

```bash
# Static readiness checks for P/D disaggregation on GKE (DRA + DRANET path):
conformance/bin/llmd-infra-check --profile conformance/profiles/gke-pd-disaggregation.yaml

# Include active fabric micro-tests (creates pods in namespace llmd-conformance):
conformance/bin/llmd-infra-check --profile conformance/profiles/gke-pd-disaggregation.yaml --microtests

# Ad-hoc dimension space without a profile file:
conformance/bin/llmd-infra-check \
  --dim infra_provider=gke --dim accelerator=gpu --dim rdma=roce \
  --dim dra=gpu-nic --dim router_mode=standalone

# See what would run:
conformance/bin/llmd-infra-check --profile ... --list
```

Sample output from real clusters, including how to read the evidence lines and
failure diagnostics: [examples/](examples/).

The runner targets the current kubeconfig context. Static checks are read-only.
Micro-tests create and delete pods/services/claims in the `llmd-conformance`
namespace (override with `LLMD_NCCL_NAMESPACE` / `LLMD_NIXL_NAMESPACE`) and
schedule onto GPU nodes; do not run them against a cluster serving production
traffic.

Exit code: 0 when every selected check passes (skips do not fail the run),
1 otherwise.

## Layout

```
bin/llmd-infra-check      runner
lib/common.sh             helpers sourced by every check
dimensions.yaml           dimension vocabulary (shared with llm-d guides)
profiles/                 dimension profiles, one per guide+platform target
examples/                 captured runs from real clusters (sanitized)
checks/common/            provider-agnostic static checks
checks/<provider>/        provider-contributed static checks
microtests/nccl/          two-node NCCL fabric tests
microtests/nixl/          pod-to-pod NIXL transfer test
microtests/common/        shared manifests (e.g. GKE DRA claim template)
```

## Check contract

A check is an executable `*.sh` file under `checks/` or `microtests/` whose
first lines declare metadata:

```bash
#!/usr/bin/env bash
# conformance-check
# id: gke.dranet-devices
# description: DRANET publishes mrdma.google.com NICs ...
# dimensions: infra_provider=gke rdma=roce dra=gpu-nic
# type: microtest        # omit for static checks
```

* `dimensions:` tokens are `key=value1|value2` constraints, ANDed together;
  a check with no `dimensions:` line applies to every profile.
* Exit 0 = PASS, 77 = SKIP (runtime-determined inapplicability, with a message
  explaining what is missing), anything else = FAIL.
* The runner exports `LLMD_CONFORMANCE_ROOT` and one `LLMD_DIM_<KEY>` per
  profile dimension. Source `lib/common.sh` for `pass`/`fail`/`skip`/`dim`
  helpers.
* Static checks must be read-only against the cluster. Micro-tests must confine
  created objects to the conformance namespace, prefix names with `llmd-`, and
  delete everything they created on exit (including on failure paths).

## What is covered today

| Check | Dimensions |
|---|---|
| `cluster.api-reachable`, `cluster.kubernetes-version`, `cluster.nodes-ready` | all |
| `accelerator.gpu.device-plugin` | `accelerator=gpu dra=none\|nic` |
| `accelerator.gpu.dra-resourceslices` | `accelerator=gpu dra=gpu\|gpu-nic` |
| `gateway.api-crds`, `gateway.inference-extension-crds` | `router_mode=gateway` |
| `gateway.controller-accepted` | `router_mode=gateway gateway_provider=*` |
| `gke.accelerator-node-labels` | `infra_provider=gke accelerator=gpu` |
| `gke.rdma-topology-labels` | `infra_provider=gke rdma=roce\|ib` |
| `gke.dranet-devices` | `infra_provider=gke rdma=roce\|ib dra=nic\|gpu-nic` |
| `gke.multinet-rdma-networks`, `gke.gib-installer` | `infra_provider=gke rdma=roce dra=none` |
| `gke.gateway-classes` | `infra_provider=gke gateway_provider=gke` |
| `microtest.nccl.gke-multinet` | `infra_provider=gke rdma=roce dra=none` |
| `microtest.nccl.gke-a4x` | `infra_provider=gke rdma=roce\|ib dra=none\|nic` |
| `microtest.nccl.gke-dra` | `infra_provider=gke rdma=roce dra=gpu-nic` |
| `microtest.nixl.gke-dra` | `infra_provider=gke rdma=roce dra=gpu-nic` |

Known gaps (contributions welcome): TPU/AMD/XPU accelerator checks, InfiniBand
(`rdma=ib`) checks for on-prem/AKS, EKS/EFA, NIXL micro-test variants for the
multi-networking and A4X shapes, an A4X NCCL variant for DRANET-claims clusters
(the current one assumes `rdma-0..3` multi-network annotations), and deeper
node health integration (NVIDIA DCGM diagnostics, Google cluster-health-scanner)
as optional micro-tests.
