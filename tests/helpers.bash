#!/usr/bin/env bash
# Shared test helpers for bats suites.
bats_require_minimum_version 1.5.0

# Called before each test
setup() {
  export TERI_DATA_HOME
  TERI_DATA_HOME="$(mktemp -d -t teri-test-XXXXXX)"

  # Put teri bin/ on PATH first
  TERI_REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TERI_REPO_ROOT
  export PATH="${TERI_REPO_ROOT}/bin:${PATH}"

  # Initialise DB
  teri-todo init >/dev/null
}

# Called after each test
teardown() {
  if [[ -n "${TERI_DATA_HOME:-}" && "$TERI_DATA_HOME" == /tmp/* ]]; then
    rm -rf "$TERI_DATA_HOME"
  fi
}
