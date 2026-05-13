#!/usr/bin/env bash
# Pre-commit public-safety guard.
# Greps staged files (or all tracked files if nothing is staged) for
# patterns that must never land in this public repo.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)")"

# Patterns to deny (case-insensitive ERE).
# Note: patterns are built dynamically to prevent this script from self-matching.
_p1="carefeed"
_p2="atlassian"
PATTERNS=(
  "${_p1}"'\.'com
  '@'"${_p1}"'\b'
  '[a-z0-9._%+-]+\.'"${_p2}"'\.net'
  'TERI_USER_EMAIL[[:space:]]*=[[:space:]]*['"'"'"]?[^'"'"'":= ]+@[^'"'"'" ]+'
  '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'
)
unset _p1 _p2

# Collect files to scan
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  STAGED=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
else
  # Initial commit — check all tracked/staged files
  STAGED=$(git diff --cached --name-only 2>/dev/null)
fi

if [[ -z "$STAGED" ]]; then
  # Fallback: scan all tracked files
  STAGED=$(git ls-files 2>/dev/null)
fi

# Filter to text files that exist; exclude binary and safe paths
FILES=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  full="${REPO_ROOT}/${f}"
  [[ -f "$full" ]] || continue
  # Skip binary-looking extensions and this script itself (it contains the denylist patterns)
  case "$f" in
    *.png|*.jpg|*.gif|*.pdf|*.ico|*.woff|*.woff2|*.ttf|*.eot) continue ;;
    .git/*) continue ;;
    node_modules/*) continue ;;
    tests/fixtures/safe/*) continue ;;
    scripts/check-public-safe.sh) continue ;;
  esac
  FILES+=("$full")
done <<< "$STAGED"

if [[ ${#FILES[@]} -eq 0 ]]; then
  exit 0
fi

FOUND=0
declare -a HITS=()

for pattern in "${PATTERNS[@]}"; do
  while IFS= read -r hit; do
    [[ -n "$hit" ]] && HITS+=("$hit") && FOUND=1
  done < <(grep -rniE "$pattern" "${FILES[@]}" 2>/dev/null || true)
done

if [[ $FOUND -eq 1 ]]; then
  echo "public-safety check failed:"
  for hit in "${HITS[@]}"; do
    # Make path relative to repo root
    rel="${hit#${REPO_ROOT}/}"
    echo "  ${rel}"
  done
  echo "Refusing to commit. Move tenant-specific values to ~/.teri/context.env."
  exit 1
fi

exit 0
