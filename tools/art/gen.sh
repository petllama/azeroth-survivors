#!/usr/bin/env bash
# Regenerate sprite candidates with the local SwarmUI model (FLUX 3 Klein, --raw = no LLM prompt upsampler).
#   tools/art/gen.sh            # all sprites
#   tools/art/gen.sh ghoul bat  # only these
# Candidates land in tools/art/out/raw/<name>_<seed>.png. Then run process.py.
set -euo pipefail
cd "$(dirname "$0")"
N=${N:-4}
MODEL=${MODEL:-flux}
STYLE="dark-fantasy World of Warcraft inspired hand-painted game sprite, viewed from a slightly top-down three-quarter angle, bold readable silhouette, thick dark outline, saturated colours, single centered subject, full body uncropped with generous margin around it, plain flat pure white background, no text, no ground shadow, isolated game asset"
STYLE_GLOW="dark-fantasy World of Warcraft inspired hand-painted spell effect game sprite, single centered subject with generous margin, bright luminous glow, plain pure black background, no text, isolated game asset"
STYLE_TILE="hand-painted dark-fantasy World of Warcraft style game ground texture, painterly"
mkdir -p out/raw
want=" $* "
while IFS='|' read -r name seed kind subject; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  [[ $# -gt 0 && "$want" != *" $name "* ]] && continue
  case "$kind" in
    sprite) prompt="$subject. $STYLE" ;;
    glow)   prompt="$subject. $STYLE_GLOW" ;;
    tile)   prompt="$subject. $STYLE_TILE" ;;
  esac
  echo ">> $name (seeds $seed..$((seed+N-1)))" >&2
  tmp=$(mktemp -d)
  imagine -m "$MODEL" --raw -n "$N" --seed "$seed" -o "$tmp" "$prompt" > "$tmp/list"
  i=0
  while read -r f; do
    mv "$f" "out/raw/${name}_$((seed+i)).png"; i=$((i+1))
  done < "$tmp/list"
  rm -rf "$tmp"
done < prompts.txt
