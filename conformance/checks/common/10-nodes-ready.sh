#!/usr/bin/env bash
# conformance-check
# id: cluster.nodes-ready
# description: At least one node is Ready
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

# NotReady nodes are normal in a live cluster (autoscaler provisioning,
# repairs, drains), so they are reported as evidence but do not fail the
# check. Usable accelerator capacity is validated separately by the
# accelerator.gpu.* checks.
require_cmd kubectl
total=0 ready=0 notready=0
while read -r name status _; do
  [ -n "$name" ] || continue
  total=$((total + 1))
  case "$status" in
    Ready|Ready,*) ready=$((ready + 1)) ;;
    *) notready=$((notready + 1)); echo "not ready: $name ($status)" ;;
  esac
done < <(k get nodes --no-headers 2>/dev/null | awk '{print $1, $2}')

[ "$total" -gt 0 ] || fail "no nodes found"
[ "$ready" -gt 0 ] || fail "0 of $total nodes Ready"
[ "$notready" -eq 0 ] && pass "$total nodes Ready"
pass "$ready of $total nodes Ready ($notready not Ready)"
