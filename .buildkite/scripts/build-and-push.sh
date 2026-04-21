#!/usr/bin/env bash
# Build and push Docker images to the container registry.
# This script handles multi-platform builds and image tagging for releases.

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.."; pwd)"

# Default values
DOCKER_REGISTRY="${DOCKER_REGISTRY:-ghcr.io}"
DOCKER_IMAGE="${DOCKER_IMAGE:-authelia/authelia}"
DOCKER_PLATFORMS="${DOCKER_PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v7}"
BUILDKIT_PROGRESS="${BUILDKIT_PROGRESS:-plain}"

# Resolve the full image name
FULL_IMAGE="${DOCKER_REGISTRY}/${DOCKER_IMAGE}"

# Determine tags from environment
TAGS=()

if [[ -n "${BUILDKITE_TAG:-}" ]]; then
  # Tag release builds with the git tag
  TAGS+=("${FULL_IMAGE}:${BUILDKITE_TAG}")
  # Also tag as latest if this is a stable release (no pre-release suffix)
  if [[ "${BUILDKITE_TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    TAGS+=("${FULL_IMAGE}:latest")
  fi
elif [[ "${BUILDKITE_BRANCH:-}" == "master" ]]; then
  TAGS+=("${FULL_IMAGE}:master")
elif [[ -n "${BUILDKITE_BRANCH:-}" ]]; then
  # Sanitize branch name for use as a Docker tag
  SANITIZED_BRANCH="$(echo "${BUILDKITE_BRANCH}" | sed 's/[^a-zA-Z0-9._-]/-/g')"
  TAGS+=("${FULL_IMAGE}:${SANITIZED_BRANCH}")
fi

# Add commit SHA tag if available
if [[ -n "${BUILDKITE_COMMIT:-}" ]]; then
  SHORT_SHA="${BUILDKITE_COMMIT:0:8}"
  TAGS+=("${FULL_IMAGE}:${SHORT_SHA}")
fi

if [[ ${#TAGS[@]} -eq 0 ]]; then
  echo "ERROR: No tags could be determined. Exiting."
  exit 1
fi

echo "--- Building and pushing Docker image"
echo "Image:     ${FULL_IMAGE}"
echo "Tags:      ${TAGS[*]}"
echo "Platforms: ${DOCKER_PLATFORMS}"

# Ensure buildx builder is available
if ! docker buildx inspect authelia-builder &>/dev/null; then
  echo "--- Creating buildx builder instance"
  docker buildx create --name authelia-builder --driver docker-container --use
else
  docker buildx use authelia-builder
fi

echo "--- Logging in to registry: ${DOCKER_REGISTRY}"
echo "${DOCKER_PASSWORD:?DOCKER_PASSWORD is required}" | \
  docker login "${DOCKER_REGISTRY}" \
    --username "${DOCKER_USERNAME:?DOCKER_USERNAME is required}" \
    --password-stdin

# Build the tag arguments
TAG_ARGS=()
for tag in "${TAGS[@]}"; do
  TAG_ARGS+=("--tag" "${tag}")
done

echo "--- Running multi-platform build and push"
BUILDKIT_PROGRESS="${BUILDKIT_PROGRESS}" docker buildx build \
  --platform "${DOCKER_PLATFORMS}" \
  --file "${PROJECT_ROOT}/Dockerfile" \
  --provenance=false \
  --push \
  "${TAG_ARGS[@]}" \
  "${PROJECT_ROOT}"

echo "--- Build and push complete"
for tag in "${TAGS[@]}"; do
  echo "  Pushed: ${tag}"
done
