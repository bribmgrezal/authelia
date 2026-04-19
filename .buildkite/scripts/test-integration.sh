#!/usr/bin/env bash
set -euo pipefail

# Integration test runner script for Authelia CI pipeline.
# Handles environment setup, suite selection, and result reporting.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE=${SUITE:-""}
LOG_LEVEL=${LOG_LEVEL:-"info"}
RETRY_COUNT=${RETRY_COUNT:-2}
ARTIFACT_DIR="${REPO_ROOT}/integration-logs"

echo "--- :go: Integration Test Setup"

mkdir -p "${ARTIFACT_DIR}"

if [[ -z "${SUITE}" ]]; then
  echo "ERROR: SUITE environment variable must be set."
  exit 1
fi

echo "Running integration suite: ${SUITE}"
echo "Log level: ${LOG_LEVEL}"
echo "Retry count: ${RETRY_COUNT}"

# Ensure required tools are available
for cmd in docker docker-compose go; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "ERROR: Required command '${cmd}' not found in PATH."
    exit 1
  fi
done

echo "--- :docker: Starting test environment"

# Bring up the integration environment
docker-compose \
  -f "${REPO_ROOT}/internal/suites/docker-compose.yml" \
  up -d --build 2>&1 | tee "${ARTIFACT_DIR}/docker-compose-up.log"

cleanup() {
  echo "--- :docker: Tearing down test environment"
  docker-compose \
    -f "${REPO_ROOT}/internal/suites/docker-compose.yml" \
    down --volumes --remove-orphans 2>&1 | tee "${ARTIFACT_DIR}/docker-compose-down.log" || true

  echo "--- :file_folder: Collecting logs"
  docker-compose \
    -f "${REPO_ROOT}/internal/suites/docker-compose.yml" \
    logs --no-color 2>&1 > "${ARTIFACT_DIR}/docker-compose-services.log" || true
}

trap cleanup EXIT

echo "--- :test_tube: Running suite: ${SUITE}"

RUN_ARGS=(
  "--log-level" "${LOG_LEVEL}"
  "--suite" "${SUITE}"
  "--artifacts-dir" "${ARTIFACT_DIR}"
)

attempt=0
success=false

while [[ ${attempt} -le ${RETRY_COUNT} ]]; do
  attempt=$((attempt + 1))
  echo "Attempt ${attempt} of $((RETRY_COUNT + 1))"

  if go run "${REPO_ROOT}/cmd/authelia-suitetest/main.go" "${RUN_ARGS[@]}" \
      2>&1 | tee "${ARTIFACT_DIR}/suite-${SUITE}-attempt-${attempt}.log"; then
    success=true
    break
  else
    echo "Suite run failed on attempt ${attempt}."
    if [[ ${attempt} -le ${RETRY_COUNT} ]]; then
      echo "Retrying in 10 seconds..."
      sleep 10
    fi
  fi
done

if [[ "${success}" != "true" ]]; then
  echo "^^^ +++"
  echo "Integration suite '${SUITE}' failed after $((RETRY_COUNT + 1)) attempt(s)."
  exit 1
fi

echo "+++ :white_check_mark: Suite '${SUITE}' passed."
