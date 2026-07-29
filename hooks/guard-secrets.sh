#!/usr/bin/env bash
# Pre-command hook: block a commit that carries a secret.
#
# Fail-closed on any gitleaks finding; passes silently when gitleaks is not installed
# or the working directory is not a git repository.
#
# NOTE: gitleaks v8.30 removed the `protect` subcommand. Staged content is scanned by
# piping the staged diff into `gitleaks stdin` — the older `gitleaks protect --staged`
# exits 0 without scanning anything, which silently disables this guard.

set -uo pipefail

# Match anywhere in the command (not just the prefix) so compound commands such as
# `git add . && git commit -m x` are still caught.
payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
# Deliberately permissive (e.g. `git -C dir commit`, `git log --grep=commit`): a false
# positive costs one extra scan, a false negative leaks a secret into history.
printf '%s' "$cmd" | grep -Eq '\bgit\b[^|;&]*\bcommit\b' || exit 0

command -v gitleaks >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Staged content is scanned via stdin (see the note above).
findings=$(git diff --staged | gitleaks stdin --no-banner --redact 2>&1)
status=$?

[ $status -eq 0 ] && exit 0

# Strip ANSI escapes so the message stays readable in the agent's prompt
findings=$(printf '%s' "$findings" | sed $'s/\033\\[[0-9;]*m//g')

reason="gitleaks found a probable secret in the staged changes - commit blocked.

$(printf '%s' "$findings" | head -30)

If this is a false positive: add the fingerprint to .gitleaksignore, or run the commit manually from your terminal."

jq -n --arg r "$reason" \
	'{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'

exit 0
