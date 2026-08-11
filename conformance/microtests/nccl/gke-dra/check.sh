#!/usr/bin/env bash
# conformance-check
# id: microtest.nccl.gke-dra
# description: NCCL over DRA/DRANET-allocated GPU+NIC pairs (single-node claim test, then two-node fabric test)
# dimensions: infra_provider=gke accelerator=gpu rdma=roce dra=gpu-nic
# type: microtest
#
# Stage 1: one 8-GPU pod with eight PCIe-aligned (gpu.nvidia.com,
#          mrdma.google.com) claims runs all_reduce_perf. Proves DRA allocation
#          and NCCL bring-up (NVLink path).
# Stage 2: two such pods on distinct nodes run all_gather over the RoCE fabric
#          via Google's run_nccl_tests.sh. Proves inter-node GPUDirect RDMA.
#
# Tunables:
#   LLMD_NCCL_NAMESPACE        namespace for test pods   (default llmd-conformance)
#   LLMD_NCCL_MIN_BUSBW_GBPS   stage-2 peak busbw floor  (default 100)
#   LLMD_NCCL_TIMEOUT_SECONDS  per-stage timeout         (default 900)
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
NS="${LLMD_NCCL_NAMESPACE:-llmd-conformance}"
MIN_BUSBW="${LLMD_NCCL_MIN_BUSBW_GBPS:-100}"
TIMEOUT="${LLMD_NCCL_TIMEOUT_SECONDS:-900}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$LLMD_CONFORMANCE_ROOT/microtests/common/gke-rdma-template.yaml"

cleanup() {
  k delete -f "$DIR/nccl-two-node.yaml" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  k delete -f "$DIR/nccl-single-node.yaml" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  k delete -f "$TEMPLATE" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

k create namespace "$NS" --dry-run=client -o yaml | k apply -f - >/dev/null
k apply -f "$TEMPLATE" -n "$NS" >/dev/null

# ---- Stage 1: single-node claim allocation + NCCL bring-up -------------------
echo "stage 1: single-node all_reduce with 8 DRA GPU+NIC claims"
k apply -f "$DIR/nccl-single-node.yaml" -n "$NS" >/dev/null
deadline=$(( $(date +%s) + TIMEOUT ))
phase=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  phase="$(k get pod llmd-nccl-dra-single -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "$phase" in Succeeded|Failed) break ;; esac
  sleep 10
done
if [ "$phase" != "Succeeded" ]; then
  k logs llmd-nccl-dra-single -n "$NS" --tail=30 2>/dev/null || true
  k describe pod llmd-nccl-dra-single -n "$NS" 2>/dev/null | tail -n 15 || true
  fail "stage 1 pod ended in phase '${phase:-Pending}' (DRA claims not allocating, or NCCL bring-up failure)"
fi
k logs llmd-nccl-dra-single -n "$NS" 2>/dev/null | grep -E 'Avg bus bandwidth' || true
echo "stage 1 passed: claims allocated, all_reduce completed"
k delete -f "$DIR/nccl-single-node.yaml" -n "$NS" --ignore-not-found >/dev/null

# ---- Stage 2: two-node fabric test -------------------------------------------
gpu_nodes="$(k get nodes -l cloud.google.com/gke-accelerator --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ "$gpu_nodes" -lt 2 ]; then
  skip "stage 1 passed; stage 2 needs >= 2 accelerator nodes, found $gpu_nodes"
fi

echo "stage 2: two-node all_gather over the RoCE fabric"
k apply -f "$DIR/nccl-two-node.yaml" -n "$NS" >/dev/null
k wait --for=condition=Ready pod/llmd-nccl-dra-test-host-1 pod/llmd-nccl-dra-test-host-2 \
  -n "$NS" --timeout="${TIMEOUT}s" \
  || fail "stage 2 pods did not become Ready (check DRA capacity on two nodes)"

if ! k exec -n "$NS" llmd-nccl-dra-test-host-1 -- test -x /usr/local/gib/scripts/run_nccl_tests.sh; then
  skip "stage 1 passed; stage 2 needs the gIB launcher on the nodes: apply gpudirect-rdma/nccl-rdma-installer.yaml from GoogleCloudPlatform/container-engine-accelerators and re-run"
fi

out="$(k exec -n "$NS" llmd-nccl-dra-test-host-1 -- \
  /usr/local/gib/scripts/run_nccl_tests.sh -t all_gather -b 1K -e 8G \
  llmd-nccl-dra-host-1 llmd-nccl-dra-host-2 2>&1)" \
  || { echo "$out" | tail -n 40; fail "stage 2 NCCL execution failed"; }

echo "$out" | grep -E 'Avg bus bandwidth|Using network' || true
peak="$(echo "$out" | awk '$1 ~ /^[0-9]+$/ && NF > 8 { if ($8 + 0 > max) max = $8 + 0 } END { printf "%.1f", max }')"
wrong="$(echo "$out" | awk '$1 ~ /^[0-9]+$/ && NF > 8 { s += $9 + 0 } END { print s + 0 }')"

[ "$wrong" = "0" ] || fail "NCCL reported $wrong wrong values (data corruption on the fabric)"
awk -v p="$peak" -v m="$MIN_BUSBW" 'BEGIN { exit !(p + 0 >= m + 0) }' \
  || fail "peak bus bandwidth ${peak} GB/s < floor ${MIN_BUSBW} GB/s (likely TCP fallback or fabric misconfiguration)"
pass "stage 1 + stage 2 passed; peak bus bandwidth ${peak} GB/s (floor ${MIN_BUSBW} GB/s)"
