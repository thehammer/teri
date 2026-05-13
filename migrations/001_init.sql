PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS todos (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  title           TEXT NOT NULL,
  body            TEXT,
  status          TEXT NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open','in_progress','done','cancelled','blocked')),
  priority        INTEGER NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
  due_date        TEXT,
  jira_key        TEXT,
  parent_id       INTEGER REFERENCES todos(id),
  recurrence      TEXT,
  source          TEXT NOT NULL DEFAULT 'user'
                    CHECK (source IN ('user','sub_agent','briefing','import','jira')),
  source_ref      TEXT,
  idempotency_key TEXT UNIQUE,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  completed_at    TEXT,
  snoozed_until   TEXT
);
CREATE INDEX IF NOT EXISTS idx_todos_status ON todos(status);
CREATE INDEX IF NOT EXISTS idx_todos_due    ON todos(due_date);
CREATE INDEX IF NOT EXISTS idx_todos_jira   ON todos(jira_key);
CREATE INDEX IF NOT EXISTS idx_todos_idem   ON todos(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_todos_parent ON todos(parent_id);

CREATE TABLE IF NOT EXISTS events (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  todo_id      INTEGER REFERENCES todos(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL,
  payload_json TEXT,
  created_at   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_todo ON events(todo_id);

CREATE TABLE IF NOT EXISTS briefings (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  kind         TEXT NOT NULL DEFAULT 'morning' CHECK (kind IN ('morning','eod','manual')),
  summary_md   TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at   TEXT NOT NULL
);

PRAGMA user_version = 1;
