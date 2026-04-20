#!/usr/bin/env bash
# Deploy script for Authelia releases via Buildkite
set -euo pipefail

# -------------------------------------------------------
# Variables
# -------------------------------------------------------
DOCKER_IMAGE="authelia/authelia"
GIT_TAG="${BUILDKITE_TAG:-}"
GIT_BRANCH="${BUILDKITE_BRANCH:-}"
DRY_RUN="${DRY_RUN:-false}"

# -------------------------------------------------------
# Helpers
# -------------------------------------------------------
log() {
  echo "[deploy] $*"
}

die() {
  echo "[deploy][error] $*" >&2
  exit 1
}

docker_tag_and_push() {
  local source="$1"
  local target="$2"

  log "Tagging ${source} -> ${target}"
  docker tag "${source}" "${target}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "[dry-run] Skipping docker push ${target}"
  else
    docker push "${target}"
  fi
}

# -------------------------------------------------------
# Validate environment
# -------------------------------------------------------
if [[ -z "${DOCKER_USERNAME:-}" ]] || [[ -z "${DOCKER_PASSWORD:-}" ]]; then
  die "DOCKER_USERNAME and DOCKER_PASSWORD must be set"
fi

log "Logging in to Docker Hub"
echo "${DOCKER_PASSWORD}" | docker login --username "${DOCKER_USERNAME}" --password-stdin

# -------------------------------------------------------
# Determine tags to publish
# -------------------------------------------------------
TAGS=()

if [[ -n "${GIT_TAG}" ]]; then
  # Full semver tag, e.g. v4.38.0
  TAGS+=("${DOCKER_IMAGE}:${GIT_TAG}")

  # Strip leading 'v' for Docker Hub convention
  VERSION="${GIT_TAG#v}"
  TAGS+=("${DOCKER_IMAGE}:${VERSION}")

  # Major.minor floating tag, e.g. 4.38
  MINOR_TAG="$(echo "${VERSION}" | cut -d. -f1,2)"
  TAGS+=("${DOCKER_IMAGE}:${MINOR_TAG}")

  # latest only on non-pre-release tags
  if [[ ! "${VERSION}" =~ (alpha|beta|rc) ]]; then
    TAGS+=("${DOCKER_IMAGE}:latest")
  fi
elif [[ "${GIT_BRANCH}" == "master" ]]; then
  TAGS+=("${DOCKER_IMAGE}:master")
elif [[ "${GIT_BRANCH}" == "develop" ]]; then
  TAGS+=("${DOCKER_IMAGE}:develop")
else
  die "No deployable tag or branch detected (tag='${GIT_TAG}', branch='${GIT_BRANCH}')"
fi

log "Tags to publish: ${TAGS[*]}"

# -------------------------------------------------------
# Build source image name (produced by CI build step)
# -------------------------------------------------------
SOURCE_IMAGE="${DOCKER_IMAGE}:buildcache"

# -------------------------------------------------------
# Push all tags
# -------------------------------------------------------
for tag in "${TAGS[@]}"; do
  docker_tag_and_push "${SOURCE_IMAGE}" "${tag}"
done

log "Deploy complete."
