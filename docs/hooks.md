# Hooks

Hooks exist for the rules that must hold **every time**. A model can forget to scan for
secrets; a hook cannot. If a rule only matters sometimes, it belongs in a module instead.

Three of these are agent-native (the agent runs them around its own tool calls). The
fourth runs at the git layer and therefore works with any assistant, or none.

| Hook | Fires | Decision |
|---|---|---|
| `format-file.sh` | After the agent writes or edits a file | Formats, returns lint output |
| `guard-secrets.sh` | Before a shell command containing `git commit` | **Blocks** on a gitleaks finding |
| `guard-destructive.sh` | Before any shell command | **Asks** for confirmation |
| `git/pre-commit` | `git commit`, any client | **Blocks** on a gitleaks finding |

## Requirements

`jq` and `gitleaks` are required; formatters and linters are optional. The formatter hook
is **self-detecting** — tools that are not installed are skipped silently, so the same
script works on a bare machine and gains capability as you install more.

```bash
# macOS / Linuxbrew
brew install jq gitleaks
brew install ruff shellcheck hadolint shfmt

# Debian / Ubuntu   (gitleaks: Debian 13+ / Ubuntu 24.04+)
sudo apt install jq gitleaks shellcheck

# Fedora            (note the capitalisation)
sudo dnf install jq gitleaks ShellCheck hadolint

# Arch
sudo pacman -S jq gitleaks shellcheck shfmt ruff
```

Per-OS notes, Windows instructions, and binary fallbacks for packages that are missing on a
given distribution are in the [Requirements section of the README](../README.md#requirements).

On **Windows** these scripts need Git Bash or WSL2 — they are bash, and will not run under
PowerShell. If your agent launches hooks through PowerShell, use the git-level `pre-commit`
guard, which runs wherever `git commit` runs.

## Claude Code

Copy the scripts somewhere stable and reference them by absolute path in
`~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "/absolute/path/hooks/format-file.sh", "timeout": 30 }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/absolute/path/hooks/guard-secrets.sh", "timeout": 30 },
          { "type": "command", "command": "/absolute/path/hooks/guard-destructive.sh", "timeout": 10 }
        ]
      }
    ]
  }
}
```

Merge into the existing `hooks` object rather than replacing it. Malformed JSON disables
every setting in the file silently.

## Cursor, Copilot, Windsurf, opencode, and everything else

These agents have no equivalent of a pre-command hook today. Use the git-layer guard, which
covers the case that matters most — a secret reaching history:

```bash
cp hooks/git/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

For a whole team, commit the hook and point git at it:

```bash
mkdir -p .githooks && cp hooks/git/pre-commit .githooks/
git config core.hooksPath .githooks
```

Formatting is better handled by your editor's format-on-save plus a CI check than by
simulating a post-edit hook.

## Testing a hook

**Always test a guard with a real trigger.** A guard that silently does nothing is worse
than no guard, because you stop looking.

```bash
# Formatter: badly formatted Go should come back formatted
printf 'package main\nfunc main(){\nx:=1\n_=x\n}\n' > /tmp/t.go
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/t.go"}}' | hooks/format-file.sh
grep -P '\t' /tmp/t.go && echo "formatter works"

# Destructive guard: expect "ask"
echo '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"}}' \
  | hooks/guard-destructive.sh | jq -r '.hookSpecificOutput.permissionDecision'

# Secret guard: expect "deny"
cd "$(mktemp -d)" && git init -q . && git config user.email t@t.io && git config user.name t
printf 'TOKEN=ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8\n' > .env && git add .env
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
  | /path/to/hooks/guard-secrets.sh | jq -r '.hookSpecificOutput.permissionDecision'
```

`scripts/validate.sh` runs all of these.

## Field note: gitleaks v8.30

`gitleaks protect --staged` was the documented way to scan staged content. **v8.30 removed
the `protect` subcommand.** It now exits 0 without scanning anything, so a hook built on it
reports success and protects nothing.

These hooks pipe the staged diff into `gitleaks stdin` instead:

```bash
git diff --staged | gitleaks stdin --no-banner --redact
```

The general lesson applies beyond gitleaks: a security tool that changes its CLI can turn
your guard into a no-op without any error. Test with a real secret, not with a clean tree.

Note also that gitleaks allowlists well-known documentation samples — `AKIAIOSFODNN7EXAMPLE`
from the AWS docs will **not** trigger a finding. Test with a realistic random value.

## Tuning

**Destructive guard** — patterns live in `hooks/guard-destructive.sh` as a list of
`check '<regex>' "<label>"` lines. Add your own, or remove ones that fire too often in your
workflow. The decision is `ask`, not `deny`, because these commands are legitimate against
a lab or staging environment.

**Secret guard** — false positives go in `.gitleaksignore` by fingerprint. The decision is
`deny` deliberately: a secret in history is expensive to undo, and `git commit --no-verify`
remains available when you have decided the finding is wrong.
