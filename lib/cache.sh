#!/usr/bin/env bash
# Cache helpers. Source after lib/teri.sh.
[[ -n "${TERI_CACHE_SH_LOADED:-}" ]] && return 0
TERI_CACHE_SH_LOADED=1

# Sanitise a cache key: only [A-Za-z0-9._-], others become _
_cache_sanitize_key() {
  echo "$1" | sed 's/[^A-Za-z0-9._-]/_/g'
}

cache_path() {
  local ns="$1"
  local key; key="$(_cache_sanitize_key "$2")"
  echo "$(teri_home)/cache/${ns}/${key}.json"
}

cache_get() {
  local ns="$1"
  local key="$2"
  local ttl_seconds="${3:-}"

  local path; path="$(cache_path "$ns" "$key")"
  [[ -f "$path" ]] || return 1

  if [[ -n "$ttl_seconds" ]]; then
    local mtime; mtime="$(stat -f %m "$path" 2>/dev/null || echo 0)"
    local now; now="$(date +%s)"
    local age=$(( now - mtime ))
    [[ $age -le $ttl_seconds ]] || return 1
  fi

  cat "$path"
  return 0
}

cache_put() {
  local ns="$1"
  local key="$2"
  local content="$3"

  local path; path="$(cache_path "$ns" "$key")"
  local dir; dir="$(dirname "$path")"
  mkdir -p "$dir"

  local tmp; tmp="$(mktemp "${dir}/.tmp.XXXXXX")"
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$path"
  return 0
}

cache_invalidate() {
  local ns="$1"
  local key="${2:-}"

  if [[ -n "$key" ]]; then
    local path; path="$(cache_path "$ns" "$key")"
    rm -f "$path"
  else
    rm -rf "$(teri_home)/cache/${ns}"
  fi
  return 0
}
