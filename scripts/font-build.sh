#!/usr/bin/env bash
# scripts/font-build.sh <root> <fontdir>
#
# Builds MapLibre glyph PBFs into <fontdir>/<Font Stack>/<range>.pbf from Google
# Fonts' Noto Sans family (Regular/Bold + Arabic + Hebrew) using fontnik's
# build-glyphs. Idempotent: ttf downloads, CSS lookups and glyph output are all
# cached under <root>/.font-src and only rebuilt when missing.
#
#   <fontdir>/Noto Sans Regular/        (Latin, Greek, Cyrillic, Vietnamese)
#   <fontdir>/Noto Sans Bold/
#   <fontdir>/Noto Sans Arabic Regular/ (Arabic)
#   <fontdir>/Noto Sans Hebrew Regular/ (Hebrew)
#
# In style.json point the vector source at the glyphs:
#   "glyphs": "font/{fontstack}/{range}.pbf"
# and set text-font to a SINGLE built font (static hosts can't merge glyphs
# across the separate font/<font>/ folders - see make/font.mk).
set -euo pipefail

ROOT="$1"
FONT_DIR="$2"
SRC_DIR="$ROOT/.font-src"        # downloaded ttf / css (throwaway, gitignored)
TOOLS_DIR="$ROOT/.font-tools"    # local fontnik install (throwaway, gitignored)

# Fonts to build: "<Google Fonts CSS family>|<stack base>|<weight:style ...>"
FONTS=(
  "Noto Sans|Noto Sans|400:Regular 700:Bold"
  "Noto Sans Arabic|Noto Sans Arabic|400:Regular"
  "Noto Sans Hebrew|Noto Sans Hebrew|400:Regular"
)

# Map a Google Fonts weight number to the style name used in the stack/folder
# name. (Kept as a function: macOS ships bash 3.2 which cannot parse "case"
# inside $().)
weight_to_style() {
  case "$1" in
    100) echo "Thin" ;;
    200) echo "ExtraLight" ;;
    300) echo "Light" ;;
    400) echo "Regular" ;;
    500) echo "Medium" ;;
    600) echo "SemiBold" ;;
    700) echo "Bold" ;;
    800) echo "ExtraBold" ;;
    900) echo "Black" ;;
    *)   echo "" ;;
  esac
}

# curl -fsSL with a few retries (Google Fonts occasionally 400/429s bursts)
curl_retry() {
  local tries=5 n=0
  until curl -fsSL "$@"; do
    n=$((n + 1))
    if [ "$n" -ge "$tries" ]; then
      echo "ERROR: curl failed after $tries tries: $*" >&2
      return 1
    fi
    echo ">> retry $n/$tries ..." >&2
    sleep 2
  done
}

mkdir -p "$SRC_DIR" "$TOOLS_DIR"

# --- 1. fontnik (local install, no sudo) ------------------------------------
BUILD_GLYPHS="$TOOLS_DIR/node_modules/.bin/build-glyphs"
if [ ! -x "$BUILD_GLYPHS" ]; then
  echo ">> Installing fontnik into $TOOLS_DIR ..."
  npm install --prefix "$TOOLS_DIR" --no-audit --no-fund fontnik >/dev/null 2>&1 || {
    echo "ERROR: npm install of fontnik failed. Run manually:" >&2
    echo "  npm install --prefix '$TOOLS_DIR' fontnik" >&2
    exit 1
  }
fi
if ! node -e "require('$TOOLS_DIR/node_modules/fontnik'); process.exit(0)" 2>/dev/null; then
  echo "ERROR: fontnik native module not loadable for $(node -p "process.platform+'-'+process.arch")." >&2
  echo "  Reinstall it manually:  npm install --prefix '$TOOLS_DIR' fontnik" >&2
  exit 1
fi

# --- 2. fetch/download/build each font stack ---------------------------------
build_font() {
  local css_family="$1" stack="$2" weights="$3"
  local slug wght w url ttf out stamp style css_url
  slug="$(echo "$stack" | tr ' ' '-')"

  # weight list for the CSS url, e.g. "400;700"
  wght=""
  for w in $weights; do
    w="${w%%:*}"   # strip the ":Style" suffix
    if [ -n "$wght" ]; then wght="$wght;$w"; else wght="$w"; fi
  done

  # CSS -> weight/url list, fetched once (curl user agent => truetype urls)
  if [ ! -s "$SRC_DIR/$slug.urls" ]; then
    css_url="https://fonts.googleapis.com/css2?family=${css_family// /+}:wght@${wght}&display=swap"
    echo ">> Fetching $stack CSS from Google Fonts ..."
    curl_retry "$css_url" | awk '
      /font-weight:/ { w = $2; sub(/;/, "", w) }
      /url\(/ {
        u = $0; sub(/^.*url\(/, "", u); sub(/\).*/, "", u)
        if (u ~ /\.ttf/) print w, u
      }
    ' > "$SRC_DIR/$slug.urls" || { rm -f "$SRC_DIR/$slug.urls"; exit 1; }
    [ -s "$SRC_DIR/$slug.urls" ] || {
      echo "ERROR: no TTF URLs returned for $stack - response format changed?" >&2
      exit 1
    }
  fi

  while read -r w url; do
    style="$(weight_to_style "$w")"
    [ -n "$style" ] || continue   # skip unrequested weights

    ttf="$SRC_DIR/$slug-$style.ttf"
    if [ ! -f "$ttf" ]; then
      echo ">> Downloading $stack $style -> $(basename "$ttf")"
      curl_retry "$url" -o "$ttf" || { rm -f "$ttf"; exit 1; }
    fi

    out="$FONT_DIR/$stack $style"
    stamp="$SRC_DIR/.built-$slug-$style"
    # stamp >= ttf counts as up to date (equal mtimes when both touch in one second)
    if [ -d "$out" ] && [ -f "$stamp" ] && ! [ "$stamp" -ot "$ttf" ]; then
      echo ">> up to date: $stack $style"
      continue
    fi
    echo ">> Building glyphs for \"$stack $style\" -> $out"
    mkdir -p "$out"
    "$BUILD_GLYPHS" "$ttf" "$out"
    touch "$stamp"
  done < "$SRC_DIR/$slug.urls"
}

for entry in "${FONTS[@]}"; do
  IFS='|' read -r family stack weights <<< "$entry"
  build_font "$family" "$stack" "$weights"
done

# --- 3. summary --------------------------------------------------------------
echo
echo "Done. Glyph sets in $FONT_DIR:"
for d in "$FONT_DIR"/*/; do
  [ -d "$d" ] || continue
  n="$(find "$d" -name '*.pbf' | wc -l | tr -d ' ')"
  echo "  - $d ($n pbf files)"
done

echo
echo "Next steps:"
echo "  1. style.json: \"glyphs\": \"font/{fontstack}/{range}.pbf\""
echo "  2. style.json (countries-label layer): \"text-font\": [\"Noto Sans Regular\"]"
echo "     (a SINGLE built font - static hosts cannot merge glyph stacks)"
echo "  3. Commit the font/ folder (caches .font-src/ .font-tools/ are gitignored)."
