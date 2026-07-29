#!/usr/bin/env bash
# Install generated configuration into a target project.
#
# Usage:
#   scripts/install.sh <agent> [target-dir]
#   scripts/install.sh claude-code ~/work/my-service
#   scripts/install.sh cursor .
#
# Nothing is overwritten without asking. Existing files are backed up as <file>.bak.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="${1:-}"
TARGET="${2:-$PWD}"

if [ -z "$AGENT" ]; then
	echo "usage: scripts/install.sh <claude-code|cursor|copilot|windsurf> [target-dir]" >&2
	exit 1
fi

SRC="$ROOT/dist/$AGENT"
[ -d "$SRC" ] || {
	echo "not built yet - run scripts/build.sh first" >&2
	exit 1
}
[ -d "$TARGET" ] || {
	echo "target directory does not exist: $TARGET" >&2
	exit 1
}

echo "installing $AGENT -> $TARGET"

copied=0
skipped=0
while IFS= read -r -d '' src; do
	rel="${src#"$SRC"/}"
	dst="$TARGET/$rel"

	if [ -e "$dst" ]; then
		if cmp -s "$src" "$dst"; then
			skipped=$((skipped + 1))
			continue
		fi
		printf '  exists: %s — overwrite? [y/N] ' "$rel"
		read -r reply </dev/tty || reply=n
		case "$reply" in
		[yY]*) cp "$dst" "$dst.bak" && echo "    backed up -> $rel.bak" ;;
		*)
			skipped=$((skipped + 1))
			continue
			;;
		esac
	fi

	mkdir -p "$(dirname "$dst")"
	cp "$src" "$dst"
	[ -x "$src" ] && chmod +x "$dst"
	copied=$((copied + 1))
done < <(find "$SRC" -type f -print0)

echo "  copied: $copied, skipped: $skipped"

cat <<MSG

Next steps:
  - Wire the hooks into your agent (see docs/hooks.md); they are not active by default.
  - Install the git-level secret guard, which works regardless of agent:
      cp hooks/git/pre-commit $TARGET/.git/hooks/pre-commit && chmod +x $TARGET/.git/hooks/pre-commit
  - Optional formatters and linters:
      brew install ruff shellcheck hadolint shfmt gitleaks jq
MSG
