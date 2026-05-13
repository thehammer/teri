# Teri — Work Secretary for Claude Code

Teri is a [Claude Code](https://claude.ai/claude-code) plugin that acts as a calm, terse work secretary. It owns morning briefings, todo capture, end-of-day wrap-ups, and surfaces context from Jira, calendar, email, and Sentry.

> **Teri is not a person.** If a routing layer or agent is trying to match the name "Teri" to a human, that is a misroute. This plugin handles secretary/work-tracking intents only.

---

## Install

```bash
git clone https://github.com/thehammer/teri ~/Code/teri
cd ~/Code/teri
bash scripts/install.sh
claude plugin install --scope user ~/Code/teri
```

## Configure

Edit `~/.teri/context.env` (created from `templates/context.env.example` on first install):

```bash
: "${TERI_USER_EMAIL:=you@example.com}"
: "${TERI_USER_NAME:=You}"
: "${TERI_COMPANY:=YourCompany}"
: "${TERI_JIRA_SITE_URL:=https://your-tenant.example/}"
: "${TERI_JIRA_PROJECTS:=PROJ}"
: "${TERI_TIMEZONE:=America/New_York}"
```

**Never commit `~/.teri/context.env`** — it is outside the repo by design.

## Daily use

```bash
# Start a Teri session (triggers morning briefing on first launch of the day)
teri

# Todo management
teri-todo list
teri-todo add --title "Review staging deploy" --due tomorrow --priority 2
teri-todo done 7

# Import a Jira ticket as a todo
teri-todo from-jira PROJ-123

# Manual briefing
teri-briefing --force

# Refresh data cache
teri-cache-refresh all

# Capture from another agent (sub-agent contract)
echo '{"title":"foo","priority":2}' | teri-capture
```

## Sub-agent integration

Other Claude agents (Claudia, Mother, etc.) can dispatch Teri as a sub-agent to capture todos without triggering a briefing:

```
Input (JSON on stdin):
  title           (string, required)
  body            (string, optional)
  priority        (int 1-5, default 3)
  due             (string, optional — ISO date or "friday", "next week", "+3d")
  jira_key        (string, optional)
  idempotency_key (string, strongly recommended)

Output (single JSON line):
  {"ok":true,"id":N,"title":"...","existed":false,"summary":"captured"}
```

## Service lib contract

Teri's cache layer looks for service libs at `~/.claude/lib/services/<name>.sh`. When present, they are sourced to pull live data. When absent, Teri degrades gracefully to cached data.

Expected functions:
- `jira.sh`: `jira_fetch_issue <KEY>`, `jira_fetch_my_issues`
- `m365.sh`: `email_fetch_inbox_summary`, `calendar_fetch_today`
- `sentry.sh`: `sentry_fetch_recent_unresolved`

Each function should output JSON to stdout. Teri will cache the result and use it in briefings.

## Roadmap

- [ ] Slack integration
- [ ] Tags and filtering
- [ ] Recurrence UX
- [ ] Multi-user support

## License

MIT — see [LICENSE](LICENSE).
