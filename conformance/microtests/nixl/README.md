# NIXL transfer micro-test

Pod-to-pod [NIXL](https://github.com/ai-dynamo/nixl) benchmark validating the
exact KV-cache transfer path llm-d prefill/decode disaggregation uses: NIXL over
UCX, VRAM to VRAM, one-sided RDMA READ (the decode pod pulls KV blocks from the
prefill pod's GPU memory).

NCCL passing does not imply NIXL passing: NCCL uses the gIB plugin on GKE while
NIXL uses UCX verbs directly, so each exercises a different RDMA consumer stack.
llm-d needs both.

## Topology

```
llmd-nixl-etcd (coordination, port 2379)
llmd-nixlbench-1  --\
                     >-- both ranks join via etcd; rank 0 = target, rank 1 = initiator
llmd-nixlbench-2  --/     (pods forced onto distinct nodes via anti-affinity)
```

## Image

No official nixlbench image is published. Build one:

```bash
git clone https://github.com/ai-dynamo/nixl && cd nixl
./benchmark/nixlbench/contrib/build.sh   # produces nixlbench:latest
# push to a registry reachable from the cluster, then:
export LLMD_NIXLBENCH_IMAGE=<registry>/nixlbench:<tag>
```

The check SKIPs with instructions when `LLMD_NIXLBENCH_IMAGE` is unset.

## Pass criteria and diagnostics

* Both ranks exit 0 with `--check_consistency` enabled.
* Optional bandwidth floor via `LLMD_NIXL_MIN_BW_GBPS` (unset = report-only,
  because healthy figures vary strongly with block size, NIC count per pod, and
  machine shape).
* If throughput is far below the fabric line rate, or transfers fail with
  `NIXL_ERR_REMOTE_DISCONNECT`, re-run with `UCX_PROTO_INFO=y` in the pod env and
  inspect which transports UCX selected: `rc_mlx5`/GPUDirect paths are healthy;
  `tcp` means RDMA fallback. On RoCE fabrics `UCX_IB_ADDR_TYPE=eth` is the most
  common missing setting; on GKE the manifests already set
  `UCX_IB_ROCE_REACHABILITY_MODE=all`.

## Variants

`nixlbench-gke-dra.yaml` targets `infra_provider=gke dra=gpu-nic` (DRA claims).
For the multi-networking path (`dra=none`), attach the pods to `rdma-0..7` via
`networking.gke.io/interfaces` annotations instead of resource claims and request
all 8 GPUs per pod; contributions welcome.
