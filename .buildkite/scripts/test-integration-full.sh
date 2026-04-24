#!/usr/bin/env bash
set -euo pipefail

# test-integration-full.sh - Run the full integration test suite
# This script runs all integration tests without filtering by suite,
# collecting coverage data and generating reports.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd "${DIR}/../.." >/dev/null 2>&1 && pwd)"

# shellcheck source=.buildkite/scripts/utils.sh
if [[ -f "${DIR}/utils.sh" ]]; then
  source "${DIR}/utils.sh"
fi

echo "--- :go: Setting up environment"

export SUITE_NAME="${SUITE_NAME:-}"
export BUILDKITE_BUILD_NUMBER="${BUILDKITE_BUILD_NUMBER:-local}"
export COVERAGE_DIR="${ROOT_DIR}/coverage"
export TEST_TIMEOUT="${TEST_TIMEOUT:-300s}"
export COMPOSE_HTTP_TIMEOUT=240
export DOCKER_BUILDKIT=1

# Ensure coverage directory exists
mkdir -p "${COVERAGE_DIR}"

echo "--- :docker: Starting integration test environment"

cd "${ROOT_DIR}"

# Pull required images before running tests
if [[ -f "docker-compose.yml" ]]; then
  docker compose pull --quiet 2>/dev/null || true
fi

echo "+++ :test_tube: Running full integration test suite"

# Determine which suites to run
if [[ -n "${SUITE_NAME}" ]]; then
  echo "Running specific suite: ${SUITE_NAME}"
  SUITE_ARGS="--suite ${SUITE_NAME}"
else
  echo "Running all integration suites"
  SUITE_ARGS=""
fi

# Run the integration tests using the authelia-scripts helper
if command -v authelia-scripts &>/dev/null; then
  authelia-scripts integration ${SUITE_ARGS} \
    --coverprofile="${COVERAGE_DIR}/integration.out" \
    2>&1 | tee /tmp/integration-test-output.log
elif [[ -f "${ROOT_DIR}/cmd/authelia-scripts/main.go" ]]; then
  go run "${ROOT_DIR}/cmd/authelia-scripts/main.go" integration ${SUITE_ARGS} \
    --coverprofile="${COVERAGE_DIR}/integration.out" \
    2>&1 | tee /tmp/integration-test-output.log
else
  echo "ERROR: authelia-scripts not found, cannot run integration tests"
  exit 1
fi

TEST_EXIT_CODE=${PIPESTATUS[0]}

echo "--- :bar_chart: Processing test results"

# Convert coverage output if it exists
if [[ -f "${COVERAGE_DIR}/integration.out" ]]; then
  echo "Coverage data found, generating HTML report..."
  go tool cover \
    -html="${COVERAGE_DIR}/integration.out" \
    -o "${COVERAGE_DIR}/integration.html" || true
fi

# Parse and annotate test failures if running in Buildkite
if [[ -n "${BUILDKITE:-}" ]] && [[ -f /tmp/integration-test-output.log ]]; then
  FAILURES=$(grep -c 'FAIL\|--- FAIL' /tmp/integration-test-output.log 2>/dev/null || echo 0)
  if [[ "${FAILURES}" -gt 0 ]]; then
    echo "^^^ +++"
    echo "Integration tests had ${FAILURES} failure(s). Check logs above for details."
  fi
fi

echo "--- :clipboard: Test run complete (exit code: ${TEST_EXIT_CODE})"

exit "${TEST_EXIT_CODE}"
