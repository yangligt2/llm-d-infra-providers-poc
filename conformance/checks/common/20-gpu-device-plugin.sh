#!/usr/bin/env bash
# conformance-check
# id: accelerator.gpu.device-plugin
# description: NVIDIA GPUs are schedulable via the device plugin (nvidia.com/gpu allocatable)
# dimensions: accelerator=gpu dra=none|nic
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl
total=0
while read -r n; do
  [ -n "$n" ] && total=$((total + n))
done < <(k get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}')

[ "$total" -gt 0 ] || fail "no node advertises allocatable nvidia.com/gpu (device plugin or GPU driver missing)"
pass "$total allocatable nvidia.com/gpu across the cluster"
