#!/usr/bin/env bash
# Shared helpers. Source this from agent body and from bin/* scripts.
# Idempotent: safe to source multiple times.

[[ -n "${TERI_SH_LOADED:-}" ]] && return 0
TERI_SH_LOADED=1

teri_home() { echo "${TERI_DATA_HOME:-$HOME/.teri}"; }
teri_db()   { echo "$(teri_home)/teri.db"; }

teri_load_context() {
  local ctx="$(teri_home)/context.env"
  if [[ -f "$ctx" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$ctx"; set +a
  else
    teri_log warn "context.env not found at $ctx — using defaults"
  fi
}

teri_log() {
  local level="${1:-info}"; shift || true
  local msg="$*"
  local ts; ts="$(teri_now_iso)"
  mkdir -p "$(teri_home)/logs"
  printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "$(teri_home)/logs/teri.log"
  [[ "$level" == "warn" || "$level" == "error" ]] && printf '%s: %s\n' "$level" "$msg" >&2
  return 0
}

teri_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { teri_log error "missing required command: $1"; return 1; }
}

teri_now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
