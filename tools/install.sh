#!/usr/bin/env bash
# Copy the addon's tracked files (plus Art/) into the WoW: Forever AddOns folder after a syntax check.
# A new file (first install, new .lua or new art) needs a full game restart; changed files need /reload.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${WOW_ADDONS:-/mnt/games/BattleNet/World of Warcraft/_forever_/Interface/AddOns}"
[ -d "$DEST" ] || { echo "no AddOns folder at $DEST" >&2; exit 1; }
for f in AzerothSurvivors/*.lua; do luac5.1 -p "$f"; done
lua5.1 tests/run_addon.lua 60 >/dev/null || { echo "offline addon test failed" >&2; exit 1; }
rm -rf "$DEST/AzerothSurvivors"
mkdir -p "$DEST/AzerothSurvivors"
cp AzerothSurvivors/*.lua AzerothSurvivors/*.toc "$DEST/AzerothSurvivors/"
if [ -d AzerothSurvivors/Art ]; then
  mkdir -p "$DEST/AzerothSurvivors/Art"
  cp AzerothSurvivors/Art/*.tga "$DEST/AzerothSurvivors/Art/" 2>/dev/null || true
fi
echo "installed into $DEST/AzerothSurvivors ($(grep '^## Version' AzerothSurvivors/AzerothSurvivors.toc))"
ls "$DEST/AzerothSurvivors" "$DEST/AzerothSurvivors/Art" 2>/dev/null
