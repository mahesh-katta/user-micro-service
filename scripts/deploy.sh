#!/usr/bin/env bash
#
# Deploys one image tag to this instance. Executed on the EC2 host by the
# pipeline through SSM Run Command, which is why it takes no credentials: it
# uses the instance role for both ECR and Parameter Store.
#
# If the new image does not report healthy, the previously running image is
# started again, so a bad deploy degrades to the last good one rather than to
# an outage.
#
# Usage: deploy.sh <image-tag>

set -euo pipefail

IMAGE_TAG="${1:?usage: deploy.sh <image-tag>}"

CONFIG_FILE="/opt/user-service/config.env"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: $CONFIG_FILE is missing. Did the instance finish bootstrapping?" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
. "$CONFIG_FILE"
set +a

CONTAINER="user-service"
REGISTRY="${ECR_REPO%%/*}"
NEW_IMAGE="${ECR_REPO}:${IMAGE_TAG}"

echo "==> Deploying ${NEW_IMAGE}"

# Remember what is running now so a failed deploy has somewhere to go back to.
PREVIOUS_IMAGE="$(docker inspect --format '{{.Config.Image}}' "$CONTAINER" 2>/dev/null || true)"
echo "==> Currently running: ${PREVIOUS_IMAGE:-nothing}"

echo "==> Authenticating to ECR"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Pulling image"
docker pull "$NEW_IMAGE"

fetch_parameter() {
  aws ssm get-parameter \
    --name "$1" \
    --with-decryption \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text
}

echo "==> Reading configuration from Parameter Store"
DB_PASSWORD="$(fetch_parameter "${SSM_PREFIX}/db/password")"
JWT_SECRET="$(fetch_parameter "${SSM_PREFIX}/jwt/secret")"
DB_HOST="$(fetch_parameter "${SSM_PREFIX}/db/host")"

start_container() {
  local image="$1"

  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

  # Secrets are passed as environment variables to the container only. They are
  # never written to disk on the host and never baked into the image.
  docker run -d \
    --name "$CONTAINER" \
    --network "$APP_NETWORK" \
    --restart unless-stopped \
    --memory 640m \
    --memory-swap 1g \
    -p 8080:8080 \
    -e DB_HOST="$DB_HOST" \
    -e DB_PORT=5432 \
    -e DB_NAME="$DB_NAME" \
    -e DB_USERNAME="$DB_USERNAME" \
    -e DB_PASSWORD="$DB_PASSWORD" \
    -e JWT_SECRET="$JWT_SECRET" \
    -e LOG_LEVEL_APP=INFO \
    "$image" >/dev/null
}

wait_until_healthy() {
  local attempts=60
  for _ in $(seq 1 "$attempts"); do
    if curl -fsS http://127.0.0.1:8080/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
      return 0
    fi
    sleep 3
  done
  return 1
}

echo "==> Starting the new container"
start_container "$NEW_IMAGE"

echo "==> Waiting for the health endpoint to report UP (up to 3 minutes)"
if wait_until_healthy; then
  echo "==> Deployment healthy: ${NEW_IMAGE}"
  curl -fsS http://127.0.0.1:8080/actuator/health || true
  echo
  docker image prune -af --filter "until=168h" >/dev/null 2>&1 || true
  exit 0
fi

echo "ERROR: the new image never reported healthy. Last 200 log lines:" >&2
docker logs --tail 200 "$CONTAINER" >&2 || true

if [ -n "$PREVIOUS_IMAGE" ] && [ "$PREVIOUS_IMAGE" != "$NEW_IMAGE" ]; then
  echo "==> Rolling back to ${PREVIOUS_IMAGE}" >&2
  start_container "$PREVIOUS_IMAGE"
  if wait_until_healthy; then
    echo "==> Rollback succeeded; the previous image is serving again." >&2
  else
    echo "ERROR: rollback also failed to become healthy." >&2
  fi
else
  echo "==> No previous image to roll back to." >&2
fi

exit 1
