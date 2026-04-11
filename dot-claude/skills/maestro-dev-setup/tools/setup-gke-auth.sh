#!/usr/bin/env bash
# Set up gcloud authentication and kubectl context for Maestro GKE cluster.
# Usage: ./setup-gke-auth.sh
#
# Prerequisites: gcloud CLI installed and on PATH
# What it does:
#   1. Authenticates with Google Cloud (opens browser)
#   2. Installs gke-gcloud-auth-plugin
#   3. Configures kubectl context for the Maestro GKE cluster
#   4. Verifies cluster access

set -euo pipefail

CLUSTER="main-0"
REGION="us-east1"
PROJECT="toptal-maestro"
EXPECTED_CONTEXT="gke_${PROJECT}_${REGION}_${CLUSTER}"

echo "=== Maestro GKE Auth Setup ==="
echo ""

# Check gcloud
if ! command -v gcloud &>/dev/null; then
    echo "ERROR: gcloud not found. Install with: brew install --cask google-cloud-sdk"
    echo "Then add to ~/.zshrc: export PATH=\"/opt/homebrew/share/google-cloud-sdk/bin:\$PATH\""
    exit 1
fi

# Check if already authenticated
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || true)
if [[ -n "$ACCOUNT" ]]; then
    echo "Already authenticated as: $ACCOUNT"
    read -p "Re-authenticate? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && gcloud auth login --brief
else
    echo "Step 1: Authenticating with Google Cloud..."
    gcloud auth login --brief
fi

# Install GKE auth plugin
echo ""
echo "Step 2: Installing GKE auth plugin..."
gcloud components install gke-gcloud-auth-plugin --quiet 2>&1

# Configure kubectl
echo ""
echo "Step 3: Configuring kubectl context..."
gcloud container clusters get-credentials "$CLUSTER" --region "$REGION" --project "$PROJECT"

# Verify
echo ""
echo "Step 4: Verifying..."
CONTEXT=$(kubectl config current-context 2>/dev/null || true)
if [[ "$CONTEXT" == "$EXPECTED_CONTEXT" ]]; then
    echo "kubectl context: $CONTEXT"
    POD_COUNT=$(kubectl get pods -n team-maestro --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "Pods in team-maestro namespace: $POD_COUNT"
    echo ""
    echo "GKE auth setup complete."
else
    echo "ERROR: Expected context '$EXPECTED_CONTEXT' but got '$CONTEXT'"
    exit 1
fi
