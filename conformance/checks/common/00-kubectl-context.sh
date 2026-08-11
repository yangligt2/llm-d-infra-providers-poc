#!/usr/bin/env bash
# conformance-check
# id: cluster.api-reachable
# description: kubectl can reach the cluster API server
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
ctx="$(kubectl config current-context 2>/dev/null || true)"
[ -n "$ctx" ] || fail "no current kubectl context configured"
k get --raw /readyz >/dev/null || fail "API server of context '$ctx' not reachable"
pass "context '$ctx' reachable"
