#!/usr/bin/env bats
# teri-cache-refresh failure reporting. All service libs, credentials and the m365 CLI
# are stubbed: no network, no real credentials.
bats_require_minimum_version 1.5.0

setup() {
  TERI_REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TERI_REPO_ROOT
  export TERI_DATA_HOME; TERI_DATA_HOME="$(mktemp -d -t teri-test-XXXXXX)"
  export HOME; HOME="$(mktemp -d -t teri-home-XXXXXX)"
  export TERI_SERVICES_DIR="${HOME}/services"
  export TERI_CREDENTIALS_LIB="${HOME}/no-such-credentials.sh"
  export TERI_TIMEZONE="America/Chicago"
  export ATLASSIAN_SITE_NAME=example.atlassian.net ATLASSIAN_USER_EMAIL=me@example.com
  export ATLASSIAN_API_TOKEN=SECRET-SENTINEL-JIRA SENTRY_API_TOKEN=SECRET-SENTINEL-SENTRY
  mkdir -p "$TERI_SERVICES_DIR" "${HOME}/bin"
  export PATH="${TERI_REPO_ROOT}/bin:${HOME}/bin:${PATH}"
  write_healthy_libs
  write_fake_m365 '{"connectedAs":"test@example.com"}'
}

teardown() {
  [[ "$TERI_DATA_HOME" == /tmp/* || "$TERI_DATA_HOME" == /var/* ]] && rm -rf "$TERI_DATA_HOME"
  [[ "$HOME" == /tmp/* || "$HOME" == /var/* ]] && rm -rf "$HOME"
  return 0
}

write_fake_m365() {
  printf '#!/usr/bin/env bash\necho %q\n' "$1" > "${HOME}/bin/m365"
  chmod +x "${HOME}/bin/m365"
}

write_healthy_libs() {
  cat > "${TERI_SERVICES_DIR}/jira.sh" <<'LIB'
jira_search() { echo '{"issues":[{"key":"CORE-1","fields":{"summary":"Fix it","status":{"name":"In Progress"}}}]}'; }
jira_get_issue() { echo "{\"key\":\"$1\",\"fields\":{\"summary\":\"s\"}}"; }
LIB
  cat > "${TERI_SERVICES_DIR}/sentry.sh" <<'LIB'
sentry_search_issues() {
  case "$1" in
    *assigned:me*) echo '[{"id":"1","title":"mine","lastSeen":"2026-10-10T00:00:00Z"}]' ;;
    *)             echo '[{"id":"2","title":"fresh","lastSeen":"2026-10-11T00:00:00Z"},{"id":"1","title":"mine","lastSeen":"2026-10-10T00:00:00Z"}]' ;;
  esac
}
LIB
  cat > "${TERI_SERVICES_DIR}/calendar.sh" <<'LIB'
get_calendar_for_date() { echo '{"value":[{"subject":"Standup","start":{"dateTime":"2026-10-11T15:00:00.0000000"},"end":{"dateTime":"2026-10-11T15:30:00.0000000"},"location":{"displayName":"Zoom"}}]}'; }
LIB
  cat > "${TERI_SERVICES_DIR}/m365.sh" <<'LIB'
graph_request() { echo '{"totalItemCount":10,"unreadItemCount":2}'; }
graph_get_inbox_messages() { echo '{"value":[{"subject":"Hello","from":{"emailAddress":{"name":"Ann"}},"receivedDateTime":"2026-10-11T12:00:00Z","isRead":false,"bodyPreview":"private text"},{"subject":"Old","from":{"emailAddress":{"name":"Bob"}},"receivedDateTime":"2026-10-10T12:00:00Z","isRead":true}]}'; }
LIB
}

cache_file() { echo "${TERI_DATA_HOME}/cache/$1/$2.json"; }

@test "healthy: every source ok, exit 0, caches written in the shapes briefing reads" {
  run --separate-stderr teri-cache-refresh all
  [ "$status" -eq 0 ]
  [[ "$output" == *"jira "*" ok "* ]]
  [[ "$output" == *"sentry "*" ok "* ]]
  [[ "$output" == *"calendar "*" ok "* ]]
  [[ "$output" == *"email "*" ok "* ]]
  [[ "$output" == *"all 4 source(s) fetched"* ]]
  [ "$(jq 'length' "$(cache_file jira _my_issues)")" -eq 1 ]
  [ "$(jq -r '.[0].key' "$(cache_file jira _my_issues)")" = "CORE-1" ]
  # Sentry: assigned + fresh, de-duplicated by id
  [ "$(jq 'length' "$(cache_file sentry recent)")" -eq 2 ]
  # Calendar: UTC 15:00Z -> 10:00 Central
  [ "$(jq -r '.events[0].start' "$(cache_file calendar today)")" = "2026-10-11T10:00" ]
  [ "$(jq -r '.events[0].location' "$(cache_file calendar today)")" = "Zoom" ]
  # Email: unread only in top, no body preview leaked
  [ "$(jq -r '.unread_count' "$(cache_file email inbox)")" -eq 2 ]
  [ "$(jq '.top | length' "$(cache_file email inbox)")" -eq 1 ]
  ! grep -q "private text" "$(cache_file email inbox)"
}

@test "empty result: reported 'empty', cache written, exit 0" {
  echo 'jira_search() { echo "{\"issues\":[]}"; }' > "${TERI_SERVICES_DIR}/jira.sh"
  run --separate-stderr teri-cache-refresh jira
  [ "$status" -eq 0 ]
  [[ "$output" == *"jira "*" empty "* ]]
  [ "$(jq 'length' "$(cache_file jira _my_issues)")" -eq 0 ]
}

@test "missing function: FAILED with the function name, exit 1, cache untouched" {
  echo 'unrelated() { :; }' > "${TERI_SERVICES_DIR}/jira.sh"
  run --separate-stderr teri-cache-refresh jira
  [ "$status" -eq 1 ]
  [[ "$output" == *"jira "*"FAILED"*"jira_search"* ]]
  [ ! -f "$(cache_file jira _my_issues)" ]
}

@test "missing function in one source: PARTIAL summary, exit 1, others still cached" {
  echo 'unrelated() { :; }' > "${TERI_SERVICES_DIR}/sentry.sh"
  run --separate-stderr teri-cache-refresh all
  [ "$status" -eq 1 ]
  [[ "$output" == *"sentry "*"FAILED"*"sentry_search_issues"* ]]
  [[ "$output" == *"jira "*" ok "* ]]
  [[ "$output" == *"refresh: PARTIAL"*"(sentry)"* ]]
  [ -f "$(cache_file jira _my_issues)" ]
  [ ! -f "$(cache_file sentry recent)" ]
}

@test "missing service lib: FAILED naming the lib, never a silent skip" {
  rm "${TERI_SERVICES_DIR}/calendar.sh"
  run --separate-stderr teri-cache-refresh calendar
  [ "$status" -eq 1 ]
  [[ "$output" == *"calendar "*"FAILED"*"service lib not found"* ]]
}

@test "all sources failing: summary says FAILED, exit 1" {
  rm -rf "$TERI_SERVICES_DIR"
  run --separate-stderr teri-cache-refresh all
  [ "$status" -eq 1 ]
  [[ "$output" == *"refresh: FAILED (jira, sentry, calendar, email)"* ]]
}

@test "missing credentials: reports variable NAMES only" {
  unset ATLASSIAN_API_TOKEN
  run --separate-stderr teri-cache-refresh jira
  [ "$status" -eq 1 ]
  [[ "$output" == *"ATLASSIAN_API_TOKEN"* ]]
  [[ "$output" != *"SECRET-SENTINEL"* ]]
}

@test "secrets never appear in output, stderr or log" {
  echo 'jira_search() { echo "{\"errorMessages\":[\"Unauthorized\"]}"; }' > "${TERI_SERVICES_DIR}/jira.sh"
  run --separate-stderr teri-cache-refresh all
  [[ "$output" != *"SECRET-SENTINEL"* ]]
  [[ "$stderr" != *"SECRET-SENTINEL"* ]]
  ! grep -rq "SECRET-SENTINEL" "$TERI_DATA_HOME"
}

@test "API error body is a failure, not an empty result" {
  echo 'jira_search() { echo "{\"errorMessages\":[\"Unauthorized\"]}"; }' > "${TERI_SERVICES_DIR}/jira.sh"
  run --separate-stderr teri-cache-refresh jira
  [ "$status" -eq 1 ]
  [[ "$output" == *"jira "*"FAILED"*"Unauthorized"* ]]
  [ ! -f "$(cache_file jira _my_issues)" ]
}

@test "non-JSON response is a failure" {
  echo 'jira_search() { echo "<html>login</html>"; }' > "${TERI_SERVICES_DIR}/jira.sh"
  run --separate-stderr teri-cache-refresh jira
  [ "$status" -eq 1 ]
  [[ "$output" == *"jira "*"FAILED"*"non-JSON"* ]]
}

@test "m365 not logged in: calendar and email FAILED, no interactive login attempted" {
  write_fake_m365 'not connected'
  run --separate-stderr teri-cache-refresh all
  [ "$status" -eq 1 ]
  [[ "$output" == *"calendar "*"FAILED"*"not logged in"* ]]
  [[ "$output" == *"email "*"FAILED"*"not logged in"* ]]
  [[ "$output" == *"refresh: PARTIAL"* ]]
}

@test "hung source: FAILED on timeout, exit 1" {
  echo 'jira_search() { sleep 20; }' > "${TERI_SERVICES_DIR}/jira.sh"
  TERI_REFRESH_TIMEOUT=1 run --separate-stderr teri-cache-refresh jira
  [ "$status" -eq 1 ]
  [[ "$output" == *"jira "*"FAILED"*"timed out"* ]]
}

@test "jira KEY: refreshes a single issue; bad key fails" {
  run --separate-stderr teri-cache-refresh jira CORE-9
  [ "$status" -eq 0 ]
  [ "$(jq -r '.key' "$(cache_file jira CORE-9)")" = "CORE-9" ]
  run --separate-stderr teri-cache-refresh jira "not a key"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"*"invalid issue key"* ]]
}

@test "unknown subcommand: usage error exit 2" {
  run --separate-stderr teri-cache-refresh bogus
  [ "$status" -eq 2 ]
}
