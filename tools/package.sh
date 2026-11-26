#!/usr/bin/env bash
# Build dist/AzerothSurvivors-<version>.zip (the AzerothSurvivors/ folder only), after the offline tests.
set -euo pipefail
cd "$(dirname "$0")/.."
v=$(sed -n 's/^## Version: //p' AzerothSurvivors/AzerothSurvivors.toc)
for f in AzerothSurvivors/*.lua; do luac5.1 -p "$f"; done
lua5.1 tests/run_addon.lua 60 >/dev/null && lua5.1 tests/test_save.lua >/dev/null
mkdir -p dist
rm -f "dist/AzerothSurvivors-$v.zip"
git ls-files AzerothSurvivors | zip -q -X "dist/AzerothSurvivors-$v.zip" -@
echo "dist/AzerothSurvivors-$v.zip"
