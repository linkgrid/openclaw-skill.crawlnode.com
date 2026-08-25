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

set -e

FILE="$HOME/.npm-global/lib/node_modules/openclaw/dist/openclaw-tools-0r2mZn6Z.js"
MARKER="PATCH forceFullContext"

if [ ! -f "$FILE" ]; then
  echo "[001-force-full-context] target file not found at $FILE — skipping" >&2
  exit 0
fi

COUNT=$(grep -c "$MARKER" "$FILE" 2>/dev/null || true)
COUNT=${COUNT:-0}

if [ "$COUNT" = "3" ]; then
  echo "[001-force-full-context] already applied (3/3 markers)"
  exit 0
fi

# Back up the vanilla file the first time we patch it after an OpenClaw upgrade
BAK="$FILE.bak-preforcefullcontext-$(date -u +%Y%m%dT%H%M%SZ)"
cp -p "$FILE" "$BAK"

sed -i 's|const bootstrapContextMode = params\.lightContext ? "lightweight" : void 0;|const bootstrapContextMode = /*PATCH forceFullContext*/ void 0;|' "$FILE"
sed -i 's|const contextEnginePrepareResult = params\.lightContext && preparedSpawnContext\.mode === "isolated" ?|const contextEnginePrepareResult = /*PATCH forceFullContext*/ false \&\& preparedSpawnContext.mode === "isolated" ?|' "$FILE"
sed -i 's|const lightContext = params\.lightContext === true;|const lightContext = /*PATCH forceFullContext*/ false;|' "$FILE"

NEW_COUNT=$(grep -c "$MARKER" "$FILE" 2>/dev/null || true)
NEW_COUNT=${NEW_COUNT:-0}

if [ "$NEW_COUNT" = "3" ]; then
  echo "[001-force-full-context] applied (3/3 markers, backup: $BAK)"
else
  echo "[001-force-full-context] FAILED — only $NEW_COUNT/3 markers present after patch. Restoring." >&2
  cp -p "$BAK" "$FILE"
  exit 1
fi
