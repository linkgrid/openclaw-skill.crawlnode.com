#!/usr/bin/env bash
# refresh-openclaw.sh
#
# Single-command refresh for an OpenClaw machine (Claw1, Claw2, ...). This is
# the ONLY script an operator should have to run to redeploy every change made
# in the openclaw-skill.crawlnode.com repo:
#
#   1. Pull latest from GitHub
#   2. Sync skills (top-level folders containing SKILL.md)
#   3. Sync per-agent AGENTS.md files into each agent's workspace folder
#      (source of truth: agents/<agent-id>/AGENTS.md; target: read from
#      the sibling WORKSPACE file)
#   4. Install helper scripts (openclaw-config/scripts/*.sh) into
#      ~/.openclaw/scripts/ so agents can call them via `exec`
#   5. Apply the multi-agent config overlay via `openclaw config patch`
#   6. Self-update this refresh script (copy the repo's version over ~/scripts/)
#   7. Restart the OpenClaw gateway
#
# Idempotent: safe to re-run any time. Exits non-zero on the first failure.
#
# Version: 2 (adds steps 3, 4, 5, 6). Version 1 only did steps 1, 2, 7.

set -euo pipefail

REPO="https://github.com/linkgrid/openclaw-skill.crawlnode.com.git"
CLONE_DIR="/tmp/openclaw-skills-pull"
SKILLS_DIR="$HOME/.openclaw/skills"
OPENCLAW_HOME="$HOME/.openclaw"
LOCAL_SCRIPTS_DIR="$HOME/.openclaw/scripts"          # agent-callable helper scripts
OP_SCRIPTS_DIR="$HOME/scripts"                        # operator scripts (this file, wifi-watchdog, ...)
OC="$HOME/.npm-global/bin/openclaw"

echo "=== OpenClaw Refresh (v2) ==="
echo "Host: $(hostname)   User: $USER   Time: $(date)"
echo

# ---------------------------------------------------------------------------
# [1/7] Pull latest from GitHub
# ---------------------------------------------------------------------------
echo "[1/7] Pulling latest from $REPO..."
rm -rf "$CLONE_DIR"
if git clone --depth 1 "$REPO" "$CLONE_DIR" 2>/dev/null; then
  echo "  -> Cloned into $CLONE_DIR"
else
  echo "  -> ERROR: Failed to clone repo" >&2
  exit 1
fi
echo

# ---------------------------------------------------------------------------
# [2/7] Sync skills (top-level folders containing SKILL.md)
# ---------------------------------------------------------------------------
echo "[2/7] Syncing skills to $SKILLS_DIR..."
mkdir -p "$SKILLS_DIR"
for skill_dir in "$CLONE_DIR"/*/; do
  skill_name=$(basename "$skill_dir")
  [ -f "$skill_dir/SKILL.md" ] || continue
  mkdir -p "$SKILLS_DIR/$skill_name"
  cp -r "$skill_dir"/* "$SKILLS_DIR/$skill_name/"
  echo "  -> Updated skill: $skill_name"
done
if [ -f "$CLONE_DIR/SKILLS.json" ]; then
  cp "$CLONE_DIR/SKILLS.json" "$SKILLS_DIR/SKILLS.json"
  echo "  -> Updated SKILLS.json (registry)"
fi
echo

# ---------------------------------------------------------------------------
# [3/7] Sync per-agent AGENTS.md files
# ---------------------------------------------------------------------------
# Convention: each folder under agents/ contains AGENTS.md (the prompt) and
# WORKSPACE (a one-line file with the absolute target directory, allowed to
# reference $HOME). If a repo adds a new agent, drop a folder here with those
# two files and it auto-deploys.
echo "[3/7] Syncing AGENTS.md files..."
if [ -d "$CLONE_DIR/agents" ]; then
  for agent_dir in "$CLONE_DIR"/agents/*/; do
    agent_name=$(basename "$agent_dir")
    [ -f "$agent_dir/AGENTS.md" ] || { echo "  -> SKIP $agent_name (no AGENTS.md)"; continue; }
    [ -f "$agent_dir/WORKSPACE" ] || { echo "  -> SKIP $agent_name (no WORKSPACE file)"; continue; }
    target_dir=$(eval echo "$(cat "$agent_dir/WORKSPACE" | tr -d '\r\n')")
    if [ -z "$target_dir" ]; then
      echo "  -> SKIP $agent_name (empty WORKSPACE)"; continue
    fi
    mkdir -p "$target_dir"
    # Back up the existing AGENTS.md if it's about to change, so we always
    # have one rollback candidate on disk.
    if [ -f "$target_dir/AGENTS.md" ] && ! cmp -s "$agent_dir/AGENTS.md" "$target_dir/AGENTS.md"; then
      cp "$target_dir/AGENTS.md" "$target_dir/AGENTS.md.bak-$(date +%Y%m%d-%H%M%S)"
    fi
    cp "$agent_dir/AGENTS.md" "$target_dir/AGENTS.md"
    echo "  -> Updated $agent_name  →  $target_dir/AGENTS.md"
  done
else
  echo "  -> No agents/ folder in repo (skipping)"
fi
echo

# ---------------------------------------------------------------------------
# [4/7] Install agent-callable helper scripts
# ---------------------------------------------------------------------------
# These are shell scripts that specialist agents call via `exec` (e.g. the
# passimage screenshot uploader). Everything in openclaw-config/scripts/ ends
# up in ~/.openclaw/scripts/ EXCEPT refresh-openclaw.sh, which is an operator
# script and gets handled in step [6].
echo "[4/7] Installing agent helper scripts to $LOCAL_SCRIPTS_DIR..."
mkdir -p "$LOCAL_SCRIPTS_DIR"
if [ -d "$CLONE_DIR/openclaw-config/scripts" ]; then
  for script_path in "$CLONE_DIR"/openclaw-config/scripts/*.sh; do
    [ -f "$script_path" ] || continue
    script_name=$(basename "$script_path")
    if [ "$script_name" = "refresh-openclaw.sh" ]; then
      continue
    fi
    cp "$script_path" "$LOCAL_SCRIPTS_DIR/$script_name"
    chmod +x "$LOCAL_SCRIPTS_DIR/$script_name"
    echo "  -> Installed $script_name"
  done
else
  echo "  -> No openclaw-config/scripts/ in repo (skipping)"
fi
echo

# ---------------------------------------------------------------------------
# [5/7] Apply multi-agent config overlay
# ---------------------------------------------------------------------------
# `openclaw config patch` merges objects recursively and REPLACES arrays.
# So the overlay is the source of truth for agents.list[], acp.defaultAgent,
# and agents.defaults.subagents — nothing else in openclaw.json is touched.
echo "[5/7] Applying multi-agent config overlay..."
# We redirect openclaw's very chatty stderr to a log file rather than piping it
# through `tail`. Under ssh + shell wrappers, the pipeline sometimes gets OOM-
# killed (SIGKILL / exit 137) because the whole subshell has to buffer the
# stream. Log-file redirection sidesteps that entirely.
OVERLAY="$CLONE_DIR/openclaw-config/multi-agent-overlay.json5"
OVERLAY_LOG="/tmp/openclaw-refresh-overlay.log"
if [ -f "$OVERLAY" ]; then
  # Dry-run first so we fail loud without touching live config.
  if $OC config patch --file "$OVERLAY" --dry-run >"$OVERLAY_LOG" 2>&1; then
    if $OC config patch --file "$OVERLAY" >>"$OVERLAY_LOG" 2>&1; then
      echo "  -> Applied overlay from $OVERLAY (log: $OVERLAY_LOG)"
    else
      echo "  -> ERROR: overlay apply failed. See $OVERLAY_LOG" >&2
      exit 1
    fi
  else
    echo "  -> ERROR: overlay failed dry-run validation. See $OVERLAY_LOG" >&2
    exit 1
  fi
else
  echo "  -> No overlay file at $OVERLAY (skipping)"
fi
echo

# ---------------------------------------------------------------------------
# [6/7] Self-update this refresh script
# ---------------------------------------------------------------------------
# Copy the freshest version of this file over ~/scripts/refresh-openclaw.sh
# so future runs automatically pick up any changes committed to the repo.
# Safe while running: Linux keeps the currently-executing file open.
echo "[6/7] Self-updating refresh script..."
NEW_SELF="$CLONE_DIR/openclaw-config/scripts/refresh-openclaw.sh"
SELF_TARGET="$OP_SCRIPTS_DIR/refresh-openclaw.sh"
mkdir -p "$OP_SCRIPTS_DIR"
if [ -f "$NEW_SELF" ]; then
  if [ ! -f "$SELF_TARGET" ] || ! cmp -s "$NEW_SELF" "$SELF_TARGET"; then
    [ -f "$SELF_TARGET" ] && cp "$SELF_TARGET" "$SELF_TARGET.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$NEW_SELF" "$SELF_TARGET"
    chmod +x "$SELF_TARGET"
    echo "  -> Updated $SELF_TARGET (next run uses new version)"
  else
    echo "  -> Already up to date"
  fi
else
  echo "  -> No refresh-openclaw.sh in repo (skipping self-update)"
fi
echo

# ---------------------------------------------------------------------------
# [7/7] Restart the gateway
# ---------------------------------------------------------------------------
# Kill stray gateway processes first (defence against duplicates), then let
# systemd (or a raw nohup) bring it back up. Both agent + config changes
# above need this restart to take effect.
echo "[7/7] Restarting OpenClaw gateway..."
pkill -f 'openclaw-gateway' 2>/dev/null || true
pkill -f 'openclaw gateway' 2>/dev/null || true
sleep 2
if systemctl --user cat openclaw-gateway &>/dev/null; then
  systemctl --user restart openclaw-gateway
  sleep 3
  systemctl --user is-active openclaw-gateway && echo "  -> Gateway is active"
else
  echo "  -> No systemd unit found. Starting via CLI..."
  nohup $OC gateway > /tmp/openclaw-gateway.log 2>&1 &
  sleep 3
  echo "  -> Gateway PID: $!"
fi

rm -rf "$CLONE_DIR"

echo
echo "=== Refresh complete ==="
echo "Source: $REPO"
echo "Skills:      $SKILLS_DIR"
echo "Agent MDs:   \$HOME/.openclaw/workspace*/AGENTS.md"
echo "Helpers:     $LOCAL_SCRIPTS_DIR"
echo "Config:      $OPENCLAW_HOME/openclaw.json (via openclaw config patch)"
