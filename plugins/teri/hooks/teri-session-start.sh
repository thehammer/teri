#!/usr/bin/env bash
set -euo pipefail

# Guard 1: only run inside a `bin/teri` session.
[[ -f "${HOME}/.teri/state/active" ]] || exit 0

# Guard 2: explicit opt-out.
[[ "${TERI_NO_BRIEFING:-0}" == "1" ]] && exit 0

# Guard 3: never run for sub-agent invocations.
[[ "${CLAUDE_SUBAGENT:-0}" == "1" ]] && exit 0

# All guards passed — run the briefing.
exec "${HOME}/.local/bin/teri-briefing" --auto
