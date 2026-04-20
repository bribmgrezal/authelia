#!/usr/bin/env bash
set -euo pipefail

# Test Integration Suite Script
# Runs a specific integration test suite with proper setup and teardown

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../ && pwd)"

print_info() {
  echo "--- [INFO] $*"
}

print_error() {
  echo "^^^ +++"
  echo "[ERROR] $*" >&2
}

check_required_env() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    print_error "Required environment variable '${var}' is not set."
    exit 1
  fi
}

# Required variables
check_required_env "SUITE"

SUITE_DIR="${DIR}/internal/suites"
LOGS_DIR="${DIR}/authelia-logs"
ARTIFACTS_DIR="${DIR}/authelia-artifacts"

mkdir -p "${LOGS_DIR}"
mkdir -p "${ARTIFACTS_DIR}"

print_info "Running integration suite: ${SUITE}"
print_info "Suite directory: ${SUITE_DIR}"

# Determine timeout — default to 10 minutes
TEST_TIMEOUT="${TEST_TIMEOUT:-10m}"

# Optional: filter specific test cases within the suite
TEST_FILTER="${TEST_FILTER:-}"

cd "${DIR}"

if [[ ! -d "${SUITE_DIR}/${SUITE}" ]]; then
  print_error "Suite '${SUITE}' does not exist in ${SUITE_DIR}"
  exit 1
fi

print_info "Starting suite environment..."
if ! go run ./cmd/authelia-suites/ setup "${SUITE}" 2>&1 | tee "${LOGS_DIR}/suite-setup-${SUITE}.log"; then
  print_error "Failed to setup suite '${SUITE}'"
  exit 1
fi

cleanup() {
  print_info "Tearing down suite environment..."
  go run ./cmd/authelia-suites/ teardown "${SUITE}" 2>&1 | tee "${LOGS_DIR}/suite-teardown-${SUITE}.log" || true

  # Collect logs and artifacts
  if [[ -d "${DIR}/internal/suites/${SUITE}/logs" ]]; then
    cp -r "${DIR}/internal/suites/${SUITE}/logs/" "${ARTIFACTS_DIR}/suite-${SUITE}-logs/" || true
  fi
}

trap cleanup EXIT INT TERM

print_info "Running tests for suite: ${SUITE} (timeout: ${TEST_TIMEOUT})"

TEST_ARGS=(
  "-v"
  "-timeout" "${TEST_TIMEOUT}"
  "-run" "Test${SUITE}${TEST_FILTER}"
  "./internal/suites/..."
)

if go test "${TEST_ARGS[@]}" 2>&1 | tee "${LOGS_DIR}/suite-test-${SUITE}.log"; then
  print_info "Suite '${SUITE}' passed."
else
  print_error "Suite '${SUITE}' failed. Check logs at ${LOGS_DIR}/suite-test-${SUITE}.log"
  exit 1
fi
