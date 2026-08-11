#!/usr/bin/env bash
# conformance-check
# id: gke.multinet-rdma-networks
# description: GKE multi-networking Network CRs rdma-0..rdma-7 exist and nodes advertise RDMA interface resources
# dimensions: infra_provider=gke rdma=roce dra=none
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl

nets="$(k get networks.networking.gke.io -o name 2>/dev/null || true)"
[ -n "$nets" ] || fail "no networks.networking.gke.io objects (multi-networking CRs not applied)"

# Names rdma-0..rdma-7 are exactly what the wide-ep-lws GKE overlay pod
# annotations reference; a rename breaks the guide.
missing=""
for i in 0 1 2 3 4 5 6 7; do
  echo "$nets" | grep -qx "network.networking.gke.io/rdma-$i" || missing="$missing rdma-$i"
done
[ -z "$missing" ] || fail "missing Network CRs:$missing"

# GKE injects per-network IP resources on the nodes (modern A3 Ultra/A4 nodes
# advertise the .IP variant).
alloc="$(k get nodes -l cloud.google.com/gke-accelerator \
  -o jsonpath='{.items[0].status.allocatable}' 2>/dev/null || true)"
echo "$alloc" | grep -q 'networking.gke.io' \
  || fail "accelerator nodes do not advertise networking.gke.io resources (node pool missing --additional-node-network?)"

pass "rdma-0..rdma-7 Network CRs present; nodes advertise networking.gke.io resources"
