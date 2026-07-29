#!/usr/bin/env bash
# Generate agent-specific configuration from the neutral core.
#
# core/modules/*.md  ->  dist/<agent>/...
#
# The core is the single source of truth. Adapters are pure transformations: never edit
# anything under dist/ by hand, it is overwritten on every build.
#
# Usage: scripts/build.sh [agent ...]     (default: all)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT/core/modules"
DIST="$ROOT/dist"

command -v python3 >/dev/null 2>&1 || {
	echo "python3 is required" >&2
	exit 1
}

agents=("$@")
[ ${#agents[@]} -eq 0 ] && agents=(claude-code cursor copilot windsurf opencode agent-skills)

rm -rf "$DIST"

for agent in "${agents[@]}"; do
	echo "building: $agent"
	python3 "$ROOT/scripts/render.py" "$agent" "$CORE" "$DIST/$agent" "$ROOT/AGENTS.md"
done

echo
echo "output -> $DIST"
