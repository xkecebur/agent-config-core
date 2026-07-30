# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - Unreleased

First public release. Extracted from a working single-agent setup and generalised.

### Added
- Neutral core: 15 modules under `core/modules/`, agent-independent
- Constitution (`AGENTS.md`) holding only cross-domain rules
- Language modules: `java-backend`, `go-backend`, `node-backend`, `python-backend`, `php-backend`
- Cross-cutting modules: `backend-patterns`, `db-operations`, `pg-review`, `iac-review`,
  `devops-pipeline`, `security-audit`, `blue-team-detection`, `pr-review`, `lsp-tooling`
- Adapters for Claude Code, Cursor, GitHub Copilot, Windsurf, opencode, and the
  cross-client Agent Skills standard (`scripts/render.py`). opencode modules render as
  `.opencode/agents/*.md` subagents rather than `opencode.json` `instructions` globs,
  which would load every module on every request
- `agent-skills` adapter emitting `.agents/skills/<name>/SKILL.md` per the
  [Agent Skills specification](https://agentskills.io/specification). One adapter covers
  every compliant client — Codex, Gemini CLI, VS Code, Junie, Amp, goose, Roo Code and
  Zed among them — instead of one adapter each
- `scripts/validate.sh` enforces the Agent Skills limits: name charset and length, and a
  1024-character description ceiling checked against the **rendered** output, since the
  adapter appends glob metadata to the description after the source-side check
- Hooks: post-edit formatter, staged-secret guard, destructive-command guard, plus an
  agent-independent git `pre-commit`
- `scripts/validate.sh` — frontmatter checks, build check, and hook behaviour tests that
  use real triggers
- CI running shellcheck, shfmt, ruff, validation, and a secret scan
- Constitution gains **Robust** and **Maintainable** rules under coding standards —
  timeouts, resource cleanup on error paths, idempotent retries, honest names,
  minimal diffs, and stated migration paths for public-contract changes
- `blue-team-detection` gains an **Observability** section: choosing between a log, a
  metric and a trace, cardinality limits on metric labels, correlation ids born at the
  edge, clock synchronisation as a forensic requirement, and retention sized to real
  attacker dwell time
- `devops-pipeline` gains a **Deployment and runtime health** section: liveness versus
  readiness probes, SLOs and error budgets as a release gate, canary promotion driven by
  an SLI rather than a timer, rehearsed rollback, and burn-rate alerting on symptoms
- `debugging` module — a language-agnostic investigation method: evidence before
  hypothesis, bisecting by input, commit or layer, a language-server query loop in place
  of guessing, falsifiable predictions, one change at a time, verification before claiming
  a fix, and the criteria for stopping and asking for data
- `java-backend` is no longer Spring-only. It now detects the framework first — Spring
  Boot, Quarkus, Micronaut, Vert.x, Helidon, plain Jakarta EE, Ktor — and treats the
  paradigm (blocking, Reactor, Mutiny, coroutine, virtual threads) as a separate axis,
  because the same framework runs several
- `go-backend` gains router and data-layer detection (net/http, chi, gin, echo, fiber,
  gRPC; database/sql, pgx, sqlc, GORM) and a data-access section covering the unbounded
  default connection pool, `rows.Err()`, and pgx behind PgBouncer in transaction mode
- Symptom-to-cause tables in `java-backend` and `go-backend`, so the language module is
  reachable while debugging rather than only while writing code

### Notes
- Only the Claude Code adapter has been verified in a running tool. The other four are
  generated but unverified — see the support matrix in the README.
- `java-backend`, `pg-review`, `pr-review`, `security-audit`, and `lsp-tooling` come from
  daily use. The remaining modules are newer and have had less exposure.
- Within `java-backend`, only the Spring Boot content is daily use. The Quarkus,
  Micronaut, Vert.x, Helidon, and Ktor entries are researched rather than lived, and stay
  limited to detection markers and each framework's known failure modes.
