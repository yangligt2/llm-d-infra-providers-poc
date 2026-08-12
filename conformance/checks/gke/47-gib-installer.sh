#!/usr/bin/env bash
# conformance-check
# id: gke.gib-installer
# description: gIB / NCCL RDMA installer DaemonSet is running on all GPU nodes
# dimensions: infra_provider=gke rdma=roce dra=none
set -euo pipefail
. "$LLMD_CONFORMANCE_ROOT/lib/common.sh"

require_cmd kubectl

# The installer DaemonSet from GoogleCloudPlatform/container-engine-accelerators
# (gpudirect-rdma/nccl-rdma-installer.yaml) places RDMA binaries in
# /home/kubernetes/bin/gib on each node.
row="$(k get daemonsets -A --no-headers 2>/dev/null | grep -i 'rdma' | head -n 1 || true)"
[ -n "$row" ] || fail "no RDMA installer DaemonSet found (apply gpudirect-rdma/nccl-rdma-installer.yaml)"

ns="$(echo "$row" | awk '{print $1}')"
name="$(echo "$row" | awk '{print $2}')"
desired="$(echo "$row" | awk '{print $3}')"
ready="$(echo "$row" | awk '{print $5}')"
[ "$desired" = "$ready" ] || fail "DaemonSet $ns/$name: $ready of $desired pods ready"

# Floors from requirements.yaml (gke.gib-installer, per the llm-d GKE guide).
# The installer image version is the observable proxy for the gIB version on
# the node.
min_gib="$(req gke.gib-installer min_gib)"
min_nccl="$(req gke.gib-installer min_nccl)"
vllm_from="$(req gke.gib-installer vllm_from)"
installer_ref="$(req gke.gib-installer installer_ref)"
img="$(k get daemonset -n "$ns" "$name" -o jsonpath='{.spec.template.spec.initContainers[0].image}{" "}{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
echo "installer images: $img"
echo "note: vLLM ${vllm_from}+ needs gIB ${min_gib}+ (NCCL ${min_nccl}); use at least the installer from ${installer_ref}"
pass "DaemonSet $ns/$name ready on $desired node(s)"
