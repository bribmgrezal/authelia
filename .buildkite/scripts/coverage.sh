#!/usr/bin/env bash
set -euo pipefail

# coverage.sh - Collect and report test coverage for Authelia
# Uploads coverage reports to Codecov and generates annotations.

REPO_ROOT="$(git rev-parse --show-toplevel)"
COVERAGE_DIR="${REPO_ROOT}/coverage"
GO_COVERAGE_FILE="${COVERAGE_DIR}/coverage.txt"
JS_COVERAGE_DIR="${COVERAGE_DIR}/js"

mkdir -p "${COVERAGE_DIR}"

echo "--- :go: Collecting Go coverage"
if [[ -f "${GO_COVERAGE_FILE}" ]]; then
  echo "Go coverage file found: ${GO_COVERAGE_FILE}"
  go tool cover -func="${GO_COVERAGE_FILE}" | tail -n 1
else
  echo "No Go coverage file found, skipping Go coverage report."
fi

echo "--- :javascript: Collecting JavaScript/TypeScript coverage"
if [[ -d "${JS_COVERAGE_DIR}" ]]; then
  echo "JS coverage directory found: ${JS_COVERAGE_DIR}"
else
  echo "No JS coverage directory found, skipping JS coverage report."
fi

echo "--- :codecov: Uploading coverage to Codecov"
if [[ -z "${CODECOV_TOKEN:-}" ]]; then
  echo "CODECOV_TOKEN is not set, skipping upload."
  exit 0
fi

CODECOV_FLAGS=""
if [[ -n "${BUILDKITE_BRANCH:-}" ]]; then
  CODECOV_FLAGS="--branch ${BUILDKITE_BRANCH}"
fi

if [[ -n "${BUILDKITE_COMMIT:-}" ]]; then
  CODECOV_FLAGS="${CODECOV_FLAGS} --sha ${BUILDKITE_COMMIT}"
fi

if [[ -n "${BUILDKITE_BUILD_NUMBER:-}" ]]; then
  CODECOV_FLAGS="${CODECOV_FLAGS} --build ${BUILDKITE_BUILD_NUMBER}"
fi

if [[ -f "${GO_COVERAGE_FILE}" ]]; then
  echo "Uploading Go coverage..."
  bash <(curl -s https://codecov.io/bash) \
    -t "${CODECOV_TOKEN}" \
    -f "${GO_COVERAGE_FILE}" \
    -F go \
    ${CODECOV_FLAGS} || echo "Go coverage upload failed (non-fatal)"
fi

if [[ -d "${JS_COVERAGE_DIR}" ]]; then
  echo "Uploading JS coverage..."
  bash <(curl -s https://codecov.io/bash) \
    -t "${CODECOV_TOKEN}" \
    -s "${JS_COVERAGE_DIR}" \
    -F javascript \
    ${CODECOV_FLAGS} || echo "JS coverage upload failed (non-fatal)"
fi

echo "Coverage reporting complete."
