#!/usr/bin/env bash
# scripts/raster-prep.sh <rawdir> <out.tif>
# Finds the largest raster image in <rawdir> (Natural Earth zips hold a few)
# and writes a georeferenced copy to <out.tif>. Natural Earth rasters can lack
# georeferencing or an SRS, so those get the world extent in EPSG:4326.
# NOTE: deliberately no pipefail - `... | head -1` closes the pipe after one
# line (see summary.sh for why that must not abort).
set -eu

RAW="$1"
OUT="$2"

SRC="$(find "$RAW" -maxdepth 2 -type f \( -iname '*.tif' -o -iname '*.tiff' \
  -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0 \
  | xargs -0 ls -S 2>/dev/null | head -1 || true)"
if [ -z "$SRC" ]; then
  echo "ERROR: no raster image found in $RAW" >&2
  exit 1
fi
echo ">> Source raster: $SRC"

if ! gdalinfo "$SRC" 2>/dev/null | grep -q "Origin"; then
  echo ">> Not georeferenced - assigning world extent (EPSG:4326) ..."
  gdal_translate -q -a_srs EPSG:4326 -a_ullr -180 90 180 -90 "$SRC" "$OUT"
elif ! gdalinfo "$SRC" 2>/dev/null | grep -q "Coordinate System is"; then
  echo ">> Georeferenced but no SRS - assigning EPSG:4326 ..."
  gdal_translate -q -a_srs EPSG:4326 "$SRC" "$OUT"
else
  cp "$SRC" "$OUT"
fi
echo ">> Prepared: $OUT"
