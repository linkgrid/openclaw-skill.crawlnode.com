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
#   upload-latest-screenshot.sh              # uploads newest image in media/browser/
#   upload-latest-screenshot.sh /path/to.jpg # uploads a specific file
#
# Supported extensions: .png, .jpg, .jpeg (case-insensitive). OpenClaw
# 2026.6.x defaults to .jpg for screenshots; older versions used .png.
#
# On success: prints ONE line, the public URL (e.g. https://s.passimage.in/f/abc.png)
#             AND sweeps image files older than 30 minutes from MEDIA_DIR so
#             stale files can't be picked up by future runs.
# On failure: prints "ERROR: <reason>" to stderr and exits 1

set -euo pipefail

MEDIA_DIR="${OPENCLAW_MEDIA_DIR:-$HOME/.openclaw/media/browser}"
API_URL="https://s.passimage.in/upload"
STALE_MINUTES="${OPENCLAW_MEDIA_STALE_MINUTES:-30}"

if [ -n "${1:-}" ]; then
  FILE="$1"
else
  # Newest image, regardless of extension. ls -t sorts by modification time,
  # newest first; we pick the very first entry. Globs that match nothing are
  # silenced by the 2>/dev/null redirect.
  FILE=$(ls -t \
    "$MEDIA_DIR"/*.png \
    "$MEDIA_DIR"/*.jpg \
    "$MEDIA_DIR"/*.jpeg \
    "$MEDIA_DIR"/*.PNG \
    "$MEDIA_DIR"/*.JPG \
    "$MEDIA_DIR"/*.JPEG \
    2>/dev/null | head -1 || true)
fi

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "ERROR: no screenshot file found in $MEDIA_DIR" >&2
  exit 1
fi

if [ -z "${PASSIMAGE_FILES_API_KEY:-}" ]; then
  echo "ERROR: PASSIMAGE_FILES_API_KEY env var is not set" >&2
  exit 1
fi

# Pick Content-Type from the file extension so JPGs upload as image/jpeg.
FILE_LOWER="${FILE,,}"
case "$FILE_LOWER" in
  *.png)        CONTENT_TYPE="image/png" ;;
  *.jpg|*.jpeg) CONTENT_TYPE="image/jpeg" ;;
  *)            CONTENT_TYPE="application/octet-stream" ;;
esac

RESPONSE=$(curl -sS --fail-with-body -X POST "$API_URL" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: $CONTENT_TYPE" \
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

# Cleanup: remove image files older than STALE_MINUTES so the media folder
# doesn't grow unbounded and older screenshots can't be picked up by mistake
# on future runs. Errors are swallowed so cleanup never fails the upload.
find "$MEDIA_DIR" -maxdepth 1 -type f \
  \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) \
  -mmin "+${STALE_MINUTES}" -delete 2>/dev/null || true

echo "$URL"
