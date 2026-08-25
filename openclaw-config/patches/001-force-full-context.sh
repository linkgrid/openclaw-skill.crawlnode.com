#!/usr/bin/env bash
# 001-force-full-context.sh
#
# Purpose: Prevent OpenClaw's classifier from ever spawning a subagent with
#          lightContext:true, which strips the subagent's AGENTS.md rulebook
#          and causes the browser-agent to loop on screenshots.
#
# Root cause (as of OpenClaw 2026.6.34, Aug 2026):
#   The gateway reads params.lightContext from the LLM's sessions_spawn call.
#   Because the classifier is an LLM, it flips between true and false run to
#   run, so subagents randomly boot without their rulebook.
#
# Fix: Hard-code the 3 code paths that read params.lightContext to always
#      behave as if it were false. Full AGENTS.md is always shipped.
#
# Runs at every gateway start via ExecStartPre (see patch-guard.sh).
# Idempotent — safe to re-run.
#
# Target discovery: OpenClaw ships bundled files whose names carry a build
# hash (e.g. openclaw-tools-0r2mZn6Z.js) that CHANGES on every release. This
# script therefore locates the file by CONTENT, not by name, and exits
# non-zero if it cannot find it — a silent skip would let the bug return
# unnoticed after an OpenClaw upgrade.

set -e

DIST="$HOME/.npm-global/lib/node_modules/openclaw/dist"
MARKER="PATCH forceFullContext"

# The most distinctive vanilla line. Present only in the file we need to edit.
ANCHOR='const lightContext = params.lightContext === true;'

if [ ! -d "$DIST" ]; then
  echo "[001-force-full-context] ERROR: OpenClaw dist directory not found at $DIST" >&2
  exit 1
fi

# Look for an already-patched file first, then for a vanilla one. Backups
# (*.bak-*) are excluded so we never patch a copy instead of the live file.
find_candidate() {
  local needle="$1"
  grep -l -F -- "$needle" "$DIST"/*.js 2>/dev/null | grep -v '\.bak-' | head -1 || true
}

FILE=$(find_candidate "$MARKER")

if [ -n "$FILE" ]; then
  COUNT=$(grep -c -F -- "$MARKER" "$FILE" 2>/dev/null || true)
  COUNT=${COUNT:-0}
  if [ "$COUNT" = "3" ]; then
    echo "[001-force-full-context] already applied (3/3 markers) in $(basename "$FILE")"
    exit 0
  fi
  echo "[001-force-full-context] ERROR: $(basename "$FILE") has $COUNT/3 markers — partially patched." >&2
  echo "[001-force-full-context] Restore it from a .bak-preforcefullcontext-* backup or reinstall OpenClaw, then re-run." >&2
  exit 1
fi

FILE=$(find_candidate "$ANCHOR")

if [ -z "$FILE" ]; then
  echo "[001-force-full-context] ERROR: no file in $DIST contains the expected code." >&2
  echo "[001-force-full-context] Searched for: $ANCHOR" >&2
  echo "[001-force-full-context] OpenClaw's internals likely changed in this version. This patch needs updating" >&2
  echo "[001-force-full-context] in openclaw-skill.crawlnode.com before the gateway can be considered patched." >&2
  exit 1
fi

echo "[001-force-full-context] target: $(basename "$FILE")"

# Back up the vanilla file the first time we patch it after an OpenClaw upgrade
BAK="$FILE.bak-preforcefullcontext-$(date -u +%Y%m%dT%H%M%SZ)"
cp -p "$FILE" "$BAK"

sed -i 's|const bootstrapContextMode = params\.lightContext ? "lightweight" : void 0;|const bootstrapContextMode = /*PATCH forceFullContext*/ void 0;|' "$FILE"
sed -i 's|const contextEnginePrepareResult = params\.lightContext && preparedSpawnContext\.mode === "isolated" ?|const contextEnginePrepareResult = /*PATCH forceFullContext*/ false \&\& preparedSpawnContext.mode === "isolated" ?|' "$FILE"
sed -i 's|const lightContext = params\.lightContext === true;|const lightContext = /*PATCH forceFullContext*/ false;|' "$FILE"

NEW_COUNT=$(grep -c -F -- "$MARKER" "$FILE" 2>/dev/null || true)
NEW_COUNT=${NEW_COUNT:-0}

if [ "$NEW_COUNT" = "3" ]; then
  echo "[001-force-full-context] applied (3/3 markers, backup: $BAK)"
else
  echo "[001-force-full-context] FAILED — only $NEW_COUNT/3 markers present after patch. Restoring." >&2
  cp -p "$BAK" "$FILE"
  exit 1
fi
