#!/usr/bin/env bash
set -euo pipefail

# test-unit.sh - Run unit tests for Authelia with coverage reporting

echo "--- :go: Setting up Go environment"
export GOPATH="${HOME}/go"
export PATH="${GOPATH}/bin:${PATH}"

echo "--- :go: Downloading Go modules"
go mod download

echo "--- :test_tube: Running unit tests"
go test \
  -v \
  -coverprofile=coverage.txt \
  -covermode=atomic \
  -coverpkg=./... \
  ./internal/... \
  2>&1 | tee test-output.txt

TEST_EXIT=${PIPESTATUS[0]}

echo "--- :bar_chart: Generating coverage report"
if [[ -f coverage.txt ]]; then
  go tool cover -html=coverage.txt -o coverage.html
  go tool cover -func=coverage.txt | tail -1
fi

echo "--- :junit: Converting test output to JUnit XML"
if command -v go-junit-report &>/dev/null; then
  go-junit-report -set-exit-code < test-output.txt > junit-unit.xml
else
  echo "go-junit-report not found, skipping JUnit conversion"
fi

echo "--- :buildkite: Uploading artifacts"
if [[ -f junit-unit.xml ]]; then
  buildkite-agent artifact upload junit-unit.xml
fi

if [[ -f coverage.html ]]; then
  buildkite-agent artifact upload coverage.html
fi

if [[ -f coverage.txt ]]; then
  buildkite-agent artifact upload coverage.txt
fi

if [[ ${TEST_EXIT} -ne 0 ]]; then
  echo "^^^ +++"
  echo ":x: Unit tests failed with exit code ${TEST_EXIT}"
  exit ${TEST_EXIT}
fi

echo ":white_check_mark: Unit tests passed successfully"
