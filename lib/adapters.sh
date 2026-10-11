#!/usr/bin/env bash
# Teri adapters: thin wrappers over the global service libs in ~/.claude/lib/services/.
#
# teri-cache-refresh expects these functions, each printing JSON on stdout and
# returning non-zero (with a one-line reason on stderr, never a secret) on failure:
#
#   jira_fetch_my_issues            -> JSON array of issues (open + in progress, all projects)
#   jira_fetch_issue KEY            -> single issue JSON object
#   sentry_fetch_recent_unresolved  -> JSON array: assigned to me + fresh unassigned error/fatal
#   calendar_fetch_today            -> {"events":[{subject,start,end,location,...}]}
#   email_fetch_inbox_summary       -> {"count","unread_count","top":[{subject,from,received}]}
#
# Source AFTER the service libs. The libs themselves are read-only (owned by ~/.claude);
# nothing here modifies them. Tokens are never read or printed: only variable NAMES are
# checked for presence.

# --- helpers ---------------------------------------------------------------

# _teri_need_env NAME...   (names only; never prints values)
_teri_need_env() {
  local missing="" v
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || missing+="${missing:+ }$v"
  done
  if [[ -n "$missing" ]]; then
    echo "missing env var(s): $missing (set in ~/.claude/credentials/.env)" >&2
    return 1
  fi
}

# _teri_need_fn NAME LIBFILE
_teri_need_fn() {
  if ! declare -f "$1" >/dev/null 2>&1; then
    echo "function $1 not found (expected from $2; service lib changed?)" >&2
    return 127
  fi
}

# _teri_check_response JSON  -> returns 1 and prints a short reason if the response is
# empty, not JSON, or an API error object. Never echoes the raw body.
_teri_check_response() {
  local body="$1" reason
  if [[ -z "$body" ]]; then
    echo "empty response" >&2
    return 1
  fi
  if ! jq -e . >/dev/null 2>&1 <<<"$body"; then
    echo "non-JSON response (auth or network failure?)" >&2
    return 1
  fi
  reason="$(jq -r '
    if type != "object" then empty
    else (
      (.errorMessages // [] | .[0]?)
      // (.error | if type == "object" then (.message // .code) else . end)
      // .detail
      // (if (.errors|type) == "object" and (.errors|length) > 0 then (.errors|tostring) else null end)
      // empty
    ) end' <<<"$body" 2>/dev/null | head -n1 | cut -c1-160)"
  if [[ -n "$reason" ]]; then
    echo "API error: $reason" >&2
    return 1
  fi
  return 0
}

# m365 must already be logged in. Never trigger an interactive login from a refresh.
_teri_m365_ready() {
  if ! command -v m365 >/dev/null 2>&1; then
    echo "m365 CLI not on PATH" >&2
    return 1
  fi
  if ! command m365 status 2>&1 | grep -q connectedAs; then
    echo "m365 CLI not logged in (run: m365 login)" >&2
    return 1
  fi
}

# --- Jira ------------------------------------------------------------------

jira_fetch_my_issues() {
  _teri_need_fn jira_search jira.sh || return $?
  _teri_need_env ATLASSIAN_SITE_NAME ATLASSIAN_USER_EMAIL ATLASSIAN_API_TOKEN || return 1
  local jql='assignee = currentUser() AND statusCategory in ("To Do", "In Progress") ORDER BY updated DESC'
  local resp
  resp="$(jira_search "$jql" 50 2>/dev/null)" || { echo "jira_search failed" >&2; return 1; }
  _teri_check_response "$resp" || return 1
  jq -e '.issues | arrays' >/dev/null 2>&1 <<<"$resp" || { echo "unexpected Jira response shape (no .issues)" >&2; return 1; }
  jq -c '.issues' <<<"$resp"
}

jira_fetch_issue() {
  local key="${1:?issue key required}"
  [[ "$key" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]] || { echo "invalid issue key: $key" >&2; return 2; }
  _teri_need_fn jira_get_issue jira.sh || return $?
  _teri_need_env ATLASSIAN_SITE_NAME ATLASSIAN_USER_EMAIL ATLASSIAN_API_TOKEN || return 1
  local resp
  resp="$(jira_get_issue "$key" 2>/dev/null)" || { echo "jira_get_issue failed" >&2; return 1; }
  _teri_check_response "$resp" || return 1
  jq -e '.key' >/dev/null 2>&1 <<<"$resp" || { echo "unexpected Jira response shape (no .key)" >&2; return 1; }
  jq -c . <<<"$resp"
}

# --- Sentry ----------------------------------------------------------------

sentry_fetch_recent_unresolved() {
  _teri_need_fn sentry_search_issues sentry.sh || return $?
  _teri_need_env SENTRY_API_TOKEN || return 1
  local mine fresh
  mine="$(sentry_search_issues 'is:unresolved assigned:me' 2>/dev/null)" || { echo "sentry_search_issues (assigned) failed" >&2; return 1; }
  _teri_check_response "$mine" || return 1
  jq -e 'arrays' >/dev/null 2>&1 <<<"$mine" || { echo "unexpected Sentry response shape (assigned)" >&2; return 1; }
  fresh="$(sentry_search_issues 'is:unresolved is:unassigned level:[error,fatal] firstSeen:-24h' 2>/dev/null)" || { echo "sentry_search_issues (fresh) failed" >&2; return 1; }
  _teri_check_response "$fresh" || return 1
  jq -e 'arrays' >/dev/null 2>&1 <<<"$fresh" || { echo "unexpected Sentry response shape (fresh)" >&2; return 1; }
  jq -c -n --argjson a "$mine" --argjson f "$fresh" '
    ($a | map(. + {teri_bucket: "assigned"}))
    + ($f | map(. + {teri_bucket: "fresh_unassigned"}))
    | unique_by(.id) | sort_by(.lastSeen) | reverse'
}

# --- Calendar --------------------------------------------------------------

calendar_fetch_today() {
  _teri_need_fn get_calendar_for_date calendar.sh || return $?
  _teri_m365_ready || return 1
  local resp tz="${TERI_TIMEZONE:-America/New_York}"
  resp="$(get_calendar_for_date "$(date +%Y-%m-%d)" 2>/dev/null)" || { echo "get_calendar_for_date failed" >&2; return 1; }
  _teri_check_response "$resp" || return 1
  jq -e '.value | arrays' >/dev/null 2>&1 <<<"$resp" || { echo "unexpected Graph response shape (no .value)" >&2; return 1; }
  # Graph returns UTC; convert to the Teri timezone so briefings show local times.
  TERI_TZ="$tz" python3 -I -c '
import json, os, sys
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
tz = ZoneInfo(os.environ["TERI_TZ"])
def loc(s):
    if not s: return ""
    d = datetime.fromisoformat(s.split(".")[0]).replace(tzinfo=timezone.utc)
    return d.astimezone(tz).strftime("%Y-%m-%dT%H:%M")
out = []
for e in json.load(sys.stdin).get("value", []):
    out.append({
        "subject": e.get("subject") or "(no subject)",
        "start": loc((e.get("start") or {}).get("dateTime")),
        "end": loc((e.get("end") or {}).get("dateTime")),
        "location": (e.get("location") or {}).get("displayName") or "",
        "organizer": ((e.get("organizer") or {}).get("emailAddress") or {}).get("name") or "",
        "response": (e.get("responseStatus") or {}).get("response") or "",
    })
out.sort(key=lambda x: x["start"])
print(json.dumps({"timezone": os.environ["TERI_TZ"], "events": out}))
' <<<"$resp"
}

# --- Email -----------------------------------------------------------------
# Uses the existing m365 CLI session (graph_request / graph_get_inbox_messages).
# No new credentials: needs `m365 login` to be current, and Mail.Read consent.

email_fetch_inbox_summary() {
  _teri_need_fn graph_request m365.sh || return $?
  _teri_need_fn graph_get_inbox_messages m365.sh || return $?
  _teri_m365_ready || return 1
  local folder msgs
  folder="$(graph_request get '/me/mailFolders/inbox?$select=totalItemCount,unreadItemCount' 2>/dev/null)" || { echo "inbox folder request failed" >&2; return 1; }
  _teri_check_response "$folder" || return 1
  jq -e '.unreadItemCount | numbers' >/dev/null 2>&1 <<<"$folder" || { echo "unexpected Graph response shape (inbox folder)" >&2; return 1; }
  msgs="$(graph_get_inbox_messages 25 2>/dev/null)" || { echo "inbox messages request failed" >&2; return 1; }
  _teri_check_response "$msgs" || return 1
  jq -e '.value | arrays' >/dev/null 2>&1 <<<"$msgs" || { echo "unexpected Graph response shape (messages)" >&2; return 1; }
  jq -c -n --argjson f "$folder" --argjson m "$msgs" '{
    count: $f.totalItemCount,
    unread_count: $f.unreadItemCount,
    top: [ $m.value[] | select(.isRead == false) | {
      subject: (.subject // "(no subject)"),
      from: (.from.emailAddress.name // .from.emailAddress.address // ""),
      received: .receivedDateTime } ][:10]
  }'
}
