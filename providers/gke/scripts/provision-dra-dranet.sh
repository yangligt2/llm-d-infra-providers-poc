#!/usr/bin/env bash
# Provision GKE infrastructure for llm-d, Path A: GPU DRA + managed DRANET (RoCE).
#
# Target dimension profile: infra_provider=gke accelerator=gpu rdma=roce dra=gpu-nic
# Consumed by: llm-d pd-disaggregation guide, modelserver/gpu/vllm/gke overlay
# (ResourceClaimTemplate requesting gpu.nvidia.com + mrdma.google.com on the
# same PCIe root).
#
# Sources of truth:
#   llm-d docs/infrastructure/providers/gke (DRA + DRANET section)
#   https://docs.cloud.google.com/kubernetes-engine/docs/how-to/set-up-dra
#   https://docs.cloud.google.com/kubernetes-engine/docs/how-to/allocate-network-resources-dra
#
# Version floors: managed DRANET needs GKE Standard 1.34.1-gke.1829001+;
# GPU DRA targets GKE 1.35+; Dataplane V2 can only be enabled at cluster creation.
#
# Required IAM: roles/container.admin + roles/iam.serviceAccountUser on the node
# service account. No VPC-level roles are needed (accelerator networks are
# auto-configured via --accelerator-network-profile=auto).
#
# Required environment:
#   PROJECT, LOCATION, CLUSTER_NAME
# Optional environment (defaults for A3 Ultra / H200, Spot):
#   NODE_POOL_NAME=a3u-dra-pool-1
#   MACHINE_TYPE=a3-ultragpu-8g  GPU_TYPE=nvidia-h200-141gb  GPU_COUNT=8
#   NUM_NODES=2
#   CAPACITY_FLAGS="--spot"   # or: "--reservation-affinity=specific --reservation=..."
#   DRA_DRIVER_VERSION=25.8.0
#   ASSUME_YES=0              # 1 skips interactive confirmation
set -euo pipefail

: "${PROJECT:?set PROJECT}" "${LOCATION:?set LOCATION}" "${CLUSTER_NAME:?set CLUSTER_NAME}"
NODE_POOL_NAME="${NODE_POOL_NAME:-a3u-dra-pool-1}"
MACHINE_TYPE="${MACHINE_TYPE:-a3-ultragpu-8g}"
GPU_TYPE="${GPU_TYPE:-nvidia-h200-141gb}"
GPU_COUNT="${GPU_COUNT:-8}"
NUM_NODES="${NUM_NODES:-2}"
CAPACITY_FLAGS="${CAPACITY_FLAGS:---spot}"
DRA_DRIVER_VERSION="${DRA_DRIVER_VERSION:-25.8.0}"
ASSUME_YES="${ASSUME_YES:-0}"

for cmd in gcloud kubectl helm; do
  command -v "$cmd" >/dev/null || { echo "missing required command: $cmd" >&2; exit 1; }
done

confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  printf '%s [y/N] ' "$1"
  read -r ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "aborted"; exit 1; }
}

echo "== Path A: DRA + managed DRANET =="
echo "project=$PROJECT location=$LOCATION cluster=$CLUSTER_NAME"
echo "node pool: $NODE_POOL_NAME  $NUM_NODES x $MACHINE_TYPE ($GPU_COUNT x $GPU_TYPE)  capacity: $CAPACITY_FLAGS"
echo "active identity: $(gcloud config get-value account 2>/dev/null)"
echo
echo "GPU node pools of this shape are expensive. Review machine type, node count,"
echo "and capacity model above."
confirm "Proceed with resource creation in project $PROJECT?"

# --- Cluster (Dataplane V2 mandatory; only settable at creation) ---------------
if gcloud container clusters describe "$CLUSTER_NAME" --location="$LOCATION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "cluster $CLUSTER_NAME already exists; verifying Dataplane V2..."
  dpv2="$(gcloud container clusters describe "$CLUSTER_NAME" --location="$LOCATION" --project="$PROJECT" \
    --format='value(networkConfig.datapathProvider)')"
  if [ "$dpv2" != "ADVANCED_DATAPATH" ]; then
    echo "ERROR: existing cluster does not use Dataplane V2 (datapathProvider=$dpv2)." >&2
    echo "Managed DRANET is unsupported there. Create a new cluster, or use" >&2
    echo "provision-multinet-gib.sh with manually created subnets." >&2
    exit 1
  fi
else
  echo "creating cluster $CLUSTER_NAME (Dataplane V2, managed OTel)..."
  gcloud container clusters create "$CLUSTER_NAME" \
    --enable-dataplane-v2 \
    --managed-otel-scope=COLLECTION_AND_INSTRUMENTATION_COMPONENTS \
    --location="$LOCATION" \
    --project="$PROJECT"
fi

# --- Node pool (DRANET on, default GPU stack off) ------------------------------
if gcloud container node-pools describe "$NODE_POOL_NAME" --cluster="$CLUSTER_NAME" \
     --location="$LOCATION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "node pool $NODE_POOL_NAME already exists; skipping creation"
else
  echo "creating node pool $NODE_POOL_NAME..."
  # gpu-driver-version=disabled + gke-no-default-nvidia-gpu-device-plugin: GPU
  # DRA requires disabling GKE's managed GPU driver and device plugin.
  # --accelerator-network-profile=auto + gke-networking-dra-driver label: managed DRANET.
  # shellcheck disable=SC2086
  gcloud beta container node-pools create "$NODE_POOL_NAME" \
    --project="$PROJECT" \
    --location="$LOCATION" \
    --cluster="$CLUSTER_NAME" \
    --accelerator "type=$GPU_TYPE,count=$GPU_COUNT,gpu-driver-version=disabled" \
    --machine-type="$MACHINE_TYPE" \
    --num-nodes="$NUM_NODES" \
    $CAPACITY_FLAGS \
    --accelerator-network-profile=auto \
    --node-labels="cloud.google.com/gke-networking-dra-driver=true,goog-gke-accelerator-type=$GPU_TYPE,nvidia.com/gpu.present=true,cloud.google.com/gke-nvidia-gpu-dra-driver=true,gke-no-default-nvidia-gpu-device-plugin=true"
fi

gcloud container clusters get-credentials "$CLUSTER_NAME" --location="$LOCATION" --project="$PROJECT"

# --- NVIDIA driver + GPU DRA driver --------------------------------------------
echo "installing COS NVIDIA driver DaemonSet..."
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded.yaml

echo "installing NVIDIA GPU DRA driver (helm chart $DRA_DRIVER_VERSION)..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install nvidia-dra-driver-gpu nvidia/nvidia-dra-driver-gpu \
  --version="$DRA_DRIVER_VERSION" --create-namespace --namespace=nvidia-dra-driver-gpu \
  --set nvidiaDriverRoot="/home/kubernetes/bin/nvidia/" \
  --set gpuResourcesEnabledOverride=true \
  --set resources.computeDomains.enabled=false \
  --set kubeletPlugin.priorityClassName="" \
  --set 'kubeletPlugin.tolerations[0].key=nvidia.com/gpu' \
  --set 'kubeletPlugin.tolerations[0].operator=Exists' \
  --set 'kubeletPlugin.tolerations[0].effect=NoSchedule'

echo
echo "provisioning complete. Validate with:"
echo "  conformance/bin/llmd-infra-check --profile conformance/profiles/gke-pd-disaggregation.yaml --microtests"
