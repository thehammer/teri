#!/usr/bin/env bats
# Tests for teri-capture
bats_require_minimum_version 1.5.0

load helpers.bash

@test "capture: JSON stdin creates sub_agent row" {
  run --separate-stderr bash -c "echo '{\"title\":\"Captured task\"}' | teri-capture"
  [ "$status" -eq 0 ]
  id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  [[ "$id" =~ ^[0-9]+$ ]]

  src=$(sqlite3 "${TERI_DATA_HOME}/teri.db" "SELECT source FROM todos WHERE id=${id};")
  [ "$src" = "sub_agent" ]

  ok=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['ok'])")
  [ "$ok" = "True" ]
}

@test "capture: flag path creates row" {
  run --separate-stderr teri-capture --title "Flag task" --priority 2
  [ "$status" -eq 0 ]
  id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  [[ "$id" =~ ^[0-9]+$ ]]
}

@test "capture: missing title exits 2 with error JSON" {
  run --separate-stderr bash -c "echo '{}' | teri-capture"
  [ "$status" -eq 2 ]
  err=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['error'])")
  [ "$err" = "title required" ]
}

@test "capture: idempotency key prevents duplicate" {
  run --separate-stderr bash -c "echo '{\"title\":\"Idem cap\",\"idempotency_key\":\"cap-idem-1\"}' | teri-capture"
  [ "$status" -eq 0 ]
  id1=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

  run --separate-stderr bash -c "echo '{\"title\":\"Idem cap dup\",\"idempotency_key\":\"cap-idem-1\"}' | teri-capture"
  [ "$status" -eq 0 ]
  id2=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  existed=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['existed'])")

  [ "$id1" = "$id2" ]
  [ "$existed" = "True" ]
}

@test "capture: source_ref is preserved" {
  run --separate-stderr bash -c "echo '{\"title\":\"Reftest\",\"source_ref\":\"from-slack-msg-123\"}' | teri-capture"
  [ "$status" -eq 0 ]
  id=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  ref=$(sqlite3 "${TERI_DATA_HOME}/teri.db" "SELECT source_ref FROM todos WHERE id=${id};")
  [ "$ref" = "from-slack-msg-123" ]
}
