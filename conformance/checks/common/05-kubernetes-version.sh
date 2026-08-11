#!/usr/bin/env bash
# conformance-check
# id: cluster.kubernetes-version
# description: Kubernetes server version meets the llm-d floor (>= 1.29; 1.33+ recommended)
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
ver="$(k version -o json 2>/dev/null \
  | tr -d ' \n' \
  | sed -n 's/.*"serverVersion":{[^}]*"gitVersion":"v\([0-9][0-9.]*\)[^"]*".*/\1/p')"
[ -n "$ver" ] || fail "could not determine server version"

# Floor from llm-d docs/infrastructure: 1.29 minimum; v1.33.0+ recommended for
# complete sidecar init container support (restartPolicy: Always).
semver_ge "$ver" "1.29" || fail "server version $ver < 1.29"
if ! semver_ge "$ver" "1.33"; then
  echo "warning: server version $ver < 1.33; sidecar init container support is incomplete"
fi
pass "server version $ver"
