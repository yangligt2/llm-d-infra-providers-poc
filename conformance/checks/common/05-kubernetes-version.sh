#!/usr/bin/env bash
# conformance-check
# id: cluster.kubernetes-version
# description: Kubernetes server version meets the llm-d floor (requirements.yaml)
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
ver="$(k version -o json 2>/dev/null \
  | tr -d ' \n' \
  | sed -n 's/.*"serverVersion":{[^}]*"gitVersion":"v\([0-9][0-9.]*\)[^"]*".*/\1/p')"
[ -n "$ver" ] || fail "could not determine server version"

min="$(req cluster.kubernetes-version min)"
rec="$(req cluster.kubernetes-version recommended)"
semver_ge "$ver" "$min" || fail "server version $ver < $min"
if ! semver_ge "$ver" "$rec"; then
  echo "warning: server version $ver < $rec; sidecar init container support is incomplete"
fi
pass "server version $ver (floor $min, recommended $rec)"
