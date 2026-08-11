#!/usr/bin/env bash
# conformance-check
# id: microtest.nixl.gke-dra
# description: Pod-to-pod NIXL (UCX) VRAM-to-VRAM transfer over RDMA completes with consistency checks
# dimensions: infra_provider=gke accelerator=gpu rdma=roce dra=gpu-nic
# type: microtest
#
# Validates the exact data path llm-d prefill/decode disaggregation uses:
# NIXL over UCX pulling GPU memory between two pods on distinct nodes, with
# DRA-allocated RDMA NICs. Requires a nixlbench container image:
#
#   LLMD_NIXLBENCH_IMAGE       (required) image containing nixlbench; build via
#                              benchmark/nixlbench/contrib/build.sh in
#                              github.com/ai-dynamo/nixl
#   LLMD_NIXL_NAMESPACE        namespace for test pods (default llmd-conformance)
#   LLMD_NIXL_MIN_BW_GBPS      optional bandwidth floor; unset = report only
#   LLMD_NIXL_TIMEOUT_SECONDS  timeout (default 900)
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
IMAGE="${LLMD_NIXLBENCH_IMAGE:-}"
[ -n "$IMAGE" ] || skip "set LLMD_NIXLBENCH_IMAGE to a nixlbench image (no official image is published; build with ai-dynamo/nixl benchmark/nixlbench/contrib/build.sh)"

NS="${LLMD_NIXL_NAMESPACE:-llmd-conformance}"
TIMEOUT="${LLMD_NIXL_TIMEOUT_SECONDS:-900}"
MIN_BW="${LLMD_NIXL_MIN_BW_GBPS:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$LLMD_CONFORMANCE_ROOT/microtests/common/gke-rdma-template.yaml"

gpu_nodes="$(k get nodes -l cloud.google.com/gke-accelerator --no-headers 2>/dev/null | wc -l | tr -d ' ')"
[ "$gpu_nodes" -ge 2 ] || skip "needs >= 2 accelerator nodes, found $gpu_nodes"

rendered="$(mktemp)"
sed "s|REPLACE_NIXLBENCH_IMAGE|$IMAGE|g" "$DIR/nixlbench-gke-dra.yaml" > "$rendered"

cleanup() {
  k delete -f "$rendered" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  k delete -f "$DIR/etcd.yaml" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  k delete -f "$TEMPLATE" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  rm -f "$rendered"
}
trap cleanup EXIT

k create namespace "$NS" --dry-run=client -o yaml | k apply -f - >/dev/null
k apply -f "$TEMPLATE" -n "$NS" >/dev/null
k apply -f "$DIR/etcd.yaml" -n "$NS" >/dev/null
k wait --for=condition=Ready pod/llmd-nixl-etcd -n "$NS" --timeout=120s >/dev/null \
  || fail "etcd coordination pod did not become Ready"

k apply -f "$rendered" -n "$NS" >/dev/null
echo "created 2 nixlbench pods (image $IMAGE); both ranks coordinate via etcd"

deadline=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  p1="$(k get pod llmd-nixlbench-1 -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  p2="$(k get pod llmd-nixlbench-2 -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "$p1/$p2" in
    Succeeded/Succeeded) break ;;
    Failed/*|*/Failed) break ;;
  esac
  sleep 10
done

for pod in llmd-nixlbench-1 llmd-nixlbench-2; do
  phase="$(k get pod "$pod" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [ "$phase" != "Succeeded" ]; then
    echo "--- logs $pod (phase ${phase:-Pending}) ---"
    k logs "$pod" -n "$NS" --tail=40 2>/dev/null || true
    fail "nixlbench pod $pod ended in phase '${phase:-Pending}' (UCX transport failure or claims not allocating; retry with UCX_PROTO_INFO=y for transport diagnostics)"
  fi
done

logs="$(k logs llmd-nixlbench-2 -n "$NS" 2>/dev/null || true)"
echo "$logs" | tail -n 25

# Report the highest bandwidth figure nixlbench printed (GB/s column).
peak="$(echo "$logs" | grep -oE '[0-9]+\.[0-9]+' | sort -g | tail -n 1 || true)"
if [ -n "$MIN_BW" ] && [ -n "$peak" ]; then
  awk -v p="$peak" -v m="$MIN_BW" 'BEGIN { exit !(p + 0 >= m + 0) }' \
    || fail "peak reported figure ${peak} < floor ${MIN_BW} GB/s"
fi
pass "both nixlbench ranks completed with consistency checks enabled"
