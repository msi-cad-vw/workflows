#!/bin/bash

set -e  # Exit on any error

# Input Parameters
TENANT_ID=$1
ACTION=${2:-create}  # Default to 'create'
CLUSTER=${3:-msi-cad-vw-cluster}
GC_SERVICE_ACCOUNT=$4
GC_SERVICE_ACCOUNT_SECRET=$5
GC_PROJECT_ID=$6
GC_BACKEND_BUCKET=$7

# Environment Variables
GOOGLE_APPLICATION_CREDENTIALS="${PWD}/${GC_SERVICE_ACCOUNT}.json"
SERVICE_ACCOUNT_EMAIL="${GC_SERVICE_ACCOUNT}@${GC_PROJECT_ID}.iam.gserviceaccount.com"
ENTRY_EXISTS=false
CLUSTER="msi-cad-vw-cluster"

# Authenticate to Google Cloud
echo "$GC_SERVICE_ACCOUNT_SECRET" | base64 --decode > "$GOOGLE_APPLICATION_CREDENTIALS"
echo "$SERVICE_ACCOUNT_EMAIL"
gcloud auth activate-service-account "$SERVICE_ACCOUNT_EMAIL" --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
gcloud config set project "$GC_PROJECT_ID"

# Copy tenants.json
gcloud storage cp gs://$GC_BACKEND_BUCKET/tenants.json tenants.json

# Check if entry exists
if jq -e ".[] | select(.name == \"$TENANT_ID\")" tenants.json > /dev/null; then
  ENTRY_EXISTS=true
else
  ENTRY_EXISTS=false
fi

# Handle actions
if [ "$ACTION" == "create" ]; then
  if [ "$ENTRY_EXISTS" == "true" ]; then
    echo "Name is already existing or not valid"
    exit 1
  else
    jq ". += [{\"name\": \"$TENANT_ID\", \"replicas\": \"2\", \"maxReplicas\": \"5\", \"maxUnavailable\": \"0\", \"maxSurge\": \"1\", \"averageUtilization\": \"50%\"}]" tenants.json > tenants_new.json
    gcloud storage cp tenants_new.json gs://$GC_BACKEND_BUCKET/tenants.json
  fi

elif [ "$ACTION" == "delete" ]; then
  if [ "$ENTRY_EXISTS" == "true" ]; then
    jq "del(.[] | select(.name == \"$TENANT_ID\"))" tenants.json > tenants_new.json
    gcloud storage cp tenants_new.json gs://$GC_BACKEND_BUCKET/tenants.json
  else
    echo "Entry does not exist. Nothing to delete."
  fi
else
  echo "Unsupported action: $ACTION"
  exit 1
fi



# Additional workflow steps (terraform and helm setup) can be integrated as needed
# Example placeholder for invoking Terraform
# terraform -chdir=./terraform/startup apply -auto-approve

# Example placeholder for invoking Helm
# helm upgrade --install ...


jq '. += [,{ \
\"name\": \"miau\", \
"replicas": "2", \
"maxReplicas": "3", \
"maxUnavailable": "0", \
"maxSurge": "1", \
"averageUtilization": "50", \
"maxCPU": "100m", \
"maxMemory": "150Mi"}]' tenants_new.json > tenants_miau.json