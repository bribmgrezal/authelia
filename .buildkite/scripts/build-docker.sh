#!/usr/bin/env bash
# Build and optionally push Docker images for Authelia.
# This script is intended to be run from the root of the repository.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
IMAGE_NAME="${DOCKER_IMAGE:-authelia/authelia}"
PLATFORMS="${DOCKER_PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v7}"
BUILDX_BUILDER="${BUILDX_BUILDER:-authelia-builder}"
PUSH="${DOCKER_PUSH:-false}"

# Determine the image tag from the environment or git describe.
if [[ -n "${BUILDKITE_TAG:-}" ]]; then
  TAG="${BUILDKITE_TAG}"
elif [[ -n "${BUILDKITE_BRANCH:-}" ]]; then
  # Sanitise branch name for use as a Docker tag.
  TAG="$(echo "${BUILDKITE_BRANCH}" | sed 's/[^a-zA-Z0-9._-]/-/g')"
else
  TAG="$(git describe --tags --always --dirty 2>/dev/null || echo 'dev')"
fi

FULL_IMAGE="${IMAGE_NAME}:${TAG}"

echo "--- :docker: Build configuration"
echo "  Image   : ${FULL_IMAGE}"
echo "  Platforms: ${PLATFORMS}"
echo "  Push    : ${PUSH}"

# ---------------------------------------------------------------------------
# Ensure a buildx builder with multi-platform support exists.
# ---------------------------------------------------------------------------
echo "--- :docker: Ensuring buildx builder '${BUILDX_BUILDER}'"
if ! docker buildx inspect "${BUILDX_BUILDER}" &>/dev/null; then
  docker buildx create \
    --name "${BUILDX_BUILDER}" \
    --driver docker-container \
    --use
else
  docker buildx use "${BUILDX_BUILDER}"
fi

docker buildx inspect --bootstrap

# ---------------------------------------------------------------------------
# Build (and optionally push) the image.
# ---------------------------------------------------------------------------
echo "--- :docker: Building image ${FULL_IMAGE}"

BUILD_ARGS=(
  buildx build
  --platform "${PLATFORMS}"
  --tag "${FULL_IMAGE}"
  --label "org.opencontainers.image.revision=${BUILDKITE_COMMIT:-$(git rev-parse HEAD)}"
  --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  --label "org.opencontainers.image.version=${TAG}"
  --file Dockerfile
)

# If this is a tagged release also apply a 'latest' tag.
if [[ "${PUSH}" == "true" ]]; then
  BUILD_ARGS+=("--push")
  if [[ -n "${BUILDKITE_TAG:-}" ]]; then
    BUILD_ARGS+=("--tag" "${IMAGE_NAME}:latest")
    echo "  Also tagging as: ${IMAGE_NAME}:latest"
  fi
else
  # Without --push we load into the local daemon (single-platform only).
  BUILD_ARGS+=("--load")
  # Override platforms to the local arch when loading.
  BUILD_ARGS[2]="$(go env GOOS)/$(go env GOARCH 2>/dev/null || uname -m)"
fi

BUILD_ARGS+=(".")

docker "${BUILD_ARGS[@]}"

echo "+++ :docker: Build complete: ${FULL_IMAGE}"
