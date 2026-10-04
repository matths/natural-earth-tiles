#!/usr/bin/env bash
# scripts/summary.sh <outdir> <method> <minzoom> <maxzoom>
# Prints the post-publish summary + next-step hints.
# NOTE: deliberately NO pipefail. The `find ... | head -1` below closes the
# pipe after one line, so on large tile trees `find` dies of SIGPIPE (141);
# that is normal and must not abort the summary. head's own exit (0) decides.
set -eu

OUT="$1"
METHOD="$2"
MIN="$3"
MAX="$4"

n="$(find "$OUT" -name '*.pbf' | wc -l | tr -d ' ')"
sample="$(find "$OUT" -name '*.pbf' | head -1)"

echo
echo "Done: $n tiles -> $OUT   (method=$METHOD, z$MIN-$MAX)"
if [ "$METHOD" = "mb-util" ]; then
  echo "  decompress step: ran   (mb-util writes gzip; raw MVT needed for hosting)"
else
  echo "  decompress step: not needed (tiles already raw MVT)"
fi
if [ -n "$sample" ] && command -v file >/dev/null 2>&1; then
  echo "  sample tile:     $(file -b "$sample" | cut -c1-70)"
fi
echo
echo "Serve it:  the vector source in style.json reads $OUT/tiles.json."
echo "  Change BASE_URL (no rebuild - publish re-writes tiles.json):"
echo "    make vector BASE_URL=http://127.0.0.1:8080/tiles/   # local dev"
echo
echo "  Clean up (from the repo root):"
echo "    make vector-prune   remove only the .vector-src/ build cache"
echo "    make vector-clean   also remove $(basename "$OUT") (build cache + dist)"
