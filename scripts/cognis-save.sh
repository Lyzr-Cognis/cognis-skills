#!/bin/bash
# cognis-save.sh — Save a memory via the Cognis REST API
# Usage: bash scripts/cognis-save.sh "content to remember" [--team]
# Env:   LYZR_API_KEY (required), COGNIS_OWNER_ID (optional), COGNIS_API_URL (optional)

set -euo pipefail

source "$(dirname "$0")/cognis-lib.sh"

# --- Help ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat >&2 <<'USAGE'
cognis-save.sh — Save a memory to Cognis

USAGE:
  bash scripts/cognis-save.sh "memory content" [OPTIONS]
  echo "memory content" | bash scripts/cognis-save.sh - [OPTIONS]

OPTIONS:
  --team        Save as team/repo-scoped memory (visible to all contributors)
  --help, -h    Show this help message

ENVIRONMENT:
  LYZR_API_KEY      (required) Your Cognis API key
  COGNIS_OWNER_ID   (optional) Override owner ID (default: system username)
  COGNIS_API_URL    (optional) Override API base URL

EXAMPLES:
  bash scripts/cognis-save.sh "User prefers TypeScript over JavaScript"
  bash scripts/cognis-save.sh "Deploy with: make deploy-prod" --team
  echo "Long content here" | bash scripts/cognis-save.sh - --team
USAGE
  exit 0
fi

# --- Validate ---
if [[ -z "${LYZR_API_KEY:-}" ]]; then
  echo "Error: LYZR_API_KEY environment variable is not set." >&2
  echo "Get your API key at https://memory.studio.lyzr.ai" >&2
  exit 1
fi

# --- Parse args ---
CONTENT=""
TEAM_MODE=false

for arg in "$@"; do
  case "$arg" in
    --team) TEAM_MODE=true ;;
    -) CONTENT="$(cat)" ;;
    *) [[ -z "$CONTENT" ]] && CONTENT="$arg" ;;
  esac
done

if [[ -z "$CONTENT" ]]; then
  echo "Error: No content provided. Usage: bash scripts/cognis-save.sh \"content\" [--team]" >&2
  exit 1
fi

# --- Scoping ---
OWNER_ID="${COGNIS_OWNER_ID:-$(whoami)}"

if [[ "$TEAM_MODE" == true ]]; then
  AGENT_ID="$(get_repo_agent_id)"
else
  AGENT_ID="$(get_personal_agent_id)"
fi

# --- Build JSON payload ---
JSON_CONTENT="$(echo "$CONTENT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))')"

PAYLOAD=$(cat <<EOF
{
  "messages": [{"role": "user", "content": ${JSON_CONTENT}}],
  "owner_id": "${OWNER_ID}",
  "agent_id": "${AGENT_ID}"
}
EOF
)

# --- API call ---
echo "Saving memory (scope: $([ "$TEAM_MODE" = true ] && echo "team" || echo "personal"), agent_id: ${AGENT_ID})..." >&2

BODY=$(cognis_curl POST "${COGNIS_API_URL}/v1/memories" "$PAYLOAD") || exit 1

echo "Memory saved successfully." >&2
echo "$BODY"
