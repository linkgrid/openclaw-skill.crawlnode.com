#!/usr/bin/env bash
# Minimal CrawlNode session wrapper — start or destroy a session cleanly.
# Usage:
#   cn-session.sh start [start.json]     → prints session_id to stdout
#   cn-session.sh destroy SESSION_ID
set -euo pipefail

API="${CRAWLNODE_API_URL:-http://api1.crawlnode.com:8000}"

if [ -z "${CRAWLNODE_TOKEN:-}" ]; then
  echo "ERROR: CRAWLNODE_TOKEN is not set" >&2
  exit 1
fi

cmd="${1:-}"
shift || true

case "$cmd" in
  start)
    out="${1:-/tmp/crawlnode-start.json}"
    curl -sS -X POST "$API/api/start" \
      -H "Token: $CRAWLNODE_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"proxy":"auto","extension":false}' \
      -o "$out"
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["session_id"])' "$out"
    ;;
  destroy)
    sid="${1:-}"
    if [ -z "$sid" ]; then
      echo "ERROR: session id required" >&2
      exit 1
    fi
    curl -sS -X POST "$API/api/destroy" \
      -H "Token: $CRAWLNODE_TOKEN" \
      -H "X-Session-Id: $sid" \
      -H "Content-Type: application/json" \
      -d '{}' >/dev/null
    ;;
  *)
    echo "Usage: cn-session.sh start [out.json] | destroy SESSION_ID" >&2
    exit 1
    ;;
esac
