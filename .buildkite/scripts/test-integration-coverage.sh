#!/usr/bin/env bash
set -euo pipefail

# Script to run integration tests with coverage reporting
# This script is called by the Buildkite pipeline after integration tests complete

REPO_ROOT=$(git rev-parse --show-toplevel)
COVERAGE_DIR="${REPO_ROOT}/coverage"
INTEGRATION_COVERAGE_FILE="${COVERAGE_DIR}/integration.coverage"
MERGED_COVERAGE_FILE="${COVERAGE_DIR}/merged.coverage"

echo "--- Setting up coverage directory"
mkdir -p "${COVERAGE_DIR}"

echo "--- Running integration tests with coverage"
cd "${REPO_ROOT}"

# Check if go is available
if ! command -v go &> /dev/null; then
  echo "Error: go is not installed or not in PATH"
  exit 1
fi

# Run integration tests with coverage enabled
go test \
  -v \
  -coverprofile="${INTEGRATION_COVERAGE_FILE}" \
  -covermode=atomic \
  -timeout=300s \
  ./internal/... \
  -tags integration \
  2>&1 | tee "${COVERAGE_DIR}/integration-test-output.log"

TEST_EXIT_CODE=${PIPESTATUS[0]}

if [[ ${TEST_EXIT_CODE} -ne 0 ]]; then
  echo "^^^ +++"
  echo "Integration tests failed with exit code ${TEST_EXIT_CODE}"
fi

# Merge unit and integration coverage if unit coverage exists
if [[ -f "${COVERAGE_DIR}/unit.coverage" ]]; then
  echo "--- Merging unit and integration coverage reports"

  if ! command -v gocovmerge &> /dev/null; then
    echo "Installing gocovmerge..."
    go install github.com/wadey/gocovmerge@latest
  fi

  gocovmerge \
    "${COVERAGE_DIR}/unit.coverage" \
    "${INTEGRATION_COVERAGE_FILE}" \
    > "${MERGED_COVERAGE_FILE}"

  echo "Merged coverage written to ${MERGED_COVERAGE_FILE}"
else
  echo "Unit coverage not found, skipping merge step"
  cp "${INTEGRATION_COVERAGE_FILE}" "${MERGED_COVERAGE_FILE}"
fi

# Generate HTML coverage report
echo "--- Generating HTML coverage report"
go tool cover \
  -html="${MERGED_COVERAGE_FILE}" \
  -o "${COVERAGE_DIR}/coverage.html"

# Print coverage summary
echo "--- Coverage Summary"
go tool cover -func="${MERGED_COVERAGE_FILE}" | tail -1

echo "Coverage report available at ${COVERAGE_DIR}/coverage.html"

exit ${TEST_EXIT_CODE}
