#!/usr/bin/env bash
# scripts/extract-mb-util.sh <root> <mbtiles> <outdir>
#
# Extract a .mbtiles (built by tippecanoe) with mapbox/mbutil, then decompress
# every tile on disk. mbutil copies the .mbtiles blobs out VERBATIM and
# tippecanoe stores them gzip-compressed, but static hosts (GitHub Pages) serve
# .pbf WITHOUT "Content-Encoding: gzip", so the bytes on disk must be RAW
# (uncompressed) MVT. This is the one extractor that needs that extra step
# (tile-join --no-tile-compression and ogr2ogr -dsco COMPRESS=NO do not).
set -euo pipefail

ROOT="$1"
MBTILES="$2"
OUT="$3"
WORK="$ROOT/.vector-src"

rm -rf "$OUT"
# No mkdir: mbutil refuses an existing output dir and creates it itself.

# Reuse an mbutil checkout if one already exists, else clone it into the
# gitignored build cache. mbutil is a python3 script.
MBUTIL=""
for cand in "$ROOT/build/mbutil" "$WORK/mbutil"; do
  if [ -x "$cand/mb-util" ]; then
    MBUTIL="$cand"
    break
  fi
done
if [ -z "$MBUTIL" ]; then
  echo ">> cloning mapbox/mbutil ..."
  git clone --depth 1 https://github.com/mapbox/mbutil.git "$WORK/mbutil"
  MBUTIL="$WORK/mbutil"
fi

echo ">> mb-util -> $OUT (output is gzip; decompressing next)"
python3 "$MBUTIL/mb-util" --silent "$MBTILES" "$OUT" --image_format=pbf

# Decompress every tile whose header is gzip (magic bytes 1f 8b).
n=0
while IFS= read -r -d '' f; do
  magic="$(od -An -tx1 -N2 "$f" | tr -d ' \n')"
  if [ "$magic" = "1f8b" ]; then
    gzip -dc "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    n=$((n + 1))
  fi
done < <(find "$OUT" -name '*.pbf' -print0)
echo ">> decompressed $n gzip tile(s) in $OUT"
