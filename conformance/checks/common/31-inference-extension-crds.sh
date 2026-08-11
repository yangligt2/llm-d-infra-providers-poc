#!/usr/bin/env bash
# conformance-check
# id: gateway.inference-extension-crds
# description: Gateway API Inference Extension CRDs (inference.networking.k8s.io) are installed
# dimensions: router_mode=gateway
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
k api-resources --api-group=inference.networking.k8s.io 2>/dev/null \
  | awk '{print $1}' | grep -qx inferencepools \
  || fail "InferencePool CRD not found (install the Gateway API Inference Extension manifests pinned by llm-d guides/env.sh)"
pass "inferencepools available"
