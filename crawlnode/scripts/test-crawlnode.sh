#!/usr/bin/env bash
set -euo pipefail

for cmd in curl sed grep; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: required command '$cmd' not found. Install it first." >&2
    exit 1
  fi
done

API="${CRAWLNODE_API_URL:-http://api1.crawlnode.com:8001}"
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

# /api/go returns as soon as navigation is dispatched, not when the page has
# rendered — a screenshot taken immediately after comes back as a ~200-byte
# blank PNG and the title reads "New tab". Give Chrome time to paint.
RENDER_WAIT="${CRAWLNODE_RENDER_WAIT:-6}"
echo "Waiting ${RENDER_WAIT}s for the page to render ..."
sleep "$RENDER_WAIT"

# MANDATORY before any screenshot. /api/screenshot captures the OS window, and
# a fresh session's window is collapsed to ~97x6 px — without this you get a
# valid-looking 211-byte PNG of nothing. Must run AFTER /api/go.
echo "Calling $API/api/maximize (required for a usable screenshot) ..."
curl -sS -X POST "$API/api/maximize" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: $SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{}'
echo
sleep 2

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
SHOT_BYTES=$(wc -c < /tmp/crawlnode-screenshot.png)
echo "  $SHOT_BYTES bytes written"
# A real page render is tens of KB. Anything this small is a blank frame, which
# would otherwise be reported as a passing test with a useless screenshot URL.
if [ "$SHOT_BYTES" -lt 5000 ]; then
  echo "  WARNING: only $SHOT_BYTES bytes — this is almost certainly a blank page." >&2
  echo "  The page had not rendered yet. Retry with CRAWLNODE_RENDER_WAIT=10." >&2
fi

# --- 5. Upload screenshot via passimage ---
SCREENSHOT_URL=$(curl -sS -X POST "https://s.passimage.in/upload" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: image/png" \
  -H "X-Filename: crawlnode-screenshot.png" \
  --data-binary "@/tmp/crawlnode-screenshot.png")

echo "SCREENSHOT: $SCREENSHOT_URL"

echo ""
echo "Done. Session $SESSION_ID will be destroyed on exit."
