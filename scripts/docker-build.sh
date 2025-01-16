#!/bin/bash



# Input Variables
dockerfile=$1
docker_build_path=${2:-.}
service=$3

# Secrets
GC_SERVICE_ACCOUNT=$4
GC_SERVICE_ACCOUNT_SECRET=$5
GC_PROJECT_ID=$6
REACT_JS_ENV=${7:-}

DEFAULT_VERSION=2.0.0

# Environment Variables
DOCKER_IMG_PATH="europe-west1-docker.pkg.dev/${GC_PROJECT_ID}/docker-repo/${service}"
GOOGLE_APPLICATION_CREDENTIALS="${PWD}/${GC_SERVICE_ACCOUNT}.json"
SERVICE_ACCOUNT_EMAIL="${GC_SERVICE_ACCOUNT}@${GC_PROJECT_ID}.iam.gserviceaccount.com"

cd /mnt/c/Users/maren/Documents/projects/projekte_master/Cloud/

# Set New Version (Simulated call to an external workflow or script)
# new_version=$(./docker-set-version.sh "$service" "$GC_PROJECT_ID" "$GC_SERVICE_ACCOUNT" "$GC_SERVICE_ACCOUNT_SECRET")
# if [ $? -ne 0 ]; then
#   echo "Failed to set new version"
#   exit 1
# fi
# Get current version of frontend docker file
# Authenticate to Google Cloud
echo "$GC_SERVICE_ACCOUNT_SECRET" | base64 --decode > "$GOOGLE_APPLICATION_CREDENTIALS"
gcloud auth activate-service-account "$SERVICE_ACCOUNT_EMAIL" --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
gcloud config set project "$GC_PROJECT_ID"

# Configure Docker authentication
gcloud auth configure-docker europe-west1-docker.pkg.dev --quiet

VERSION=$(gcloud container images list-tags "${DOCKER_IMG_PATH}${service}" | head -n 2 | grep -oP '\b(latest|\d+\.\d+\.\d+)\b') || VERSION="$DEFAULT_VERSION"
if [ "$VERSION" != "latest" ]; then
  new_version=$(echo $VERSION | awk -F. '{print $1"."$2"."$3+1}')
else
  new_version="$DEFAULT_VERSION"
fi

echo $VERSION
echo $new_version

# Clone Repository (if applicable)
# git clone https://github.com/your-repo/your-project.git && cd your-project || exit 1

# Create frontend environment if the service is 'frontend'
if [ "$service" == "frontend" ]; then
  cd frontend/app || exit 1
  # echo "$REACT_JS_ENV" > .env
  # cat .env
  
  while IFS='=' read -r name value; do
    export "$name"="$value"
  done < .env

  npm install
  npm run build
  cd ../..
fi

# Build Docker Image
docker build --tag "${service}:${new_version}" --file "$dockerfile" "$docker_build_path"

# Tag Docker Image
docker tag "${service}:${new_version}" "${DOCKER_IMG_PATH}:${new_version}"

# Push Docker Image
echo "${DOCKER_IMG_PATH}:${new_version}"
docker push "${DOCKER_IMG_PATH}:${new_version}"

# Cleanup
rm -f "$GOOGLE_APPLICATION_CREDENTIALS"

echo "Docker image pushed successfully: ${DOCKER_IMG_PATH}:${new_version}"