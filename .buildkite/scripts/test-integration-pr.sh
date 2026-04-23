#!/usr/bin/env bash
# test-integration-pr.sh: Run integration tests for pull request builds.
# This script determines which integration test suites to run based on
# changed files in the PR and runs them in parallel where possible.

set -euo pipefail

# Source common environment variables and helper functions
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PR_NUMBER="${BUILDKITE_PULL_REQUEST:-false}"
BRANCH="${BUILDKITE_BRANCH:-unknown}"
COMMIT="${BUILDKITE_COMMIT:-HEAD}"
BUILD_NUMBER="${BUILDKITE_BUILD_NUMBER:-0}"
PARALLEL_JOB="${BUILDKITE_PARALLEL_JOB:-0}"
PARALLEL_JOB_COUNT="${BUILDKITE_PARALLEL_JOB_COUNT:-1}"

echo "--- :buildkite: Build Information"
echo "PR Number:          ${PR_NUMBER}"
echo "Branch:             ${BRANCH}"
echo "Commit:             ${COMMIT}"
echo "Build Number:       ${BUILD_NUMBER}"
echo "Parallel Job:       ${PARALLEL_JOB}"
echo "Parallel Job Count: ${PARALLEL_JOB_COUNT}"

# Determine the list of suites to run
SUITE_LIST=()

if [[ -n "${SUITE:-}" ]]; then
  # If a specific suite is requested, only run that one
  SUITE_LIST=("${SUITE}")
else
  # Discover all available suites from the integration test directory
  while IFS= read -r suite; do
    SUITE_LIST+=("$(basename "${suite}" .go)")
  done < <(find internal/suites -maxdepth 1 -name '*.go' -not -name '*_test.go' | sort)
fi

if [[ ${#SUITE_LIST[@]} -eq 0 ]]; then
  echo "--- :warning: No integration test suites found, exiting."
  exit 0
fi

echo "--- :test_tube: Available Suites (${#SUITE_LIST[@]} total)"
for suite in "${SUITE_LIST[@]}"; do
  echo "  - ${suite}"
done

# Determine which suites this parallel job should run
JOB_SUITES=()
for i in "${!SUITE_LIST[@]}"; do
  if (( i % PARALLEL_JOB_COUNT == PARALLEL_JOB )); then
    JOB_SUITES+=("${SUITE_LIST[$i]}")
  fi
done

if [[ ${#JOB_SUITES[@]} -eq 0 ]]; then
  echo "--- :information_source: No suites assigned to this parallel job (${PARALLEL_JOB}/${PARALLEL_JOB_COUNT}), exiting."
  exit 0
fi

echo "--- :buildkite: Suites for this job (${PARALLEL_JOB}/${PARALLEL_JOB_COUNT})"
for suite in "${JOB_SUITES[@]}"; do
  echo "  - ${suite}"
done

# Run each assigned suite
FAILED_SUITES=()
for suite in "${JOB_SUITES[@]}"; do
  echo "+++ :go: Running Suite: ${suite}"
  if ! SUITE="${suite}" bash "${script_dir}/test-integration-suite.sh"; then
    echo "^^^ +++"
    echo "--- :x: Suite '${suite}' FAILED"
    FAILED_SUITES+=("${suite}")
  else
    echo "--- :white_check_mark: Suite '${suite}' PASSED"
  fi
done

# Report results
if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
  echo "--- :x: Failed Suites"
  for suite in "${FAILED_SUITES[@]}"; do
    echo "  - ${suite}"
  done
  exit 1
fi

echo "--- :white_check_mark: All assigned suites passed"
