#!/usr/bin/env bats
# Tests for lib/cache.sh and teri-cache-refresh
bats_require_minimum_version 1.5.0

load helpers.bash

setup() {
  export TERI_DATA_HOME
  TERI_DATA_HOME="$(mktemp -d -t teri-test-XXXXXX)"
  TERI_REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TERI_REPO_ROOT
  export PATH="${TERI_REPO_ROOT}/bin:${PATH}"
  # Source the libs so cache_* functions are available
  source "${TERI_REPO_ROOT}/lib/teri.sh"
  source "${TERI_REPO_ROOT}/lib/cache.sh"
}

teardown() {
  if [[ -n "${TERI_DATA_HOME:-}" && "$TERI_DATA_HOME" == /tmp/* ]]; then
    rm -rf "$TERI_DATA_HOME"
  fi
}

@test "cache_put and cache_get round-trip" {
  cache_put "test" "mykey" '{"foo":"bar"}'
  result=$(cache_get "test" "mykey")
  [ "$result" = '{"foo":"bar"}' ]
}

@test "cache_get: missing file exits 1" {
  run cache_get "test" "nonexistent"
  [ "$status" -eq 1 ]
}

@test "cache_get: within TTL returns content" {
  cache_put "test" "ttlkey" '{"x":1}'
  result=$(cache_get "test" "ttlkey" 3600)
  [ "$result" = '{"x":1}' ]
}

@test "cache_get: expired TTL exits 1" {
  cache_put "test" "expired" '{"x":2}'
  # Set mtime to 2 hours ago
  local path="${TERI_DATA_HOME}/cache/test/expired.json"
  touch -t "$(date -v -2H +%Y%m%d%H%M.%S)" "$path"
  run cache_get "test" "expired" 3600
  [ "$status" -eq 1 ]
}

@test "cache_sanitize: weird characters in key become underscore" {
  cache_put "test" "key with spaces/and/slashes" '{"sanitized":true}'
  # The file should exist — key was sanitized
  find "${TERI_DATA_HOME}/cache/test/" -name "*.json" | grep -q .
}

@test "cache_invalidate: removes single file" {
  cache_put "test" "todel" '{"bye":true}'
  cache_invalidate "test" "todel"
  run cache_get "test" "todel"
  [ "$status" -eq 1 ]
}

@test "cache_invalidate: removes whole namespace dir" {
  cache_put "ns1" "a" '{"a":1}'
  cache_put "ns1" "b" '{"b":2}'
  cache_invalidate "ns1"
  [ ! -d "${TERI_DATA_HOME}/cache/ns1" ]
}

@test "teri-cache-refresh all: exits 0 with no service libs" {
  # Use a fresh HOME with no service libs
  local fake_home
  fake_home="$(mktemp -d -t teri-home-XXXXXX)"
  HOME="$fake_home" run --separate-stderr teri-cache-refresh all
  rm -rf "$fake_home"
  [ "$status" -eq 0 ]
}
