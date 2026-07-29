# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - Unreleased

First public release. Extracted from a working single-agent setup and generalised.

### Added
- Neutral core: 14 modules under `core/modules/`, agent-independent
- Constitution (`AGENTS.md`) holding only cross-domain rules
- Language modules: `java-backend`, `go-backend`, `node-backend`, `python-backend`, `php-backend`
- Cross-cutting modules: `backend-patterns`, `db-operations`, `pg-review`, `iac-review`,
  `devops-pipeline`, `security-audit`, `blue-team-detection`, `pr-review`, `lsp-tooling`
- Adapters for Claude Code, Cursor, GitHub Copilot, Windsurf, and opencode
  (`scripts/render.py`). opencode modules render as `.opencode/agents/*.md` subagents
  rather than `opencode.json` `instructions` globs, which would load every module on
  every request
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

### Notes
- Only the Claude Code adapter has been verified in a running tool. The other four are
  generated but unverified — see the support matrix in the README.
- `java-backend`, `pg-review`, `pr-review`, `security-audit`, and `lsp-tooling` come from
  daily use. The remaining modules are newer and have had less exposure.
