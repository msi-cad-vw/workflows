#!/bin/bash

# Inputs
SERVICE=$1
SERVICE_DIR=$2
CLUSTER=${3:-msi-cad-vw-cluster}
VERSION=${4:-"0.1.0"}
GC_SERVICE_ACCOUNT=$5
GC_SERVICE_ACCOUNT_SECRET=$6
GC_PROJECT_ID=$7

# Environment Variables
HELM_CHART_PATH="oci://europe-west1-docker.pkg.dev/${GC_PROJECT_ID}/helm-repo/${SERVICE}"
GOOGLE_APPLICATION_CREDENTIALS="${PWD}/${GC_SERVICE_ACCOUNT}.json"
SERVICE_ACCOUNT_EMAIL="${GC_SERVICE_ACCOUNT}@${GC_PROJECT_ID}.iam.gserviceaccount.com"
REGION="europe-west1-c"

cd /mnt/c/Users/maren/Documents/projects/projekte_master/Cloud/devOps/

# Authenticate to Google Cloud
echo "$GC_SERVICE_ACCOUNT_SECRET" | base64 --decode > "$GOOGLE_APPLICATION_CREDENTIALS"
gcloud auth activate-service-account "$SERVICE_ACCOUNT_EMAIL" --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
gcloud config set project "$GC_PROJECT_ID"

# Configure Docker authentication
gcloud auth configure-docker europe-west1-docker.pkg.dev --quiet

# Create Helm Chart package
helm package "$SERVICE_DIR" --version "$VERSION"

# Push Helm Chart
helm push "helm-${VERSION}.tgz" "$HELM_CHART_PATH"

# Cleanup
rm -f "$GOOGLE_APPLICATION_CREDENTIALS" "helm-${VERSION}.tgz"