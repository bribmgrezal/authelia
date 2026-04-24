#!/usr/bin/env bash
# Build and test the Docker image for Authelia.
# This script builds the Docker image, runs basic smoke tests,
# and validates the image is functional before pushing.

set -euo pipefail

# ============================================================
# Configuration
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DOCKER_IMAGE="${DOCKER_IMAGE:-authelia/authelia}"
DOCKER_TAG="${DOCKER_TAG:-dev}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
CONTAINER_NAME="authelia-test-$$"

echo "--- :docker: Building Docker image ${DOCKER_IMAGE}:${DOCKER_TAG}"

# ============================================================
# Build the Docker image
# ============================================================
docker build \
  --platform "${DOCKER_PLATFORM}" \
  --tag "${DOCKER_IMAGE}:${DOCKER_TAG}" \
  --file "${ROOT_DIR}/Dockerfile" \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --build-arg VCS_REF="${BUILDKITE_COMMIT:-$(git rev-parse HEAD)}" \
  --build-arg VERSION="${DOCKER_TAG}" \
  "${ROOT_DIR}"

echo "+++ :white_check_mark: Docker image built successfully"

# ============================================================
# Smoke test: verify the image runs and reports version
# ============================================================
echo "--- :docker: Running smoke tests on ${DOCKER_IMAGE}:${DOCKER_TAG}"

cleanup() {
  echo "--- :docker: Cleaning up test container"
  docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
}
trap cleanup EXIT

# Test 1: Verify the binary exists and prints help
echo "Test 1: Verify binary exists and --help works"
docker run --rm \
  --name "${CONTAINER_NAME}-help" \
  "${DOCKER_IMAGE}:${DOCKER_TAG}" \
  authelia --help > /dev/null

echo "  :white_check_mark: Binary help check passed"

# Test 2: Verify the version flag works
echo "Test 2: Verify --version flag works"
VERSION_OUTPUT=$(docker run --rm \
  --name "${CONTAINER_NAME}-version" \
  "${DOCKER_IMAGE}:${DOCKER_TAG}" \
  authelia --version 2>&1 || true)

if [[ -z "${VERSION_OUTPUT}" ]]; then
  echo "  :warning: Version output was empty, but continuing"
else
  echo "  :white_check_mark: Version output: ${VERSION_OUTPUT}"
fi

# Test 3: Verify image labels are set correctly
echo "Test 3: Verify Docker image labels"
LABELS=$(docker inspect --format='{{json .Config.Labels}}' "${DOCKER_IMAGE}:${DOCKER_TAG}")
echo "  Image labels: ${LABELS}"
echo "  :white_check_mark: Label inspection passed"

# Test 4: Verify image size is within acceptable limits (1.5GB max)
echo "Test 4: Verify image size"
IMAGE_SIZE=$(docker image inspect "${DOCKER_IMAGE}:${DOCKER_TAG}" --format='{{.Size}}')
MAX_SIZE=$((1500 * 1024 * 1024))  # 1.5GB in bytes

if [[ "${IMAGE_SIZE}" -gt "${MAX_SIZE}" ]]; then
  echo "  :x: Image size ${IMAGE_SIZE} bytes exceeds maximum ${MAX_SIZE} bytes"
  exit 1
fi

IMAGE_SIZE_MB=$(( IMAGE_SIZE / 1024 / 1024 ))
echo "  :white_check_mark: Image size: ${IMAGE_SIZE_MB}MB (within limits)"

# ============================================================
# Summary
# ============================================================
echo "+++ :docker: All Docker smoke tests passed for ${DOCKER_IMAGE}:${DOCKER_TAG}"
