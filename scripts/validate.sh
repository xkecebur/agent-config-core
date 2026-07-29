#!/usr/bin/env bash
# Validate the repository: module frontmatter, build reproducibility, and hook behaviour.
#
# Hooks are tested against real triggers, not merely executed. A guard that exits 0 without
# doing anything is exactly the failure mode this script exists to catch.
#
# Usage: scripts/validate.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

pass=0
fail=0

ok() {
	printf '  ok    %s\n' "$1"
	pass=$((pass + 1))
}

no() {
	printf '  FAIL  %s\n' "$1"
	fail=$((fail + 1))
}

check() { # check <condition-result> <ok-message> <fail-message>
	if [ "$1" -eq 0 ]; then
		ok "$2"
	else
		no "$3"
	fi
}

echo "modules"
for f in core/modules/*.md; do
	name=$(basename "$f" .md)

	if ! head -1 "$f" | grep -q '^---$'; then
		no "$name: missing frontmatter"
		continue
	fi

	fm=$(sed -n '2,/^---$/p' "$f")
	declared=$(printf '%s' "$fm" | grep -m1 '^name:' | sed 's/^name:[[:space:]]*//')
	desc=$(printf '%s' "$fm" | grep -m1 '^description:' | sed 's/^description:[[:space:]]*//')
	errors=0

	if [ "$declared" != "$name" ]; then
		no "$name: frontmatter name is '$declared'"
		errors=1
	fi
	if [ -z "$desc" ]; then
		no "$name: missing description"
		errors=1
	elif [ "${#desc}" -lt 80 ]; then
		no "$name: description too short to be a useful retrieval signal"
		errors=1
	elif [ "${#desc}" -gt 1200 ]; then
		no "$name: description is ${#desc} chars - it costs context on every request"
		errors=1
	elif ! printf '%s' "$desc" | grep -qi 'use when'; then
		no "$name: description does not say when to load it"
		errors=1
	fi

	if [ "$errors" -eq 0 ]; then
		ok "$name"
	fi
done

echo
echo "build"
if ./scripts/build.sh >/dev/null 2>&1; then
	count=$(find dist -type f | wc -l | tr -d ' ')
	check "$([ "$count" -gt 0 ] && echo 0 || echo 1)" \
		"build produced $count files" "build produced nothing"

	# Registering an adapter in render.py but forgetting build.sh's default list is a
	# silent failure: the build still succeeds, that agent just never gets generated.
	# -B: importing render.py must not litter scripts/ with a __pycache__ directory.
	adapters=$(python3 -B -c "import sys; sys.path.insert(0, 'scripts'); import render; print(' '.join(render.ADAPTERS))")
	for agent in $adapters; do
		if [ -d "dist/$agent" ] && [ -n "$(find "dist/$agent" -type f -print -quit)" ]; then
			ok "adapter $agent generated output"
		else
			no "adapter $agent registered but produced nothing"
		fi
	done
else
	no "build failed"
fi

echo
echo "hooks"
if ! command -v jq >/dev/null 2>&1; then
	no "jq not installed - hooks cannot run"
	echo
	echo "$pass passed, $fail failed"
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -r "$tmp" 2>/dev/null' EXIT

# Formatter: unformatted Go must come back formatted.
if command -v gofmt >/dev/null 2>&1; then
	printf 'package main\nfunc main(){\nx:=1\n_=x\n}\n' >"$tmp/t.go"
	echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$tmp/t.go\"}}" |
		./hooks/format-file.sh >/dev/null 2>&1
	if grep -q "$(printf '\t')" "$tmp/t.go"; then
		ok "format-file.sh formats Go"
	else
		no "format-file.sh did not format Go"
	fi
else
	echo "  skip  format-file.sh (gofmt not installed)"
fi

# Destructive guard: dangerous commands ask, harmless ones pass through.
decision=$(echo '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"}}' |
	./hooks/guard-destructive.sh | jq -r '.hookSpecificOutput.permissionDecision // empty')
if [ "$decision" = "ask" ]; then
	ok "guard-destructive.sh asks on terraform destroy"
else
	no "guard-destructive.sh returned '$decision' instead of 'ask'"
fi

decision=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' |
	./hooks/guard-destructive.sh | jq -r '.hookSpecificOutput.permissionDecision // empty')
if [ -z "$decision" ]; then
	ok "guard-destructive.sh passes harmless commands"
else
	no "guard-destructive.sh blocked 'ls -la'"
fi

# Secret guard: a real secret must be denied, a clean tree must pass.
# The token below is randomly generated, not a documentation sample - gitleaks allowlists
# well-known examples such as AKIAIOSFODNN7EXAMPLE and would report a false pass.
if command -v gitleaks >/dev/null 2>&1; then
	(
		cd "$tmp" || exit 1
		git init -q .
		git config user.email test@example.com
		git config user.name test
		echo hello >readme.txt
		git add readme.txt
		git commit -qm init
	) >/dev/null 2>&1

	printf 'TOKEN=ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8\n' >"$tmp/.env" # gitleaks:allow
	(cd "$tmp" && git add .env) >/dev/null 2>&1

	decision=$(cd "$tmp" && echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' |
		"$ROOT/hooks/guard-secrets.sh" | jq -r '.hookSpecificOutput.permissionDecision // empty')
	if [ "$decision" = "deny" ]; then
		ok "guard-secrets.sh denies a staged secret"
	else
		no "guard-secrets.sh returned '$decision' for a staged secret"
	fi

	(cd "$tmp" && git rm -q --cached .env) >/dev/null 2>&1
	decision=$(cd "$tmp" && echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' |
		"$ROOT/hooks/guard-secrets.sh" | jq -r '.hookSpecificOutput.permissionDecision // empty')
	if [ -z "$decision" ]; then
		ok "guard-secrets.sh passes a clean tree"
	else
		no "guard-secrets.sh blocked a clean tree"
	fi
else
	echo "  skip  guard-secrets.sh (gitleaks not installed)"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
