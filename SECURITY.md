# Security Policy

## Supported versions

This project is at **v0.1** and is developed on `master`. Fixes land on `master`; there are
no maintained release branches yet.

## What counts as a vulnerability here

This repository ships configuration, documentation, and shell scripts — not a service. The
realistic risk classes are:

- **A guard that fails open.** A hook that exits 0 without actually scanning, so a secret
  reaches history while the user believes they are protected. This has already happened once
  (`gitleaks protect` was removed in v8.30 and became a silent no-op), so it is taken
  seriously.
- **Command injection in a hook.** The hooks parse JSON that originates from agent tool
  calls, which can contain attacker-influenced content. Unquoted expansion or `eval` on that
  input would be a real finding.
- **Path handling in `install.sh`.** It writes files into a target directory; a path that
  escapes that directory is a finding.
- **Malicious or compromised content in a module.** For example, a module instructing an
  agent to exfiltrate data, disable a security control, or run an untrusted script.
- **Supply chain in CI.** An unpinned action or an install step fetching an unverifiable
  binary.

Not vulnerabilities: a linter you dislike, a module whose advice you disagree with, or the
fact that `guard-destructive.sh` can be bypassed by the user — it asks for confirmation by
design, and the person at the keyboard is trusted.

## How to report

**Do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting on this repository:
**Security → Report a vulnerability**. That opens a private advisory visible only to the
maintainer.

Please include:

- Which file and which line
- What an attacker controls, and what they achieve
- A reproduction — the smaller the better
- The versions involved (OS, bash, gitleaks, agent) if relevant

## What to expect

- Acknowledgement within about a week. This is maintained by one person alongside a
  full-time job; if you have heard nothing after two weeks, feel free to nudge publicly
  *without* disclosing details.
- If the report is valid, a fix on `master` and credit in `CHANGELOG.md` unless you prefer
  otherwise.
- If it is not, a clear explanation of why rather than silence.

## Scope

This policy covers the contents of this repository. It does **not** cover Claude Code,
Cursor, GitHub Copilot, Windsurf, gitleaks, or any other tool referenced here — report those
to their own maintainers.

## A note on the hooks

The hooks are a safety net, not a boundary. `guard-secrets.sh` reduces the chance of
committing a credential; it does not guarantee it. Detection rules have gaps, `--no-verify`
exists, and a determined user can bypass any of it. Treat them as one layer among several,
and rotate any credential that reaches a repository regardless of what a scanner reported.
