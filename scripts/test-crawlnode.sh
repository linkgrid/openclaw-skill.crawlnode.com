#!/usr/bin/env bash
set -euo pipefail

for cmd in curl sed grep; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: required command '$cmd' not found. Install it first." >&2
    exit 1
  fi
done

API="http://api1.crawlnode.com"
SESSION_ID=""

cleanup() {
  if [ -n "$SESSION_ID" ]; then
    echo ""
    echo "Cleaning up: destroying session $SESSION_ID ..."
    curl -sS -X POST "$API/api/destroy" \
      -H "Token: $CRAWLNODE_TOKEN" \
      -H "X-Session-Id: $SESSION_ID" \
      -H "Content-Type: application/json" \
      -d '{}' >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [ -z "${CRAWLNODE_TOKEN:-}" ]; then
  read -rp "CRAWLNODE_TOKEN: " CRAWLNODE_TOKEN
  export CRAWLNODE_TOKEN
fi

PASSIMAGE_FILES_URL="${PASSIMAGE_FILES_URL:-https://s.passimage.in}"

if [ -z "${PASSIMAGE_FILES_API_KEY:-}" ]; then
  read -rp "PASSIMAGE_FILES_API_KEY: " PASSIMAGE_FILES_API_KEY
  export PASSIMAGE_FILES_API_KEY
fi

echo "Got tokens: CRAWLNODE_TOKEN, PASSIMAGE_FILES_API_KEY"

# --- 1. Start session ---
echo "Calling $API/api/start ..."
START_RESP=$(curl -sS -X POST "$API/api/start" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}')

SESSION_ID=$(echo "$START_RESP" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

if [ -z "$SESSION_ID" ]; then
  echo "ERROR: failed to start session. Response: $START_RESP" >&2
  exit 1
fi
echo "  session_id: $SESSION_ID"

# --- 2. Navigate to randomvin.com ---
echo "Calling $API/api/go ..."
GO_RESP=$(curl -sS -X POST "$API/api/go" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: $SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://randomvin.com"}')
echo "  $GO_RESP"

# --- 3. Get element tree ---
echo "Calling $API/api/view (saved to: /tmp/crawlnode-view1.txt)"
curl -sS -X POST "$API/api/view" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: $SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{}' > /tmp/crawlnode-view1.txt
echo "  $(wc -c < /tmp/crawlnode-view1.txt) bytes written"

# --- 4. Screenshot ---
echo "Calling $API/api/screenshot (/tmp/crawlnode-screenshot.png)"
curl -sS -X POST "$API/api/screenshot" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: $SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{}' \
  --output /tmp/crawlnode-screenshot.png

if [ ! -s /tmp/crawlnode-screenshot.png ]; then
  echo "ERROR: screenshot file is empty" >&2
  exit 1
fi
echo "  $(wc -c < /tmp/crawlnode-screenshot.png) bytes written"

# --- 5. Upload screenshot via passimage ---
SCREENSHOT_URL=$(curl -sS -X POST "${PASSIMAGE_FILES_URL}/upload" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: image/png" \
  -H "X-Filename: crawlnode-screenshot.png" \
  --data-binary "@/tmp/crawlnode-screenshot.png")

echo "SCREENSHOT: $SCREENSHOT_URL"

echo ""
echo "Done. Session $SESSION_ID will be destroyed on exit."
