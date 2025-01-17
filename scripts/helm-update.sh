#!/bin/bash

# Inputs
CLUSTER=${1:-msi-cad-vw-cluster}
DATABASE=${2:-msi-cad-vw-database}
BUCKET=${3:-msi-cad-vw-bucket}
GC_SERVICE_ACCOUNT=$4
GC_SERVICE_ACCOUNT_SECRET=$5
GC_PROJECT_ID=$6
GC_BACKEND_BUCKET=$7

# Environment Variables
HELM_CHART_PATH="oci://europe-west1-docker.pkg.dev/${GC_PROJECT_ID}/helm-repo"
REGION="europe-west1-c"
DOCKER_IMG_PATH="europe-west1-docker.pkg.dev/${GC_PROJECT_ID}/docker-repo/"
GOOGLE_APPLICATION_CREDENTIALS="${PWD}/${GC_SERVICE_ACCOUNT}.json"
SERVICE_ACCOUNT_EMAIL="${GC_SERVICE_ACCOUNT}@${GC_PROJECT_ID}.iam.gserviceaccount.com"
DEFAULT_VERSION="1.0.0"

FRONTEND="frontend"
PARKING_GARAGES="parking-garages"
PARKING_MANAGEMENT="parking-management"
FACILITY_MANAGEMENT="facility-management"
DEFECT_MANAGEMENT="defect-management"
USER_TENANT_MANAGEMENT="user-tenant-management"

# Authenticate to Google Cloud
echo "$GC_SERVICE_ACCOUNT_SECRET" | base64 --decode > "$GOOGLE_APPLICATION_CREDENTIALS"
gcloud auth activate-service-account "$SERVICE_ACCOUNT_EMAIL" --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
gcloud config set project "$GC_PROJECT_ID"

# Configure Docker authentication
gcloud auth configure-docker europe-west1-docker.pkg.dev --quiet

# Function to get Docker image version
get_version() {
  local service_name=$1
  local version

  version=$(gcloud container images list-tags "${DOCKER_IMG_PATH}${service_name}" | head -n 2 | grep -oP '\b(latest|\d+\.\d+\.\d+)\b') || version="$DEFAULT_VERSION"
  echo "$version"

  # echo "2.0.1"
}

echo $(gcloud container images list-tags "${DOCKER_IMG_PATH}${FRONTEND}" | head -n 2)

# Get versions for all services
FRONTEND_VERSION=$(get_version "$PARKING_GARAGES")
PARKING_GARAGES_VERSION=$(get_version "$PARKING_GARAGES")
PARKING_MANAGEMENT_VERSION=$(get_version "$PARKING_MANAGEMENT")
FACILITY_MANAGEMENT_VERSION=$(get_version "$FACILITY_MANAGEMENT")
DEFECT_MANAGEMENT_VERSION=$(get_version "$DEFECT_MANAGEMENT")
USER_TENANT_MANAGEMENT_VERSION=$(get_version "$USER_TENANT_MANAGEMENT")

# Output versions
echo "Frontend Version: $FRONTEND_VERSION"
echo "Parking Garages Version: $PARKING_GARAGES_VERSION"
echo "Parking Management Version: $PARKING_MANAGEMENT_VERSION"
echo "Facility Management Version: $FACILITY_MANAGEMENT_VERSION"
echo "Defect Management Version: $DEFECT_MANAGEMENT_VERSION"
echo "User Tenant Management Version: $USER_TENANT_MANAGEMENT_VERSION"

# Get GKE credentials
gcloud container clusters get-credentials "$CLUSTER" --region "$REGION"

# Download tenants.json
gcloud storage cp "gs://${GC_BACKEND_BUCKET}/tenants.json" tenants.json
tenants=$(jq -r '.[].name' tenants.json)

# Deploy Frontend and Gateway
helm install gateway "${HELM_CHART_PATH}/infrastructure/helm" --set googleProject.name="$GC_PROJECT_ID" || true
helm install frontend "${HELM_CHART_PATH}/frontend/helm" \
  --set googleProject.name="$GC_PROJECT_ID" \
  --set frontend.version="$(get_version frontend)" || true

# Deploy Authentication
helm install authentication "${HELM_CHART_PATH}/authentication/helm" \
  --set resources.database="$DATABASE" \
  --set resources.bucket="$BUCKET" \
  --set googleProject.name="$GC_PROJECT_ID" \
  --set userTenantManagement.version="$(get_version user-tenant-management)" || true

# Deploy Backend for each tenant
jq -c '.[]' tenants.json | while read -r entry; do
  tenant=$(echo "$entry" | jq -r '.name')
  replicas=$(echo "$entry" | jq -r '.replicas')
  maxReplicas=$(echo "$entry" | jq -r '.maxReplicas')
  maxUnavailable=$(echo "$entry" | jq -r '.maxUnavailable')
  maxSurge=$(echo "$entry" | jq -r '.maxSurge')
  averageUtilization=$(echo "$entry" | jq -r '.averageUtilization')

  helm install parkspace-$tenant ${HELM_CHART_PATH}/backend/helm \
    --set namespace="$tenant" \
    --set resources.database="$DATABASE" \
    --set resources.bucket="$BUCKET" \
    --set googleProject.name="$GC_PROJECT_ID" \
    --set parkingManagement.version="$(get_version parking-management)" \
    --set parkingGarages.version="$(get_version parking-garages)" \
    --set facilityManagement.version="$(get_version facility-management)" \
    --set defectManagement.version="$(get_version defect-management)" \
    --set replicaCount=$replicas  \
    --set scaling.averageUtilization=$averageUtilization \
    --set scaling.maxReplicas=$maxReplicas \
    --set scaling.memoryLimit=$maxMemory \
    --set scaling.cpuLimit=$maxCPU \
    --set rollingUpdate.maxUnavailable=$maxUnavailable \
    --set rollingUpdate.maxSurge=$maxSurge
  
  echo "Executing for $tenant with $replicas, $maxReplicas, $maxUnavailable, $maxSurge"
  # Add your custom commands for each $name and $replicas here
done

# Create secrets for namespaces
gcloud iam service-accounts keys create key.json --iam-account="$SERVICE_ACCOUNT_EMAIL"

kubectl create secret generic gcp-sa-key --from-file=key.json=key.json -n authentication || true
kubectl create secret generic gcp-sa-key --from-file=key.json=key.json -n frontend || true

for tenant in $tenants; do
  kubectl create secret generic gcp-sa-key --from-file=key.json=key.json -n "$tenant" || true
done

# Upgrade services
helm upgrade gateway "${HELM_CHART_PATH}/infrastructure/helm" --set googleProject.name="$GC_PROJECT_ID"
helm upgrade frontend "${HELM_CHART_PATH}/frontend/helm" \
  --set googleProject.name="$GC_PROJECT_ID" \
  --set frontend.version="$(get_version frontend)"

helm upgrade authentication "${HELM_CHART_PATH}/authentication/helm" \
  --set resources.database="$DATABASE" \
  --set resources.bucket="$BUCKET" \
  --set googleProject.name="$GC_PROJECT_ID" \
  --set userTenantManagement.version="$(get_version user-tenant-management)"

jq -c '.[]' tenants.json | while read -r entry; do
  tenant=$(echo "$entry" | jq -r '.name')
  replicas=$(echo "$entry" | jq -r '.replicas')
  maxReplicas=$(echo "$entry" | jq -r '.maxReplicas')
  maxUnavailable=$(echo "$entry" | jq -r '.maxUnavailable')
  maxSurge=$(echo "$entry" | jq -r '.maxSurge')
  averageUtilization=$(echo "$entry" | jq -r '.averageUtilization')
  maxCPU=$(echo "$entry" | jq -r '.maxCPU')
  maxMemory=$(echo "$entry" | jq -r '.maxMemory')

  helm upgrade parkspace-$tenant $HELM_CHART_PATH/backend/helm \
    --set namespace="$tenant" \
    --set resources.database="$DATABASE" \
    --set resources.bucket="$BUCKET" \
    --set googleProject.name="$GC_PROJECT_ID" \
    --set parkingManagement.version="$(get_version parking-management)" \
    --set parkingGarages.version="$(get_version parking-garages)" \
    --set facilityManagement.version="$(get_version facility-management)" \
    --set defectManagement.version="$(get_version defect-management)" \
    --set replicaCount=$replicas  \
    --set scaling.averageUtilization=$averageUtilization \
    --set scaling.maxReplicas=$maxReplicas \
    --set scaling.memoryLimit=$maxMemory \
    --set scaling.cpuLimit=$maxCPU \
    --set rollingUpdate.maxUnavailable=$maxUnavailable \
    --set rollingUpdate.maxSurge=$maxSurge
  
  echo "Executing for $tenant with $replicas, $maxReplicas, $maxUnavailable, $maxSurge, $maxCPU, $maxMemory"
  # Add your custom commands for each $name and $replicas here
done

# Cleanup
rm -f key.json tenants.json
