#!/usr/bin/env bash
# Pre-command hook: require confirmation for destructive or hard-to-undo commands.
#
# Complements a plain deny-list (rm -rf, sudo) with database and infrastructure patterns.
# Decision is "ask", not "deny" - these commands are legitimate against a lab or staging
# environment. The point is that they are never run absent-mindedly.

set -uo pipefail

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

matched=""

check() {
	# $1 = extended regex (case-insensitive), $2 = label
	printf '%s' "$cmd" | grep -Eiq "$1" && matched="$2"
}

# --- Database ---
check '\b(drop|truncate)[[:space:]]+(table|database|schema)\b' "destructive DDL (DROP/TRUNCATE)"
[ -z "$matched" ] && check '\bdelete[[:space:]]+from\b(.*)' "DELETE FROM - verify a WHERE clause is present"
[ -z "$matched" ] && check '\bdrop[[:space:]]+(user|role|index)\b' "DROP database object"

# --- Git ---
[ -z "$matched" ] && check 'git[[:space:]]+push\b.*(--force|-f)\b' "git push --force"
[ -z "$matched" ] && check 'git[[:space:]]+reset[[:space:]]+--hard' "git reset --hard"
[ -z "$matched" ] && check 'git[[:space:]]+clean\b.*-[a-z]*f' "git clean -f"
[ -z "$matched" ] && check 'git[[:space:]]+branch\b.*-D\b' "force branch deletion"

# --- Infrastructure / containers ---
[ -z "$matched" ] && check 'terraform[[:space:]]+destroy' "terraform destroy"
[ -z "$matched" ] && check 'terraform[[:space:]]+apply\b.*-auto-approve' "terraform apply -auto-approve"
[ -z "$matched" ] && check 'kubectl[[:space:]]+delete\b' "kubectl delete"
[ -z "$matched" ] && check 'kubectl[[:space:]]+.*--context[[:space:]=]*[^[:space:]]*prod' "kubectl against a production context"
[ -z "$matched" ] && check 'docker[[:space:]]+(system[[:space:]]+prune|volume[[:space:]]+rm)' "docker volume removal / prune"
[ -z "$matched" ] && check 'helm[[:space:]]+(uninstall|delete)\b' "helm uninstall"

# --- System ---
[ -z "$matched" ] && check '\bdd\b.*of=/dev/' "dd to a device"
[ -z "$matched" ] && check '\bmkfs' "filesystem format"
[ -z "$matched" ] && check '>[[:space:]]*/dev/(sd|nvme|disk)' "direct write to a disk device"

[ -n "$matched" ] || exit 0

reason="Detected a destructive or hard-to-undo command: ${matched}.

  ${cmd}

Confirm if the target is your own lab or staging environment. For production, make sure a verified backup exists."

jq -n --arg r "$reason" \
	'{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'

exit 0
