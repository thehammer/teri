#!/usr/bin/env bash
# Database helpers. Source after lib/teri.sh.
[[ -n "${TERI_DB_SH_LOADED:-}" ]] && return 0
TERI_DB_SH_LOADED=1

db_exec() {
  sqlite3 -bail "$(teri_db)" "$@"
}

db_query() {
  sqlite3 -tabs -noheader "$(teri_db)" "$@"
}

db_query_json() {
  local result
  result="$(sqlite3 -json "$(teri_db)" "$@" 2>/dev/null)"
  if [[ -z "$result" ]]; then
    echo "[]"
  else
    echo "$result"
  fi
}

db_init() {
  local db_file
  db_file="$(teri_db)"
  local db_dir
  db_dir="$(dirname "$db_file")"
  mkdir -p "$db_dir"
  # Create file if missing and set WAL mode
  sqlite3 -bail "$db_file" "PRAGMA journal_mode=WAL;" > /dev/null
  teri_log info "db_init: ${db_file}"
}

db_migrate() {
  local db_file
  db_file="$(teri_db)"
  local current_version
  current_version="$(sqlite3 "$db_file" 'PRAGMA user_version;' 2>/dev/null || echo 0)"

  # Find all migration files, sorted
  local migrations_dir
  migrations_dir="${TERI_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/migrations"

  if [[ ! -d "$migrations_dir" ]]; then
    teri_log warn "db_migrate: no migrations dir at ${migrations_dir}"
    return 0
  fi

  local applied=0
  for migration in $(ls "$migrations_dir"/*.sql 2>/dev/null | sort); do
    # Extract version number from filename (NNN_...)
    local filename
    filename="$(basename "$migration")"
    local version
    version="$(echo "$filename" | grep -oE '^[0-9]+' | sed 's/^0*//' )"
    [[ -z "$version" ]] && version=0

    if [[ $version -gt $current_version ]]; then
      teri_log info "db_migrate: applying ${filename}"
      sqlite3 -bail "$db_file" < "$migration"
      current_version="$version"
      applied=$((applied + 1))
    fi
  done

  [[ $applied -eq 0 ]] && teri_log info "db_migrate: schema up to date (version ${current_version})"
  return 0
}
