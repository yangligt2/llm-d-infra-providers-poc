#!/usr/bin/env bash
# Shared helpers for conformance checks. Sourced by every check script.
#
# Exit code contract:
#   0   PASS
#   77  SKIP (check decided at runtime it is not applicable / cannot run safely)
#   *   FAIL
#
# The runner exports one LLMD_DIM_<KEY> variable per profile dimension, e.g.
# LLMD_DIM_INFRA_PROVIDER=gke, plus LLMD_CONFORMANCE_ROOT.

pass() { echo "ok: $*"; exit 0; }
fail() { echo "error: $*" >&2; exit 1; }
skip() { echo "skip: $*"; exit 77; }

# require_cmd <cmd>... - fail (not skip) if a required binary is missing:
# a conformance run without its tools is a failed run, not a passing one.
require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || fail "required command not found: $c"
  done
}

# dim <key> - read a profile dimension value ("" if unset).
dim() {
  local key
  key="LLMD_DIM_$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  printf '%s' "${!key-}"
}

# k - kubectl against the current context, never prompting.
k() { kubectl --request-timeout=20s "$@"; }

# semver_ge <a> <b> - true if dotted version a >= b (numeric fields only).
semver_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}
