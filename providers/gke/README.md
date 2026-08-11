# GKE infrastructure provider for llm-d

Provisioning tooling and documentation for preparing Google Kubernetes Engine
clusters to run llm-d. This is the pilot provider for the llm-d-infra-providers
governance model.

## Supported configurations

Tested machine shapes (per the llm-d GKE guide): A3, A3 Ultra, A4, A4X, ct5p,
ct5lp, ct6e. GKE 1.33.4+; specific features carry higher floors (managed DRANET:
1.34.1-gke.1829001+, GPU DRA: 1.35+, RDMA: 1.32.2-gke.1475000+ for A4).

## Networking paths

Pick exactly ONE per cluster (the DRANET driver and Device-type `Network`
resources manage the same NICs and must not be combined):

| Path | Dimension profile | Target guide | Provision with |
|---|---|---|---|
| A: GPU DRA + managed DRANET | `rdma=roce dra=gpu-nic` | pd-disaggregation (`gke` overlay) | [scripts/provision-dra-dranet.sh](scripts/provision-dra-dranet.sh) |
| B: multi-networking + gIB | `rdma=roce dra=none` | wide-ep-lws (`gke` overlay) | [scripts/provision-multinet-gib.sh](scripts/provision-multinet-gib.sh) |
| A4X (GB200) | `rdma=ib dra=nic` | pd-disaggregation (`gke/a4x` overlay) | AI Hypercomputer docs (script TODO) |
| No RDMA (aggregated serving) | `rdma=none dra=none` | optimized-baseline and other single-node guides | any standard GPU cluster |

Gateway mode additionally requires
[scripts/gateway-prereqs.sh](scripts/gateway-prereqs.sh) (Gateway API enablement
+ proxy-only subnet).

## Provisioning methods

1. **Guided documentation** - [docs/README.md](docs/README.md) (migrated from
   `llm-d/docs/infrastructure/providers/gke`).
2. **Deterministic scripts** - [scripts/](scripts/). Idempotent where possible;
   announce resources and require confirmation before creating billable
   capacity (`ASSUME_YES=1` for CI).
3. **AI skill** - [skills/create-gke-infra-llm-d/](skills/create-gke-infra-llm-d/),
   an interactive agent skill with IAM preflight, guardrails, and validation,
   anchored in the same sources of truth as the scripts.

## Qualification against the conformance suite

| Profile | Status |
|---|---|
| `gke-optimized-baseline` | static checks validated against a live GKE cluster (2026-08-10); gateway checks require `gateway-prereqs.sh` |
| `gke-pd-disaggregation` | check selection validated; full pass pending a Path A cluster run |
| `gke-wide-ep-lws` | check selection validated; full pass pending a Path B cluster run |
| `gke-a4x-pd-disaggregation` | static checks validated against a live A4X cluster (2026-08-10); DRANET slice publication flagged correctly |

Captured evidence from the 2026-08-10 runs:
[conformance/examples/gke-gpu-standalone-pass.txt](../../conformance/examples/gke-gpu-standalone-pass.txt)
(see [conformance/examples/](../../conformance/examples/) for how to read it).

Run:

```bash
conformance/bin/llmd-infra-check --profile conformance/profiles/gke-pd-disaggregation.yaml --microtests
```

## Known issues to surface at deploy time

These are caused by infrastructure choices but bite when llm-d is deployed:

* **gIB 1.10+ required for vLLM 0.11.0+** (NCCL 2.27). Path B only; use at least
  the installer DaemonSet from container-engine-accelerators PR #511.
* **NCCL tuner crash when gIB is installed** unless `NCCL_TUNER_PLUGIN=none` and
  `NCCL_NET_PLUGIN=""` (llm-d GKE overlays apply this via
  `disable-gke-nccl-tuner-patch`).
* **`LD_LIBRARY_PATH` must include `/usr/local/nvidia/lib64`** in custom vLLM
  images ("Failed to infer device type" otherwise).
* **DeepEP/NVSHMEM needs GPU-initiated RDMA**: `privileged: true` or
  `PeerMappingOverride=1`; set `NVSHMEM_DISABLE_GDRCOPY=1`.
* **Topology placement**: use pod affinity on `cloud.google.com/gce-topology-block`;
  for scale, Topology Aware Scheduling with Kueue + LeaderWorkerSet.

Details and workarounds: [docs/README.md](docs/README.md#known-issues).
