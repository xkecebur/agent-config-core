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
- Adapters for Claude Code, Cursor, GitHub Copilot, and Windsurf (`scripts/render.py`)
- Hooks: post-edit formatter, staged-secret guard, destructive-command guard, plus an
  agent-independent git `pre-commit`
- `scripts/validate.sh` — frontmatter checks, build check, and hook behaviour tests that
  use real triggers
- CI running shellcheck, shfmt, ruff, validation, and a secret scan

### Notes
- Only the Claude Code adapter has been verified in a running editor. The other three are
  generated but unverified — see the support matrix in the README.
- `java-backend`, `pg-review`, `pr-review`, `security-audit`, and `lsp-tooling` come from
  daily use. The remaining modules are newer and have had less exposure.
