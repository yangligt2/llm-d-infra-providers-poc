#!/usr/bin/env bash
# conformance-check
# id: gateway.controller-accepted
# description: An accepted GatewayClass exists for the selected gateway provider
# dimensions: router_mode=gateway gateway_provider=gke|istio|agentgateway|envoy-ai-gateway
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl

# Known controller names per gateway_provider dimension value.
case "$(dim gateway_provider)" in
  gke)   want="networking.gke.io/gateway" ;;
  istio) want="istio.io/gateway-controller" ;;
  *)     want="" ;;  # accept any accepted class for providers without a fixed controller name
esac

rows="$(k get gatewayclass \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.controllerName}{" "}{.status.conditions[?(@.type=="Accepted")].status}{"\n"}{end}' 2>/dev/null || true)"
[ -n "$rows" ] || fail "no GatewayClass found (gateway controller not installed/enabled)"

while read -r name controller accepted; do
  [ -n "$name" ] || continue
  if [ "$accepted" = "True" ] && { [ -z "$want" ] || [ "$controller" = "$want" ]; }; then
    pass "GatewayClass $name (controller $controller) accepted"
  fi
done <<< "$rows"

fail "no accepted GatewayClass${want:+ with controller $want}; found: $(echo "$rows" | tr '\n' '; ')"
