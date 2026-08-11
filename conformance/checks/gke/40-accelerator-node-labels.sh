#!/usr/bin/env bash
# conformance-check
# id: gke.accelerator-node-labels
# description: GKE nodes expose cloud.google.com/gke-accelerator labels
# dimensions: infra_provider=gke accelerator=gpu
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
n="$(k get nodes -l cloud.google.com/gke-accelerator --no-headers 2>/dev/null | wc -l | tr -d ' ')"
[ "$n" -gt 0 ] || fail "no node labeled cloud.google.com/gke-accelerator (GPU node pool missing?)"

types="$(k get nodes -l cloud.google.com/gke-accelerator \
  -o jsonpath='{range .items[*]}{.metadata.labels.cloud\.google\.com/gke-accelerator}{"\n"}{end}' | sort -u | tr '\n' ' ')"
pass "$n accelerator node(s): $types"
