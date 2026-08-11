#!/usr/bin/env bash
# Provision GKE infrastructure for llm-d, Path B: multi-networking + gIB
# (GPUDirect RDMA over RoCE).
#
# Target dimension profile: infra_provider=gke accelerator=gpu rdma=roce dra=none
# Consumed by: llm-d wide-ep-lws guide, modelserver/gpu/vllm/gke overlay
# (networking.gke.io/interfaces annotations rdma-0..rdma-7, gIB host mounts,
# set_nccl_env.sh).
#
# Sources of truth:
#   https://docs.cloud.google.com/ai-hypercomputer/docs/create/gke-ai-hypercompute-custom
#   llm-d docs/infrastructure/providers/gke
#
# WARNING: do not enable managed DRANET on a cluster using this path; the DRANET
# driver and Device-type Network resources manage the same NICs and must not be
# combined (GCP DRANET documentation).
#
# Required IAM: roles/container.admin, roles/iam.serviceAccountUser,
# roles/compute.networkAdmin (VPCs/subnets), roles/compute.securityAdmin
# (firewall rule).
#
# Required environment:
#   PROJECT, REGION, ZONE, CLUSTER_NAME
# Optional environment (defaults for A4 / B200, Spot):
#   NODE_POOL_NAME=gpu-rdma-pool
#   GVNIC_PREFIX=a4high-gvnic  RDMA_PREFIX=a4high-rdma
#   MACHINE_TYPE=a4-highgpu-8g GPU_TYPE=nvidia-b200 GPU_COUNT=8
#   GPU_DRIVER_VERSION=default NUM_NODES=2
#   CAPACITY_FLAGS="--spot"   # or reservation / flex-start flags
#   ASSUME_YES=0
set -euo pipefail

: "${PROJECT:?set PROJECT}" "${REGION:?set REGION}" "${ZONE:?set ZONE}" "${CLUSTER_NAME:?set CLUSTER_NAME}"
NODE_POOL_NAME="${NODE_POOL_NAME:-gpu-rdma-pool}"
GVNIC_PREFIX="${GVNIC_PREFIX:-a4high-gvnic}"
RDMA_PREFIX="${RDMA_PREFIX:-a4high-rdma}"
MACHINE_TYPE="${MACHINE_TYPE:-a4-highgpu-8g}"
GPU_TYPE="${GPU_TYPE:-nvidia-b200}"
GPU_COUNT="${GPU_COUNT:-8}"
GPU_DRIVER_VERSION="${GPU_DRIVER_VERSION:-default}"
NUM_NODES="${NUM_NODES:-2}"
CAPACITY_FLAGS="${CAPACITY_FLAGS:---spot}"
ASSUME_YES="${ASSUME_YES:-0}"

for cmd in gcloud kubectl; do
  command -v "$cmd" >/dev/null || { echo "missing required command: $cmd" >&2; exit 1; }
done

confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  printf '%s [y/N] ' "$1"
  read -r ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "aborted"; exit 1; }
}

echo "== Path B: multi-networking + gIB =="
echo "project=$PROJECT region=$REGION zone=$ZONE cluster=$CLUSTER_NAME"
echo "networks: ${GVNIC_PREFIX}-net + ${RDMA_PREFIX}-net (RoCE profile, 8 subnets) + 1 firewall rule"
echo "node pool: $NODE_POOL_NAME  $NUM_NODES x $MACHINE_TYPE ($GPU_COUNT x $GPU_TYPE)  capacity: $CAPACITY_FLAGS"
echo "active identity: $(gcloud config get-value account 2>/dev/null)"
confirm "Proceed with resource creation in project $PROJECT?"

# --- VPCs, subnets, firewall ----------------------------------------------------
if ! gcloud compute networks describe "${GVNIC_PREFIX}-net" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute --project="$PROJECT" networks create "${GVNIC_PREFIX}-net" --subnet-mode=custom
fi
if ! gcloud compute networks subnets describe "${GVNIC_PREFIX}-sub" --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute --project="$PROJECT" networks subnets create "${GVNIC_PREFIX}-sub" \
    --network="${GVNIC_PREFIX}-net" --region="$REGION" --range=192.168.0.0/24
fi
if ! gcloud compute firewall-rules describe "${GVNIC_PREFIX}-internal" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute --project="$PROJECT" firewall-rules create "${GVNIC_PREFIX}-internal" \
    --network="${GVNIC_PREFIX}-net" --action=ALLOW \
    --rules=tcp:0-65535,udp:0-65535,icmp --source-ranges=192.168.0.0/16
fi

if ! gcloud compute networks describe "${RDMA_PREFIX}-net" --project="$PROJECT" >/dev/null 2>&1; then
  # Zone-specific RoCE network profile is mandatory for the RDMA VPC.
  gcloud beta compute --project="$PROJECT" networks create "${RDMA_PREFIX}-net" \
    --network-profile="${ZONE}-vpc-roce" --subnet-mode=custom
fi
for N in 0 1 2 3 4 5 6 7; do
  if ! gcloud compute networks subnets describe "${RDMA_PREFIX}-sub-$N" --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
    gcloud compute --project="$PROJECT" networks subnets create "${RDMA_PREFIX}-sub-$N" \
      --network="${RDMA_PREFIX}-net" --region="$REGION" --range="192.168.$((N + 1)).0/24"
  fi
done

# --- Cluster ---------------------------------------------------------------------
if gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "cluster $CLUSTER_NAME already exists; skipping creation"
else
  gcloud container clusters create "$CLUSTER_NAME" \
    --project="$PROJECT" \
    --region="$REGION" \
    --node-locations="$ZONE" \
    --enable-dataplane-v2 --enable-ip-alias --enable-multi-networking \
    --num-nodes=1 --machine-type=e2-standard-4
fi

# --- GPU node pool with additional node networks ----------------------------------
if gcloud container node-pools describe "$NODE_POOL_NAME" --cluster="$CLUSTER_NAME" \
     --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "node pool $NODE_POOL_NAME already exists; skipping creation"
else
  # shellcheck disable=SC2086
  gcloud container node-pools create "$NODE_POOL_NAME" \
    --project="$PROJECT" --region="$REGION" --cluster="$CLUSTER_NAME" \
    --node-locations="$ZONE" \
    --accelerator "type=$GPU_TYPE,count=$GPU_COUNT,gpu-driver-version=$GPU_DRIVER_VERSION" \
    --machine-type="$MACHINE_TYPE" \
    --num-nodes="$NUM_NODES" \
    $CAPACITY_FLAGS \
    --additional-node-network "network=${GVNIC_PREFIX}-net,subnetwork=${GVNIC_PREFIX}-sub" \
    --additional-node-network "network=${RDMA_PREFIX}-net,subnetwork=${RDMA_PREFIX}-sub-0" \
    --additional-node-network "network=${RDMA_PREFIX}-net,subnetwork=${RDMA_PREFIX}-sub-1" \
    --additional-node-network "network=${RDMA_PREFIX}-net,subnetwork=${RDMA_PREFIX}-sub-2" \
    --additional-node-network "network=${RDMA_PREFIX}-net,subnetwork=${RDMA_PREFIX}-sub-3" \
    --additional-node-network "network=${RDMA_PREFIX}-net,subnetwork=${RDMA_PREFIX}-sub-4" \
    --additional-node-network "network=${RDMA_PREFIX}-net,subnetwork=${RDMA_PREFIX}-sub-5" \
    --additional-node-network "network=${RDMA_PREFIX}-net,subnetwork=${RDMA_PREFIX}-sub-6" \
    --additional-node-network "network=${RDMA_PREFIX}-net,subnetwork=${RDMA_PREFIX}-sub-7"
fi

gcloud container clusters get-credentials "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT"

# --- GKE Network objects (names rdma-0..7 are contractual for the wide-ep guide) --
kubectl apply -f - <<EOF
apiVersion: networking.gke.io/v1
kind: GKENetworkParamSet
metadata:
  name: gvnic-1
spec:
  vpc: ${GVNIC_PREFIX}-net
  vpcSubnet: ${GVNIC_PREFIX}-sub
  deviceMode: NetDevice
---
apiVersion: networking.gke.io/v1
kind: Network
metadata:
  name: gvnic-1
spec:
  type: "Device"
  parametersRef:
    group: networking.gke.io
    kind: GKENetworkParamSet
    name: gvnic-1
EOF

for N in 0 1 2 3 4 5 6 7; do
kubectl apply -f - <<EOF
apiVersion: networking.gke.io/v1
kind: GKENetworkParamSet
metadata:
  name: rdma-$N
spec:
  vpc: ${RDMA_PREFIX}-net
  vpcSubnet: ${RDMA_PREFIX}-sub-$N
  deviceMode: RDMA
---
apiVersion: networking.gke.io/v1
kind: Network
metadata:
  name: rdma-$N
spec:
  type: "Device"
  parametersRef:
    group: networking.gke.io
    kind: GKENetworkParamSet
    name: rdma-$N
EOF
done

# --- gIB / NCCL RDMA installer -----------------------------------------------------
# vLLM 0.11.0+ requires NCCL 2.27 => gIB 1.10+ (see llm-d GKE guide; installer
# version per container-engine-accelerators PR #511).
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/refs/heads/master/gpudirect-rdma/nccl-rdma-installer.yaml

echo
echo "provisioning complete. Validate with:"
echo "  conformance/bin/llmd-infra-check --profile conformance/profiles/gke-wide-ep-lws.yaml --microtests"
