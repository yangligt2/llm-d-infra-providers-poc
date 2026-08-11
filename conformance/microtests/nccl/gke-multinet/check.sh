#!/usr/bin/env bash
# conformance-check
# id: microtest.nccl.gke-multinet
# description: Two-node NCCL all_gather over gIB/RoCE reaches a sane bus bandwidth
# dimensions: infra_provider=gke accelerator=gpu rdma=roce dra=none
# type: microtest
#
# Creates two 8-GPU pods (one per node) wired to rdma-0..rdma-7 via GKE
# multi-networking annotations, runs Google's run_nccl_tests.sh (mpirun over ssh
# port 222 inside the diagnostic image), and asserts the peak bus bandwidth.
#
# Tunables:
#   LLMD_NCCL_NAMESPACE        namespace for test pods   (default llmd-conformance)
#   LLMD_NCCL_MIN_BUSBW_GBPS   pass floor for peak busbw (default 100)
#   LLMD_NCCL_TIMEOUT_SECONDS  pod-ready + run timeout   (default 900)
#
# The default floor of 100 GB/s is deliberately conservative: it catches fabric
# misconfiguration and TCP fallback (order-of-magnitude regressions), not mild
# degradation. Reference healthy peaks (Google, 2 nodes, all_gather):
# A3 Ultra / H200 ~337 GB/s busbw, A4 / B200 ~377 GB/s busbw.
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
NS="${LLMD_NCCL_NAMESPACE:-llmd-conformance}"
MIN_BUSBW="${LLMD_NCCL_MIN_BUSBW_GBPS:-100}"
TIMEOUT="${LLMD_NCCL_TIMEOUT_SECONDS:-900}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$DIR/nccl-test.yaml"

gpu_nodes="$(k get nodes -l cloud.google.com/gke-accelerator --no-headers 2>/dev/null | wc -l | tr -d ' ')"
[ "$gpu_nodes" -ge 2 ] || skip "needs >= 2 accelerator nodes, found $gpu_nodes"

cleanup() { k delete -f "$MANIFEST" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT

k create namespace "$NS" --dry-run=client -o yaml | k apply -f - >/dev/null
k apply -f "$MANIFEST" -n "$NS" >/dev/null
echo "created 2 NCCL test pods in namespace $NS"

k wait --for=condition=Ready "pod/llmd-nccl-test-host-1" "pod/llmd-nccl-test-host-2" \
  -n "$NS" --timeout="${TIMEOUT}s" \
  || fail "NCCL test pods did not become Ready (check GPU capacity and rdma-0..7 networks)"

echo "running: run_nccl_tests.sh -t all_gather -b 1K -e 8G (this takes a few minutes)"
out="$(k exec -n "$NS" llmd-nccl-test-host-1 -- \
  /usr/local/gib/scripts/run_nccl_tests.sh -t all_gather -b 1K -e 8G \
  llmd-nccl-host-1 llmd-nccl-host-2 2>&1)" \
  || { echo "$out" | tail -n 40; fail "NCCL test execution failed"; }

echo "$out" | grep -E 'Avg bus bandwidth|Using network' || true

# Result table columns (out-of-place): size count type redop root time algbw busbw #wrong ...
peak="$(echo "$out" | awk '$1 ~ /^[0-9]+$/ && NF > 8 { if ($8 + 0 > max) max = $8 + 0 } END { printf "%.1f", max }')"
wrong="$(echo "$out" | awk '$1 ~ /^[0-9]+$/ && NF > 8 { s += $9 + 0 } END { print s + 0 }')"

[ "$wrong" = "0" ] || fail "NCCL reported $wrong wrong values (data corruption on the fabric)"
awk -v p="$peak" -v m="$MIN_BUSBW" 'BEGIN { exit !(p + 0 >= m + 0) }' \
  || fail "peak bus bandwidth ${peak} GB/s < floor ${MIN_BUSBW} GB/s (likely TCP fallback or fabric misconfiguration)"
pass "peak bus bandwidth ${peak} GB/s (floor ${MIN_BUSBW} GB/s), 0 wrong values"
