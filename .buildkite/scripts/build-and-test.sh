#!/usr/bin/env bash
set -euo pipefail

# Build and test script for Authelia CI pipeline
# Runs compilation, unit tests, and generates coverage reports

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COVERAGE_DIR="${ROOT_DIR}/coverage"
BINARY_DIR="${ROOT_DIR}/dist"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_deps() {
  local deps=("go" "golangci-lint")
  for dep in "${deps[@]}"; do
    if ! command -v "${dep}" &>/dev/null; then
      echo "ERROR: Required dependency '${dep}' not found in PATH" >&2
      exit 1
    fi
  done
}

build() {
  log "Building Authelia binary..."
  mkdir -p "${BINARY_DIR}"
  CGO_ENABLED=0 go build \
    -trimpath \
    -ldflags "-s -w -X github.com/authelia/authelia/v4/internal/utils.BuildTag=${BUILD_TAG:-dev} -X github.com/authelia/authelia/v4/internal/utils.BuildCommit=${BUILDKITE_COMMIT:-unknown} -X github.com/authelia/authelia/v4/internal/utils.BuildBranch=${BUILDKITE_BRANCH:-unknown} -X github.com/authelia/authelia/v4/internal/utils.BuildDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -o "${BINARY_DIR}/authelia" \
    ./cmd/authelia/
  log "Build complete: ${BINARY_DIR}/authelia"
}

test_unit() {
  log "Running unit tests..."
  mkdir -p "${COVERAGE_DIR}"
  go test \
    -v \
    -race \
    -coverprofile="${COVERAGE_DIR}/coverage.txt" \
    -covermode=atomic \
    -timeout=5m \
    ./internal/...
  log "Unit tests complete. Coverage report: ${COVERAGE_DIR}/coverage.txt"
}

lint() {
  log "Running linter..."
  golangci-lint run --timeout=5m ./...
  log "Lint complete."
}

generate_coverage_report() {
  log "Generating HTML coverage report..."
  go tool cover -html="${COVERAGE_DIR}/coverage.txt" -o "${COVERAGE_DIR}/coverage.html"
  log "HTML coverage report: ${COVERAGE_DIR}/coverage.html"
}

main() {
  local cmd="${1:-all}"
  cd "${ROOT_DIR}"

  check_deps

  case "${cmd}" in
    build)   build ;;
    test)    test_unit ;;
    lint)    lint ;;
    cover)   generate_coverage_report ;;
    all)
      lint
      build
      test_unit
      generate_coverage_report
      ;;
    *)
      echo "Usage: $0 {build|test|lint|cover|all}" >&2
      exit 1
      ;;
  esac
}

main "$@"
