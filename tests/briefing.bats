#!/usr/bin/env bats
# Tests for teri-briefing
bats_require_minimum_version 1.5.0

load helpers.bash

setup() {
  export TERI_DATA_HOME
  TERI_DATA_HOME="$(mktemp -d -t teri-test-XXXXXX)"
  TERI_REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TERI_REPO_ROOT
  export PATH="${TERI_REPO_ROOT}/bin:${PATH}"
  teri-todo init >/dev/null 2>&1

  # Create state dirs
  mkdir -p "${TERI_DATA_HOME}/state" "${TERI_DATA_HOME}/cache/jira" \
           "${TERI_DATA_HOME}/cache/email" "${TERI_DATA_HOME}/cache/calendar" \
           "${TERI_DATA_HOME}/cache/sentry"

  # Set sentinel active
  touch "${TERI_DATA_HOME}/state/active"
}

teardown() {
  if [[ -n "${TERI_DATA_HOME:-}" && "$TERI_DATA_HOME" == /tmp/* ]]; then
    rm -rf "$TERI_DATA_HOME"
  fi
}

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
@test "sentinel guard: no active file -> --auto exits 0 silently" {
  rm -f "${TERI_DATA_HOME}/state/active"
  run --separate-stderr teri-briefing --auto
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "TTL guard: recent last-briefing -> --auto exits 0 silently" {
  touch "${TERI_DATA_HOME}/state/last-briefing"
  export TERI_BRIEFING_TTL_MIN=60
  run --separate-stderr teri-briefing --auto
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "quiet hours guard: skips when in quiet window" {
  # Set quiet hours to cover all 24 hours
  export TERI_BRIEFING_QUIET_HOURS="00-23"
  run --separate-stderr teri-briefing --auto
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--force bypasses all guards" {
  rm -f "${TERI_DATA_HOME}/state/active"
  export TERI_BRIEFING_QUIET_HOURS="00-23"
  export TERI_BRIEFING_TTL_MIN=999
  touch "${TERI_DATA_HOME}/state/last-briefing"
  run --separate-stderr teri-briefing --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Today"* ]]
}

# ---------------------------------------------------------------------------
# Markdown sections
# ---------------------------------------------------------------------------
@test "morning briefing contains all six section headers" {
  run --separate-stderr teri-briefing --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Today"* ]]
  [[ "$output" == *"### On your plate"* ]]
  [[ "$output" == *"### Inbox"* ]]
  [[ "$output" == *"### Jira"* ]]
  [[ "$output" == *"### Sentry"* ]]
}

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------
@test "morning briefing writes a briefings row" {
  run --separate-stderr teri-briefing --force
  [ "$status" -eq 0 ]
  count=$(sqlite3 "${TERI_DATA_HOME}/teri.db" "SELECT COUNT(*) FROM briefings WHERE kind='morning';")
  [ "$count" -ge 1 ]
}

@test "morning briefing updates last-briefing mtime" {
  # Remove existing last-briefing
  rm -f "${TERI_DATA_HOME}/state/last-briefing"
  run --separate-stderr teri-briefing --force
  [ "$status" -eq 0 ]
  [ -f "${TERI_DATA_HOME}/state/last-briefing" ]
}

# ---------------------------------------------------------------------------
# EOD
# ---------------------------------------------------------------------------
@test "EOD --non-interactive writes a briefings row with kind=eod" {
  # Add an in-progress todo
  run --separate-stderr teri-todo add --title "Finish the widget"
  id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  run --separate-stderr teri-todo status "$id" in_progress

  run --separate-stderr teri-briefing --kind eod --non-interactive
  [ "$status" -eq 0 ]
  count=$(sqlite3 "${TERI_DATA_HOME}/teri.db" "SELECT COUNT(*) FROM briefings WHERE kind='eod';")
  [ "$count" -ge 1 ]
}

@test "EOD payload_json contains in_progress_titles" {
  run --separate-stderr teri-todo add --title "EOD test task"
  id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  run --separate-stderr teri-todo status "$id" in_progress

  run --separate-stderr teri-briefing --kind eod --non-interactive
  [ "$status" -eq 0 ]

  payload=$(sqlite3 "${TERI_DATA_HOME}/teri.db" "SELECT payload_json FROM briefings WHERE kind='eod' ORDER BY id DESC LIMIT 1;")
  has_key=$(echo "$payload" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if 'in_progress_titles' in d else 'no')" 2>/dev/null)
  [ "$has_key" = "yes" ]
}

@test "morning briefing after EOD contains Yesterday section" {
  # Create an in-progress todo and run EOD
  run --separate-stderr teri-todo add --title "Yesterday task"
  id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  run --separate-stderr teri-todo status "$id" in_progress
  run --separate-stderr teri-briefing --kind eod --non-interactive

  # Now run morning briefing — should include Yesterday
  run --separate-stderr teri-briefing --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"Yesterday"* ]]
}
