#!/usr/bin/env bash
# Teri installer — sets up ~/.teri dirs, symlinks bin/ into ~/.local/bin, and initialises the DB.
set -euo pipefail

TERI_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERI_DATA_HOME="${TERI_DATA_HOME:-$HOME/.teri}"
LOCAL_BIN="${HOME}/.local/bin"

FORCE=0
NO_PROMPT=0
for arg in "$@"; do
  case "$arg" in
    --force)     FORCE=1 ;;
    --no-prompt) NO_PROMPT=1 ;;
  esac
done

# 1. Create runtime dirs
mkdir -p \
  "${TERI_DATA_HOME}/cache/jira" \
  "${TERI_DATA_HOME}/cache/email" \
  "${TERI_DATA_HOME}/cache/calendar" \
  "${TERI_DATA_HOME}/cache/sentry" \
  "${TERI_DATA_HOME}/state" \
  "${TERI_DATA_HOME}/logs"
echo "Runtime dirs: ${TERI_DATA_HOME}"

# 2. Symlink bin/* into ~/.local/bin
mkdir -p "${LOCAL_BIN}"
for src in "${TERI_REPO_DIR}/bin"/*; do
  name="$(basename "$src")"
  dest="${LOCAL_BIN}/${name}"
  if [[ -L "$dest" ]] && [[ "$(readlink "$dest")" == "$src" ]]; then
    : # already correct symlink — no-op
  elif [[ -e "$dest" ]] && [[ $FORCE -eq 0 ]]; then
    echo "warn: ${dest} exists and is not our symlink. Pass --force to overwrite." >&2
  else
    ln -sf "$src" "$dest"
    echo "linked: ${dest} -> ${src}"
  fi
done

# 3. Copy context.env.example if no context.env yet
if [[ ! -f "${TERI_DATA_HOME}/context.env" ]]; then
  cp "${TERI_REPO_DIR}/templates/context.env.example" "${TERI_DATA_HOME}/context.env"
  echo "Edit ${TERI_DATA_HOME}/context.env with your values before first run."
fi

# 4. Initialise DB
"${TERI_REPO_DIR}/bin/teri-todo" init
echo "DB initialised."

# 5. Verify deps
missing=0
for cmd in sqlite3 jq claude; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command not found: $cmd" >&2
    missing=1
  fi
done
[[ $missing -eq 1 ]] && exit 1
command -v gh >/dev/null 2>&1 || echo "warn: gh not found — GitHub features will be unavailable."

# 6. Pre-commit hook
if [[ $NO_PROMPT -eq 0 ]] && [[ $FORCE -eq 0 ]] && [[ -t 0 ]]; then
  read -rp "Install pre-commit hook that runs scripts/check-public-safe.sh? [y/N] " answer
  answer="${answer:-N}"
else
  answer="${FORCE_HOOK_ANSWER:-N}"
fi
if [[ "$(echo "$answer" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
  hook="${TERI_REPO_DIR}/.git/hooks/pre-commit"
  cat > "$hook" << 'HOOK'
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
exec "${REPO_ROOT}/scripts/check-public-safe.sh"
HOOK
  chmod +x "$hook"
  echo "pre-commit hook installed."
fi

# 7. Next steps
cat << EOF

=== Teri installed ===
Launch:   teri
Context:  ${TERI_DATA_HOME}/context.env
Logs:     ${TERI_DATA_HOME}/logs/teri.log
DB:       ${TERI_DATA_HOME}/teri.db

Make sure ${LOCAL_BIN} is in your PATH.
EOF
