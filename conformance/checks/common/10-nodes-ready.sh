#!/usr/bin/env bash
# conformance-check
# id: cluster.nodes-ready
# description: All nodes are Ready
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
total=0 notready=0
while read -r name status _; do
  [ -n "$name" ] || continue
  total=$((total + 1))
  case "$status" in
    Ready|Ready,*) ;;
    *) notready=$((notready + 1)); echo "not ready: $name ($status)" ;;
  esac
done < <(k get nodes --no-headers 2>/dev/null | awk '{print $1, $2}')

[ "$total" -gt 0 ] || fail "no nodes found"
[ "$notready" -eq 0 ] || fail "$notready of $total nodes not Ready"
pass "$total nodes Ready"
