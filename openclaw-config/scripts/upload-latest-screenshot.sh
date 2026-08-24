#!/usr/bin/env bash
# upload-latest-screenshot.sh
# Uploads the most recent screenshot from ~/.openclaw/media/browser/ to
# s.passimage.in and prints the resulting public URL on stdout.
#
# Why this exists: the `browser` tool saves screenshots to disk but does not
# return the path to the LLM (it only returns a vision-model description of
# the image). So a specialist agent needs an out-of-band way to find and
# upload the file. Putting the whole flow in one script means the agent
# only has to call ONE short exec command — a tiny target that even the
# cheapest LLM cannot easily corrupt (no long env-var names to truncate,
# no multi-arg curl to reorder).
#
# Usage:
#   upload-latest-screenshot.sh              # uploads newest PNG in media/browser/
#   upload-latest-screenshot.sh /path/to.png # uploads a specific file
#
# On success: prints ONE line, the public URL (e.g. https://s.passimage.in/f/abc.png)
# On failure: prints "ERROR: <reason>" to stderr and exits 1

set -euo pipefail

MEDIA_DIR="${OPENCLAW_MEDIA_DIR:-$HOME/.openclaw/media/browser}"
API_URL="https://s.passimage.in/upload"

if [ -n "${1:-}" ]; then
  FILE="$1"
else
  FILE=$(ls -t "$MEDIA_DIR"/*.png 2>/dev/null | head -1 || true)
fi

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "ERROR: no screenshot file found in $MEDIA_DIR" >&2
  exit 1
fi

if [ -z "${PASSIMAGE_FILES_API_KEY:-}" ]; then
  echo "ERROR: PASSIMAGE_FILES_API_KEY env var is not set" >&2
  exit 1
fi

RESPONSE=$(curl -sS --fail-with-body -X POST "$API_URL" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: image/png" \
  -H "X-Filename: $(basename "$FILE")" \
  --data-binary "@$FILE" 2>&1) || {
  echo "ERROR: passimage upload failed: $RESPONSE" >&2
  exit 1
}

URL=$(echo "$RESPONSE" | jq -r "(.url // .publicUrl // .link // empty)" 2>/dev/null || true)

if [ -z "$URL" ] || [ "$URL" = "null" ]; then
  echo "ERROR: passimage response had no URL. Body: $RESPONSE" >&2
  exit 1
fi

echo "$URL"
