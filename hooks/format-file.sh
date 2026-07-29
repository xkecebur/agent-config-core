#!/usr/bin/env bash
# Post-edit hook: format the file the agent just wrote, then lint it if a linter exists.
#
# Reads the agent's tool payload as JSON on stdin and extracts the file path.
# Self-detecting: tools that are not installed are skipped silently, so the same script
# works on a fresh machine and gains capability as you install more tooling.
#
# Lint output is returned to the agent so problems surface immediately, not at build time.

set -uo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)

[ -n "$file" ] && [ -f "$file" ] || exit 0

has() { command -v "$1" >/dev/null 2>&1; }

lint_output=""
base=$(basename "$file")

case "$file" in
*.go)
	has gofmt && gofmt -w "$file" 2>/dev/null
	has goimports && goimports -w "$file" 2>/dev/null
	;;
*.py)
	has ruff && {
		ruff format "$file" >/dev/null 2>&1
		lint_output=$(ruff check "$file" 2>&1 | head -20)
	}
	;;
*.sh | *.bash)
	has shfmt && shfmt -w "$file" 2>/dev/null
	has shellcheck && lint_output=$(shellcheck -f gcc "$file" 2>&1 | head -20)
	;;
*.java)
	has google-java-format && google-java-format -i "$file" 2>/dev/null
	;;
*.php)
	has php-cs-fixer && php-cs-fixer fix "$file" --quiet 2>/dev/null
	has php && lint_output=$(php -l "$file" 2>&1 | grep -v '^No syntax errors' | head -10)
	;;
*.tf | *.tfvars)
	has terraform && terraform fmt "$file" >/dev/null 2>&1
	has tflint && lint_output=$(tflint --filter="$file" 2>&1 | head -20)
	;;
*.sql)
	has sqlfluff && lint_output=$(sqlfluff lint --dialect postgres "$file" 2>&1 | head -20)
	;;
esac

# Dockerfiles do not always carry an extension, so match on the file name too.
case "$base" in
Dockerfile | Dockerfile.* | *.dockerfile)
	has hadolint && lint_output=$(hadolint "$file" 2>&1 | head -20)
	;;
esac

if [ -n "$lint_output" ]; then
	jq -n --arg ctx "Lint results for $file:"$'\n'"$lint_output" \
		'{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
fi

exit 0
