#!/usr/bin/env bash
# conformance-check
# id: gke.dranet-devices
# description: DRANET publishes mrdma.google.com NIC devices via DRA ResourceSlices
# dimensions: infra_provider=gke rdma=roce|ib dra=nic|gpu-nic
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl

# 1. DRANET DeviceClass (auto-installed from the GKE version in requirements.yaml).
min_gke="$(req gke.dranet-devices min_gke)"
k get deviceclass mrdma.google.com >/dev/null 2>&1 \
  || fail "DeviceClass mrdma.google.com not found (managed DRANET not active; requires GKE ${min_gke}+; check GKE version and node labels)"

slices="$(k get resourceslices -o json 2>/dev/null || true)"
[ -n "$slices" ] || fail "could not list ResourceSlices"
echo "$slices" | grep -q '"driver": "mrdma.google.com"' \
  || fail "no ResourceSlice from driver mrdma.google.com (DRANET not publishing NIC devices)"
nics="$(echo "$slices" | grep -c '"driver": "mrdma.google.com"' || true)"

if [ "$(dim dra)" = "gpu-nic" ]; then
  # Full-DRA path (pd-disaggregation gke overlay): GPUs are also claimed via
  # DRA, and the gke-rdma-template constrains GPU and NIC to the same PCIe root
  # via matchAttribute resource.kubernetes.io/pcieRoot, so both drivers must
  # publish that attribute.
  pods="$(k get pods -n nvidia-dra-driver-gpu --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  [ "$pods" -gt 0 ] || fail "namespace nvidia-dra-driver-gpu has no pods (NVIDIA GPU DRA driver not installed)"
  notrunning="$(k get pods -n nvidia-dra-driver-gpu --no-headers 2>/dev/null \
    | awk '$3 != "Running" {print $1}' | wc -l | tr -d ' ')"
  [ "$notrunning" -eq 0 ] || fail "$notrunning NVIDIA DRA driver pod(s) not Running"
  echo "$slices" | grep -q '"driver": "gpu.nvidia.com"' \
    || fail "no ResourceSlice from driver gpu.nvidia.com (NVIDIA GPU DRA driver not publishing devices)"
  echo "$slices" | grep -q 'resource.kubernetes.io/pcieRoot' \
    || fail "ResourceSlices do not expose resource.kubernetes.io/pcieRoot (PCIe-aligned GPU+NIC claims will not allocate)"
  pass "gpu.nvidia.com and mrdma.google.com ResourceSlices present ($nics NIC slice(s)), pcieRoot exposed"
fi

# NIC-only DRA path (e.g. A4X/GB200: mrdma claims + nvidia.com/gpu device plugin).
pass "mrdma.google.com ResourceSlices present ($nics NIC slice(s)); GPUs via device plugin"
