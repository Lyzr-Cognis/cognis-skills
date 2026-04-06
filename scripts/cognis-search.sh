#!/bin/bash
# cognis-search.sh — Search memories via the Cognis REST API
# Usage: bash scripts/cognis-search.sh "query" [--user|--repo|--both]
# Env:   LYZR_API_KEY (required), COGNIS_OWNER_ID (optional), COGNIS_API_URL (optional)

set -euo pipefail

source "$(dirname "$0")/cognis-lib.sh"

# --- Help ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat >&2 <<'USAGE'
cognis-search.sh — Search Cognis memories

USAGE:
  bash scripts/cognis-search.sh "search query" [OPTIONS]

OPTIONS:
  --user        Search only personal/user-scoped memories (default)
  --repo        Search only team/repo-scoped memories
  --both        Search both personal and team memories
  --limit N     Maximum number of results (default: 10)
  --help, -h    Show this help message

ENVIRONMENT:
  LYZR_API_KEY      (required) Your Cognis API key
  COGNIS_OWNER_ID   (optional) Override owner ID (default: system username)
  COGNIS_API_URL    (optional) Override API base URL

EXAMPLES:
  bash scripts/cognis-search.sh "what database do we use"
  bash scripts/cognis-search.sh "deployment process" --repo
  bash scripts/cognis-search.sh "auth setup" --both --limit 5
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
QUERY=""
SCOPE="user"
LIMIT=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) SCOPE="user"; shift ;;
    --repo) SCOPE="repo"; shift ;;
    --both) SCOPE="both"; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --help|-h) exit 0 ;;
    *) [[ -z "$QUERY" ]] && QUERY="$1"; shift ;;
  esac
done

if [[ -z "$QUERY" ]]; then
  echo "Error: No query provided. Usage: bash scripts/cognis-search.sh \"query\" [--user|--repo|--both]" >&2
  exit 1
fi

# --- Scoping ---
OWNER_ID="${COGNIS_OWNER_ID:-$(whoami)}"

# --- Search function ---
do_search() {
  local agent_id="$1"
  local label="$2"

  JSON_QUERY="$(echo "$QUERY" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))')"

  PAYLOAD=$(cat <<EOF
{
  "query": ${JSON_QUERY},
  "owner_id": "${OWNER_ID}",
  "agent_id": "${agent_id}",
  "limit": ${LIMIT}
}
EOF
)

  echo "Searching ${label} memories (agent_id: ${agent_id})..." >&2

  cognis_curl POST "${COGNIS_API_URL}/v1/memories/search" "$PAYLOAD"
}

# --- Execute search based on scope ---
case "$SCOPE" in
  user)
    RESULT=$(do_search "$(get_personal_agent_id)" "personal") || exit 1
    wrap_untrusted_output "cognis-search/personal" "$RESULT"
    ;;
  repo)
    RESULT=$(do_search "$(get_repo_agent_id)" "team") || exit 1
    wrap_untrusted_output "cognis-search/team" "$RESULT"
    ;;
  both)
    PERSONAL=$(do_search "$(get_personal_agent_id)" "personal") || exit 1
    TEAM=$(do_search "$(get_repo_agent_id)" "team") || exit 1
    if command -v jq &>/dev/null; then
      COMBINED=$(jq -n --argjson p "$PERSONAL" --argjson t "$TEAM" '{"personal": $p, "team": $t}')
    else
      COMBINED=$(python3 -c "
import json, sys
p = json.loads(sys.argv[1])
t = json.loads(sys.argv[2])
print(json.dumps({'personal': p, 'team': t}))
" "$PERSONAL" "$TEAM")
    fi
    wrap_untrusted_output "cognis-search/both" "$COMBINED"
    ;;
esac
