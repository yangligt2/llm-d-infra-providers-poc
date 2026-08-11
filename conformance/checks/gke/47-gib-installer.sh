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

# vLLM 0.11.0+ requires NCCL 2.27 => gIB 1.10+ (llm-d GKE guide). The installer
# image version is the observable proxy for the gIB version on the node.
img="$(k get daemonset -n "$ns" "$name" -o jsonpath='{.spec.template.spec.initContainers[0].image}{" "}{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
echo "installer images: $img"
echo "note: vLLM 0.11.0+ needs gIB 1.10+ (NCCL 2.27); use at least the installer from container-engine-accelerators PR #511"
pass "DaemonSet $ns/$name ready on $desired node(s)"
