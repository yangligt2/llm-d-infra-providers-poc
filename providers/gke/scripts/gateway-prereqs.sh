#!/usr/bin/env bash
# Enable GKE Gateway API prerequisites for llm-d gateway mode
# (gateway_provider=gke, router_mode=gateway).
#
# Only needed when llm-d will use a GKE-managed GatewayClass (gke-l7-rilb for
# VPC-internal, gke-l7-regional-external-managed for internet-facing).
# Standalone router mode needs none of this.
#
# Sources of truth:
#   llm-d docs/infrastructure/gateway/gke.md
#   https://docs.cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways
#
# Required IAM: roles/container.admin (Gateway API enablement),
# roles/compute.networkAdmin (proxy-only subnet).
#
# Required environment:
#   PROJECT, LOCATION, CLUSTER_NAME, REGION, VPC_NETWORK_NAME
# Optional:
#   PROXY_SUBNET_NAME=proxy-only-subnet
#   PROXY_SUBNET_RANGE=10.129.0.0/23   # /26 minimum, /23 recommended
#   GAIE_VERSION=v1.5.0                # only used on GKE < 1.34.0-gke.1626000
#   ASSUME_YES=0
set -euo pipefail

: "${PROJECT:?set PROJECT}" "${LOCATION:?set LOCATION}" "${CLUSTER_NAME:?set CLUSTER_NAME}"
: "${REGION:?set REGION}" "${VPC_NETWORK_NAME:?set VPC_NETWORK_NAME}"
PROXY_SUBNET_NAME="${PROXY_SUBNET_NAME:-proxy-only-subnet}"
PROXY_SUBNET_RANGE="${PROXY_SUBNET_RANGE:-10.129.0.0/23}"
GAIE_VERSION="${GAIE_VERSION:-v1.5.0}"
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

echo "== GKE Gateway API prerequisites =="
echo "project=$PROJECT cluster=$CLUSTER_NAME location=$LOCATION"
echo "This updates the existing cluster (--gateway-api=standard) and may create a"
echo "proxy-only subnet $PROXY_SUBNET_NAME ($PROXY_SUBNET_RANGE) in $REGION on $VPC_NETWORK_NAME."
confirm "Proceed?"

channel="$(gcloud container clusters describe "$CLUSTER_NAME" --location="$LOCATION" --project="$PROJECT" \
  --format='value(networkConfig.gatewayApiConfig.channel)' 2>/dev/null || true)"
if [ "$channel" = "CHANNEL_STANDARD" ]; then
  echo "Gateway API already enabled (CHANNEL_STANDARD)"
else
  gcloud container clusters update "$CLUSTER_NAME" \
    --location="$LOCATION" --project="$PROJECT" --gateway-api=standard
  echo "Gateway API enablement submitted; CRD reconciliation can take up to 45 minutes"
fi

existing="$(gcloud compute networks subnets list --project="$PROJECT" \
  --filter="purpose=REGIONAL_MANAGED_PROXY AND region:$REGION AND network:$VPC_NETWORK_NAME" \
  --format='value(name)' 2>/dev/null || true)"
if [ -n "$existing" ]; then
  echo "proxy-only subnet already present: $existing"
else
  gcloud compute networks subnets create "$PROXY_SUBNET_NAME" \
    --project="$PROJECT" \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE \
    --region="$REGION" \
    --network="$VPC_NETWORK_NAME" \
    --range="$PROXY_SUBNET_RANGE"
fi

gcloud container clusters get-credentials "$CLUSTER_NAME" --location="$LOCATION" --project="$PROJECT"

# GKE 1.34.0-gke.1626000+ auto-installs the GA Gateway API + Inference Extension
# CRDs; install manually on older versions.
if ! kubectl api-resources --api-group=inference.networking.k8s.io 2>/dev/null | grep -q inferencepools; then
  echo "installing Gateway API Inference Extension CRDs ($GAIE_VERSION)..."
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${GAIE_VERSION}/v1-manifests.yaml"
fi

echo
echo "verify with:"
echo "  kubectl get gatewayclass   # expect gke-l7-rilb / gke-l7-regional-external-managed ACCEPTED=True"
echo "  conformance/bin/llmd-infra-check --dim infra_provider=gke --dim router_mode=gateway --dim gateway_provider=gke ..."
