#!/usr/bin/env bats
# Tests for teri-todo CLI
bats_require_minimum_version 1.5.0

load helpers.bash

# ---------------------------------------------------------------------------
# init
# ---------------------------------------------------------------------------
@test "init is idempotent" {
  run --separate-stderr teri-todo init
  [ "$status" -eq 0 ]
  run --separate-stderr teri-todo init
  [ "$status" -eq 0 ]
  # Schema should not have drifted — check table still exists
  run --separate-stderr sqlite3 "${TERI_DATA_HOME}/teri.db" "SELECT name FROM sqlite_master WHERE type='table' AND name='todos';"
  [ "$status" -eq 0 ]
  [ "$output" = "todos" ]
}

# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------
@test "add with only title returns valid JSON with integer id" {
  run --separate-stderr teri-todo add --title "Test task"
  [ "$status" -eq 0 ]
  id=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'])" 2>/dev/null)
  [[ "$id" =~ ^[0-9]+$ ]]
}

@test "add with all optional flags" {
  run --separate-stderr teri-todo add --title "Full task" \
    --body "Some description" \
    --priority 2 \
    --due "$(date -v +1d +%Y-%m-%d)" \
    --jira "DEMO-99" \
    --source "user" \
    --source-ref "test"
  [ "$status" -eq 0 ]
  id=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'])")
  [[ "$id" =~ ^[0-9]+$ ]]
}

@test "add missing title exits 2" {
  run --separate-stderr teri-todo add
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------
@test "add and list round-trip" {
  run --separate-stderr teri-todo add --title "List me"
  [ "$status" -eq 0 ]
  run --separate-stderr teri-todo list --json
  [ "$status" -eq 0 ]
  count=$(echo "$output" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
  [ "$count" -ge 1 ]
}

# ---------------------------------------------------------------------------
# Due date parsing
# ---------------------------------------------------------------------------
@test "due date: tomorrow" {
  expected=$(date -v +1d +"%Y-%m-%d")
  run --separate-stderr teri-todo add --title "Tomorrow task" --due "tomorrow"
  [ "$status" -eq 0 ]
  due=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('due_date',''))")
  [ "$due" = "$expected" ]
}

@test "due date: +3d" {
  expected=$(date -v +3d +"%Y-%m-%d")
  run --separate-stderr teri-todo add --title "Plus3d" --due "+3d"
  [ "$status" -eq 0 ]
  due=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('due_date',''))")
  [ "$due" = "$expected" ]
}

@test "due date: ISO passthrough" {
  run --separate-stderr teri-todo add --title "ISO task" --due "2030-12-31"
  [ "$status" -eq 0 ]
  due=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('due_date',''))")
  [ "$due" = "2030-12-31" ]
}

@test "due date: friday resolves to a date" {
  run --separate-stderr teri-todo add --title "Friday task" --due "friday"
  [ "$status" -eq 0 ]
  due=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('due_date',''))")
  [[ "$due" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

@test "invalid due date exits 2" {
  run --separate-stderr teri-todo add --title "Bad due" --due "not-a-date"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# status transitions
# ---------------------------------------------------------------------------
@test "status: open -> done sets completed_at" {
  run --separate-stderr teri-todo add --title "Status task"
  id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  run --separate-stderr teri-todo status "$id" done
  [ "$status" -eq 0 ]
  completed=$(sqlite3 "${TERI_DATA_HOME}/teri.db" "SELECT completed_at FROM todos WHERE id=${id};")
  [[ -n "$completed" ]]
}

@test "status: invalid status exits 2" {
  run --separate-stderr teri-todo add --title "Status task 2"
  id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  run --separate-stderr teri-todo status "$id" "exploded"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# snooze
# ---------------------------------------------------------------------------
@test "snooze hides row from default list" {
  run --separate-stderr teri-todo add --title "Snoozeable"
  id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  run --separate-stderr teri-todo snooze "$id" "+5d"
  [ "$status" -eq 0 ]
  run --separate-stderr teri-todo list --json
  count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len([t for t in d if t['id']==${id}]))")
  [ "$count" -eq 0 ]
}

@test "snooze: --include-snoozed reveals snoozed row" {
  run --separate-stderr teri-todo add --title "Snoozeable2"
  id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  run --separate-stderr teri-todo snooze "$id" "+5d"
  run --separate-stderr teri-todo list --json --include-snoozed
  count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len([t for t in d if t['id']==${id}]))")
  [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# search
# ---------------------------------------------------------------------------
@test "search matches title" {
  run --separate-stderr teri-todo add --title "Unicorn task for testing"
  run --separate-stderr teri-todo search "Unicorn" --json
  [ "$status" -eq 0 ]
  count=$(echo "$output" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
  [ "$count" -ge 1 ]
}

# ---------------------------------------------------------------------------
# from-jira
# ---------------------------------------------------------------------------
@test "from-jira: creates todo from fixture" {
  # Stage the fixture in the test data dir
  mkdir -p "${TERI_DATA_HOME}/cache/jira"
  cp "${TERI_REPO_ROOT}/tests/fixtures/jira/DEMO-1.json" "${TERI_DATA_HOME}/cache/jira/DEMO-1.json"

  run --separate-stderr teri-todo from-jira DEMO-1
  [ "$status" -eq 0 ]
  id=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))")
  [[ "$id" =~ ^[0-9]+$ ]]

  # Verify source=jira and jira_key=DEMO-1
  jira_key=$(sqlite3 "${TERI_DATA_HOME}/teri.db" "SELECT jira_key FROM todos WHERE id=${id};")
  [ "$jira_key" = "DEMO-1" ]
  src=$(sqlite3 "${TERI_DATA_HOME}/teri.db" "SELECT source FROM todos WHERE id=${id};")
  [ "$src" = "jira" ]
}

@test "from-jira: re-import returns same id with existed=true" {
  mkdir -p "${TERI_DATA_HOME}/cache/jira"
  cp "${TERI_REPO_ROOT}/tests/fixtures/jira/DEMO-1.json" "${TERI_DATA_HOME}/cache/jira/DEMO-1.json"

  run --separate-stderr teri-todo from-jira DEMO-1
  [ "$status" -eq 0 ]
  id1=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

  run --separate-stderr teri-todo from-jira DEMO-1
  [ "$status" -eq 0 ]
  id2=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  existed=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('existed', False))")

  [ "$id1" = "$id2" ]
  [ "$existed" = "True" ]
}

@test "from-jira: missing cache exits 3" {
  run --separate-stderr teri-todo from-jira DEMO-NOCACHE
  [ "$status" -eq 3 ]
}

# ---------------------------------------------------------------------------
# idempotency key
# ---------------------------------------------------------------------------
@test "add with duplicate idempotency-key returns same id" {
  run --separate-stderr teri-todo add --title "Idem task" --idempotency-key "test-idem-key"
  [ "$status" -eq 0 ]
  id1=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

  run --separate-stderr teri-todo add --title "Idem task dup" --idempotency-key "test-idem-key"
  [ "$status" -eq 0 ]
  id2=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  existed=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('existed', False))")

  [ "$id1" = "$id2" ]
  [ "$existed" = "True" ]
}
