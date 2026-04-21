#!/usr/bin/env bash
# This script runs unit tests with coverage reporting and uploads results
# to the coverage service configured in the CI environment.
set -euo pipefail

# Source common environment variables and helper functions
if [[ -f ".buildkite/scripts/common.sh" ]]; then
  # shellcheck source=.buildkite/scripts/common.sh
  source ".buildkite/scripts/common.sh"
fi

COVERAGE_DIR="${COVERAGE_DIR:-coverage}"
COVERAGE_PROFILE="${COVERAGE_DIR}/coverage.txt"
COVERAGE_HTML="${COVERAGE_DIR}/coverage.html"
MIN_COVERAGE="${MIN_COVERAGE:-50}"

echo "--- :go: Setting up Go environment"
go version

echo "--- :broom: Cleaning previous coverage artifacts"
rm -rf "${COVERAGE_DIR}"
mkdir -p "${COVERAGE_DIR}"

echo "+++ :go: Running unit tests with coverage"
go test \
  -v \
  -race \
  -coverprofile="${COVERAGE_PROFILE}" \
  -covermode=atomic \
  -timeout=10m \
  ./internal/... \
  2>&1 | tee "${COVERAGE_DIR}/unit-test-output.txt"

TEST_EXIT_CODE=${PIPESTATUS[0]}

echo "--- :bar_chart: Generating coverage HTML report"
go tool cover -html="${COVERAGE_PROFILE}" -o "${COVERAGE_HTML}"

echo "--- :bar_chart: Coverage summary"
go tool cover -func="${COVERAGE_PROFILE}" | tail -n 1

# Extract total coverage percentage
TOTAL_COVERAGE=$(go tool cover -func="${COVERAGE_PROFILE}" | grep total | awk '{print $3}' | tr -d '%')
echo "Total coverage: ${TOTAL_COVERAGE}%"

# Check if coverage meets minimum threshold
if (( $(echo "${TOTAL_COVERAGE} < ${MIN_COVERAGE}" | bc -l) )); then
  echo "^^^ +++"
  echo ":warning: Coverage ${TOTAL_COVERAGE}% is below minimum threshold of ${MIN_COVERAGE}%"
else
  echo ":white_check_mark: Coverage ${TOTAL_COVERAGE}% meets minimum threshold of ${MIN_COVERAGE}%"
fi

# Upload coverage to Codecov if token is available
if [[ -n "${CODECOV_TOKEN:-}" ]]; then
  echo "--- :codecov: Uploading coverage to Codecov"
  if command -v codecov &>/dev/null; then
    codecov \
      --token="${CODECOV_TOKEN}" \
      --file="${COVERAGE_PROFILE}" \
      --flags=unit \
      --name="unit-tests" \
      --nonZero
  else
    echo "codecov binary not found, skipping upload"
  fi
fi

# Upload artifacts
if [[ -f "${COVERAGE_HTML}" ]]; then
  echo "--- :buildkite: Uploading coverage artifacts"
  buildkite-agent artifact upload "${COVERAGE_DIR}/**/*" || true
fi

exit "${TEST_EXIT_CODE}"
