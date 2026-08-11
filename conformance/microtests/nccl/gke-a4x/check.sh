#!/usr/bin/env bash
# conformance-check
# id: microtest.nccl.gke-a4x
# description: Two-node NCCL all_gather on A4X (GB200) over gIB/RoCE with an IMEX compute domain
# dimensions: infra_provider=gke accelerator=gpu rdma=roce|ib dra=none|nic
# type: microtest
#
# A4X variant of the two-node NCCL fabric test: 4 GPUs + 4 RDMA networks
# (rdma-0..rdma-3) per node, arm64 diagnostic image, and a two-node NVIDIA
# ComputeDomain (IMEX channel via DRA) as required on GB200. Skips at runtime
# when the cluster has no nvidia-gb200 nodes, so it can share dimension spaces
# with the A3 Ultra / A4 variants.
#
# Tunables:
#   LLMD_NCCL_NAMESPACE        namespace for test pods   (default llmd-conformance)
#   LLMD_NCCL_MIN_BUSBW_GBPS   pass floor for peak busbw (default 100)
#   LLMD_NCCL_TIMEOUT_SECONDS  pod-ready + run timeout   (default 900)
#
# The floor catches order-of-magnitude failures (TCP fallback, missing
# GPUDirect). Measured healthy reference (2 nodes, all_gather, 8 GiB): ~189
# GB/s busbw, ~95% of the 4x400G per-node line rate.
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
NS="${LLMD_NCCL_NAMESPACE:-llmd-conformance}"
MIN_BUSBW="${LLMD_NCCL_MIN_BUSBW_GBPS:-100}"
TIMEOUT="${LLMD_NCCL_TIMEOUT_SECONDS:-900}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$DIR/nccl-test.yaml"

gb200_nodes="$(k get nodes -l cloud.google.com/gke-accelerator=nvidia-gb200 --no-headers 2>/dev/null | wc -l | tr -d ' ')"
[ "$gb200_nodes" -gt 0 ] || skip "no nvidia-gb200 nodes (A4X variant; use microtest.nccl.gke-multinet or .gke-dra for other shapes)"
[ "$gb200_nodes" -ge 2 ] || skip "needs >= 2 GB200 nodes, found $gb200_nodes"

k get crd computedomains.resource.nvidia.com >/dev/null 2>&1 \
  || fail "ComputeDomain CRD missing (install the NVIDIA DRA driver with computeDomains enabled; required on GB200)"

cleanup() { k delete -f "$MANIFEST" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT

k create namespace "$NS" --dry-run=client -o yaml | k apply -f - >/dev/null
k apply -f "$MANIFEST" -n "$NS" >/dev/null
echo "created 2 NCCL test pods (4 GPUs each) + ComputeDomain in namespace $NS"

k wait --for=condition=Ready "pod/llmd-nccl-test-host-1" "pod/llmd-nccl-test-host-2" \
  -n "$NS" --timeout="${TIMEOUT}s" \
  || fail "NCCL test pods did not become Ready (check GB200 capacity, rdma-0..3 networks, and ComputeDomain allocation)"

echo "running: run_nccl_tests.sh -t all_gather -b 1K -e 8G (gpus_per_node auto-detected; takes a few minutes)"
out="$(k exec -n "$NS" llmd-nccl-test-host-1 -- \
  /usr/local/gib/scripts/run_nccl_tests.sh -t all_gather -b 1K -e 8G \
  llmd-nccl-host-1 llmd-nccl-host-2 2>&1)" \
  || { echo "$out" | tail -n 40; fail "NCCL test execution failed"; }

echo "$out" | grep -E 'Avg bus bandwidth|Out of bounds' || true

# Result table columns (out-of-place): size count type redop root time algbw busbw #wrong ...
peak="$(echo "$out" | awk '$1 ~ /^[0-9]+$/ && NF > 8 { if ($8 + 0 > max) max = $8 + 0 } END { printf "%.1f", max }')"
wrong="$(echo "$out" | awk '$1 ~ /^[0-9]+$/ && NF > 8 { s += $9 + 0 } END { print s + 0 }')"

[ "$wrong" = "0" ] || fail "NCCL reported $wrong wrong values (data corruption on the fabric)"
awk -v p="$peak" -v m="$MIN_BUSBW" 'BEGIN { exit !(p + 0 >= m + 0) }' \
  || fail "peak bus bandwidth ${peak} GB/s < floor ${MIN_BUSBW} GB/s (likely TCP fallback or fabric misconfiguration)"
pass "peak bus bandwidth ${peak} GB/s (floor ${MIN_BUSBW} GB/s), 0 wrong values, 2x4 GB200 ranks"
