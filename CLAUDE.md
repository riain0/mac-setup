# User Preferences

> Project CLAUDE.md takes precedence over everything here. When conflict: project rules win.

---

## Caveman Mode

Active every session, default **full**. Persist until "stop caveman" / "normal mode".

Skills:
- `/caveman` — activate full (default)
- `/caveman lite|ultra` — switch intensity
- `/caveman-commit` — terse Conventional Commits
- `/caveman-review` — one-line PR comments
- `/caveman:compress <file>` — compress .md to caveman prose
- `/caveman-help` — quick reference card

Auto-clarity for: destructive ops, security warnings, multi-step sequences where fragment order risks misread.

---

## Commits

Always invoke `/caveman-commit`. Never write ad-hoc commit messages.

Format: `type(scope): subject` — subject ≤50 chars, body only when "why" non-obvious.
Types: `feat fix chore refactor docs test ci build perf`.

---

## Git Workflow — Graphite (Always)

Use `gt` CLI 100% of the time. Never `git checkout -b`, `git push origin <branch>`, or `gh pr create` directly.

Every change = own branch, stacked on trunk or parent branch.

| Command | When |
|---------|------|
| `gt create` | New branch + stage changes |
| `gt modify` | Amend current branch |
| `gt submit` | Push current branch + downstack as PRs |
| `gt submit --stack` | Push entire stack |
| `gt sync` | Pull trunk, rebase stack, prune merged |
| `gt log` | View stack graph |
| `gt checkout` | Interactive branch switch |
| `gt up` / `gt down` | Navigate stack |

Stack pattern: `main ← feat/api ← feat/frontend ← feat/docs`. Keep PRs small + reviewable.

---

## Bureau

Agent package manager. Use for all agent discovery + install.

- `/bureau:search <query>` — find agents
- `/bureau:install <name>` — install to ~/.claude/agents/
- `/bureau:list` — show installed
- `/bureau:tap add <repo>` — add community tap
- `/bureau:update` — update all agents

---

## Compress

Run `/caveman:compress` on CLAUDE.md files, memory files, todos when content grows verbose. Saves ~46% input tokens. Backup auto-saved as `FILE.original.md`.

Apply proactively when prose in .md files gets long.

---

## Active Comprehension — Anti-Cognitive-Offload

Goal: keep user thinking, not just approving.

**After completing non-trivial work**, ask 1–3 targeted questions. Examples:
- "Why does X approach work here vs alternative Y?"
- "What would break if Z assumption changed?"
- "What's the tradeoff we accepted by doing it this way?"

**Triggers** (non-trivial = any of):
- Multi-file changes
- New architectural pattern introduced
- Non-obvious tradeoff made
- Bug fix where root cause is subtle
- Schema/data model change
- Performance optimization

**Skip for**: typo fixes, rename-only changes, boilerplate scaffolding, explicitly routine tasks.

**Format**: brief setup sentence + 1–3 concrete questions. Not a quiz — a prompt to reason aloud. User can answer or skip.
