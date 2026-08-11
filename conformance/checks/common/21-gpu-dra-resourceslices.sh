#!/usr/bin/env bash
# conformance-check
# id: accelerator.gpu.dra-resourceslices
# description: GPU devices are published via DRA ResourceSlices (driver gpu.nvidia.com)
# dimensions: accelerator=gpu dra=gpu|gpu-nic
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
k api-resources --api-group=resource.k8s.io 2>/dev/null | grep -q resourceslices \
  || fail "resource.k8s.io API group not available (DRA not enabled on this cluster)"

n="$(k get resourceslices -o jsonpath='{range .items[*]}{.spec.driver}{"\n"}{end}' 2>/dev/null \
  | grep -c '^gpu.nvidia.com$' || true)"
[ "$n" -gt 0 ] || fail "no ResourceSlice from driver gpu.nvidia.com (NVIDIA GPU DRA driver not publishing devices)"

k get deviceclass gpu.nvidia.com >/dev/null 2>&1 \
  || fail "DeviceClass gpu.nvidia.com not found"
pass "$n ResourceSlice(s) from gpu.nvidia.com; DeviceClass present"
