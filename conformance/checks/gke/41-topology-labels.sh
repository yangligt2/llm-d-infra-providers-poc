#!/usr/bin/env bash
# conformance-check
# id: gke.rdma-topology-labels
# description: RDMA-capable GKE nodes carry gce-topology-block labels used by llm-d overlays for placement
# dimensions: infra_provider=gke accelerator=gpu rdma=roce|ib
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
total=0 labeled=0
while read -r block; do
  total=$((total + 1))
  [ -n "$block" ] && [ "$block" != "<none>" ] && labeled=$((labeled + 1))
done < <(k get nodes -l cloud.google.com/gke-accelerator \
  -o jsonpath='{range .items[*]}{.metadata.labels.cloud\.google\.com/gce-topology-block}{"\n"}{end}')

[ "$total" -gt 0 ] || fail "no accelerator nodes found"
if [ "$labeled" -eq 0 ]; then
  # llm-d GKE overlays add pod affinity on these labels; absence means the machine
  # shape is likely not on the RDMA fabric (A3 Ultra / A4 / A4X).
  fail "no accelerator node has cloud.google.com/gce-topology-block (nodes not on an RDMA fabric?)"
fi
[ "$labeled" -eq "$total" ] || echo "warning: only $labeled of $total accelerator nodes carry topology labels"
pass "$labeled of $total accelerator node(s) carry gce-topology-block"
