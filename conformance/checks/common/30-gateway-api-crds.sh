#!/usr/bin/env bash
# conformance-check
# id: gateway.api-crds
# description: Gateway API CRDs (gateway.networking.k8s.io) are installed
# dimensions: router_mode=gateway
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
res="$(k api-resources --api-group=gateway.networking.k8s.io 2>/dev/null || true)"
missing=""
for kind in gatewayclasses gateways httproutes; do
  echo "$res" | awk '{print $1}' | grep -qx "$kind" || missing="$missing $kind"
done
[ -z "$missing" ] || fail "missing Gateway API resources:$missing (install the Gateway API CRDs)"
pass "gatewayclasses, gateways, httproutes available"
