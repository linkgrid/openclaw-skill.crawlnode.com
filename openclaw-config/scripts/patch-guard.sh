#!/usr/bin/env bash
# patch-guard.sh
#
# The "doormat" that runs BEFORE the OpenClaw gateway starts, every time.
# Walks through every *.sh in ~/.openclaw/patches/, executes each one, and
# lets each patch decide whether it needs to be applied (idempotency lives
# inside each patch file).
#
# This is what makes our patches survive `npm update -g openclaw` — even if
# an upgrade wipes the modified source files, this script re-applies every
# patch on the next gateway restart before the gateway boots.
#
# Wired into systemd via a drop-in override:
#   ~/.config/systemd/user/openclaw-gateway.service.d/patch-guard.conf
#
# Which adds:
#   [Service]
#   ExecStartPre=/home/autoscale/.openclaw/scripts/patch-guard.sh
#
# The drop-in file is installed by refresh-openclaw.sh (step [5/8]).

set -e
PATCHES_DIR="$HOME/.openclaw/patches"

if [ ! -d "$PATCHES_DIR" ]; then
  echo "[patch-guard] no patches folder at $PATCHES_DIR — nothing to do"
  exit 0
fi

total=0
applied=0
failed=0
for patch in "$PATCHES_DIR"/*.sh; do
  [ -f "$patch" ] || continue
  total=$((total + 1))
  if bash "$patch"; then
    applied=$((applied + 1))
  else
    failed=$((failed + 1))
    echo "[patch-guard] patch failed: $(basename "$patch")" >&2
  fi
done

echo "[patch-guard] $applied/$total patch(es) ok, $failed failed"

if [ "$failed" -gt 0 ]; then
  exit 1
fi
