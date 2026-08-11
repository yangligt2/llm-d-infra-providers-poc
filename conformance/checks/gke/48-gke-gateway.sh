#!/usr/bin/env bash
# conformance-check
# id: gke.gateway-classes
# description: GKE-managed GatewayClasses used by llm-d recipes are present and accepted
# dimensions: infra_provider=gke router_mode=gateway gateway_provider=gke
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl

# llm-d gateway recipes use gke-l7-rilb (VPC-internal) or
# gke-l7-regional-external-managed (internet-facing). Both also require a
# REGIONAL_MANAGED_PROXY subnet in the cluster's region; that is a gcloud-level
# check performed by the provider tooling, not here.
found=""
for gc in gke-l7-rilb gke-l7-regional-external-managed; do
  accepted="$(k get gatewayclass "$gc" \
    -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)"
  [ "$accepted" = "True" ] && found="$found $gc"
done
[ -n "$found" ] || fail "neither gke-l7-rilb nor gke-l7-regional-external-managed is present+accepted (enable the Gateway API: gcloud container clusters update --gateway-api=standard)"
pass "accepted GKE GatewayClasses:$found"
