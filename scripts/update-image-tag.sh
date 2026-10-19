#!/usr/bin/env bash
#
# update-image-tag.sh: set a service's image tag in one environment and push it.
#
# Run from the root of a clone of this repo. Many pipelines push here at the
# same time, so every attempt starts from the latest remote state, re-applies
# the edit and pushes. A rejected push simply retries; nothing is lost.
#
# Convention: the image placeholder in platform-apps/base/<service>/deployment.yaml has the
# same name as the service folder (base uses `image: sample-app`).
#
# Ordering: this script guarantees no update is lost, not that two builds of
# the SAME service land in build order. Serialize those in the app repo's
# workflow with a `concurrency` group (see examples/app-repo).
#
# Usage:
#   scripts/update-image-tag.sh <env> <service> <image> <tag>
#
# Example:
#   scripts/update-image-tag.sh dev payment myco.jfrog.io/docker/payment v1.4.0-develop-20260514.103022
#
# Optional environment variables:
#   GITOPS_BRANCH  branch to push to (default: main)
#   MAX_RETRIES    push attempts before giving up (default: 5)
#   SOURCE_REF     shown in the commit message, e.g. "payment@3f9c2a1"

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <env> <service> <image> <tag>" >&2
  exit 2
fi

ENV_NAME=$1
SERVICE=$2
IMAGE=$3
TAG=$4
BRANCH=${GITOPS_BRANCH:-main}
MAX_RETRIES=${MAX_RETRIES:-5}
OVERLAY="platform-apps/overlays/${ENV_NAME}/${SERVICE}"

case "$ENV_NAME" in
  dev|uat|prod) ;;
  *) echo "error: unknown environment '$ENV_NAME' (expected dev, uat or prod)" >&2; exit 2 ;;
esac

command -v kustomize >/dev/null || { echo "error: kustomize is not installed" >&2; exit 1; }

for attempt in $(seq 1 "$MAX_RETRIES"); do
  # Always start from what is on the remote right now.
  git fetch --quiet origin "$BRANCH"
  git reset --quiet --hard "origin/$BRANCH"

  if [[ ! -f "$OVERLAY/kustomization.yaml" ]]; then
    echo "error: $OVERLAY/kustomization.yaml not found" >&2
    exit 1
  fi

  (cd "$OVERLAY" && kustomize edit set image "${SERVICE}=${IMAGE}:${TAG}")

  if git diff --quiet; then
    echo "${SERVICE} in ${ENV_NAME} is already on ${TAG}. Nothing to do."
    exit 0
  fi

  git add "$OVERLAY/kustomization.yaml"
  git commit --quiet \
    -m "deploy(${SERVICE}): ${TAG} to ${ENV_NAME}" \
    -m "Source: ${SOURCE_REF:-unknown}"

  if push_out=$(git push --quiet origin "HEAD:${BRANCH}" 2>&1); then
    echo "Pushed ${SERVICE}:${TAG} to ${ENV_NAME} (attempt ${attempt})."
    exit 0
  fi

  last_error=$push_out
  wait_s=$(( attempt * 3 + RANDOM % 5 ))
  echo "Push rejected, another pipeline got there first. Retrying in ${wait_s}s..."
  sleep "$wait_s"
done

echo "error: push failed after ${MAX_RETRIES} attempts. Last git output:" >&2
echo "${last_error:-none}" >&2
exit 1
