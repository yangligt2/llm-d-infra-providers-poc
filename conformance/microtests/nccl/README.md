# NCCL fabric micro-tests

Active two-node NCCL collective tests validating the inter-node RDMA fabric
before llm-d deployment. NCCL is the collective transport used by multi-node
llm-d topologies (wide expert parallelism, multi-host tensor parallelism);
a broken or TCP-falling-back fabric surfaces here in minutes instead of at
model-server start.

| Variant | Dimension space | What it runs |
|---|---|---|
| [gke-multinet](gke-multinet/) | `infra_provider=gke rdma=roce dra=none` | Google's two-pod `run_nccl_tests.sh` (all_gather, 1K-8G) over `rdma-0..7` multi-network annotations + gIB. Skips on GB200 shapes |
| [gke-a4x](gke-a4x/) | `infra_provider=gke rdma=roce\|ib dra=none\|nic` | A4X/GB200 shape: 4 GPUs + `rdma-0..3` per node, arm64 image, two-node NVIDIA ComputeDomain (IMEX) claim. Skips when no GB200 nodes |
| [gke-dra](gke-dra/) | `infra_provider=gke rdma=roce dra=gpu-nic` | Stage 1: single-node all_reduce with 8 PCIe-aligned DRA GPU+NIC claims. Stage 2: two-pod all_gather with DRA claims |

## Pass criteria

* `#wrong` (NCCL correctness column, enabled via `-c 1` in Google's launcher) is 0.
* Peak bus bandwidth >= `LLMD_NCCL_MIN_BUSBW_GBPS` (default 100 GB/s). The floor
  detects order-of-magnitude failures (TCP fallback, missing GPUDirect), not mild
  degradation.

Reference healthy peaks for eyeball comparison (2-node all_gather): A3 Ultra
(8x H200, 8x400G) ~337 GB/s busbw and A4 (8x B200) ~377 GB/s busbw (Google
published values); A4X (4x GB200, 4x400G) 189.3 GB/s busbw measured by this
suite on a live cluster (~95% of line rate, see
[../../examples/](../../examples/)). Values below ~85% of the reference for
your shape warrant investigation
(NIC affinity, `NCCL_TESTS_SPLIT_MASK`, congested Spot fabric) even though the
conformance floor passes.

## Notes

* NCCL environment comes from `/usr/local/gib/scripts/set_nccl_env.sh` inside the
  diagnostic image. Do not overlay manual `NCCL_*` settings; Google's gIB config
  checker rejects several combinations, and guidance changes across gIB versions.
* Test pods request all 8 GPUs and all RDMA interfaces of each node (a GKE
  requirement: RDMA NICs are not shareable across pods on a node).
* Adding a provider variant: create `<provider-variant>/check.sh` with the
  standard header (see [../../README.md](../../README.md#check-contract)) plus the
  manifests it applies. Keep pod/service names prefixed `llmd-` and confined to
  the `llmd-conformance` namespace.
