#!/usr/bin/env bash

# exit on error / unset var / any failing pipe step
set -euo pipefail

# create_vector_tiles.sh
# ---------------------------------------------------------------------------
# Builds a self-hosted vector tile pyramid (MVT = Mapbox Vector Tile; .pbf =
# protobuf-encoded; {z}/{x}/{y}, Web Mercator) from the Natural Earth 1:10m
# admin-0 countries shapefile - the dataset behind the style.json vector source
# (source-layer "countries", served from ./tiles/).
#
#   ./create_vector_tiles.sh [method] [maxzoom]
#     method     which pipeline to use        (default: tile-join)
#                direct | tile-join | mb-util | ogr2ogr
#     maxzoom    top zoom of the pyramid      (default: 8)
#
#   ./create_vector_tiles.sh prune   remove only the .vector-src/ build cache
#   ./create_vector_tiles.sh clean   also remove ./tiles/ (build cache + dist)
#
#   OUT_DIR=/some/dir ./create_vector_tiles.sh ...   (redirect output folder)
#
# Choose the pipeline with `method` - every method writes into ./tiles/:
#
#   method      ogr2ogr -> tippecanoe -> extract with          writes
#   ----------  ---------------------------------------------------------
#   direct      shp -> MVT dir              (none)             raw MVT
#   tile-join   shp -> GeoJSON -> .mbtiles -> tile-join        raw MVT
#   ogr2ogr     shp -> GeoJSON -> .mbtiles -> ogr2ogr -f MVT   raw MVT
#   mb-util     shp -> GeoJSON -> .mbtiles -> mbutil/mb-util   gzip MVT*
#   * = decompressed by the script before you serve ./tiles/ (see below).
#
# Which methods need the decompressing step, and which don't:
# MapLibre fetches {z}/{x}/{y}.pbf, and static hosts (GitHub Pages) serve .pbf
# WITHOUT "Content-Encoding: gzip", so the bytes on disk must be RAW
# (uncompressed) MVT. tippecanoe always stores gzip-compressed tiles inside the
# .mbtiles, so it comes down to the extractor:
#   - tile-join:  --no-tile-compression  => writes raw   => no extra step
#   - ogr2ogr:    -dsco COMPRESS=NO      => writes raw   => no extra step
#   - mb-util:    copies the .mbtiles blobs out VERBATIM and has no option to
#                 uncompress them        => writes gzip  => MUST decompress
# So the script runs the gzip -dc loop ONLY for the mb-util method.
# (Leaving out --no-tile-compression / COMPRESS=NO would also produce gzip and
#  would need that same loop - the GDAL MVT driver's default is COMPRESS=YES.)
#
# Note: 'direct' and 'ogr2ogr' tiles keep full-precision geometry (no per-zoom
# simplification), so they are far larger than the tippecanoe methods and best
# used for comparison or low maxzooms. tippecanoe + tile-join + mb-util are
# byte-identical after decompression; tile-join is the simplest/fastest.
#
# Requires: curl, unzip, ogr2ogr (GDAL), tippecanoe; tile-join for that method;
#           python3 + sqlite3 for metadata/tiles.json; and for mb-util a checkout
#           of mapbox/mbutil (auto-detected or cloned by the script).
#
# Output:
#   ./tiles/    {z}/{x}/{y}.pbf + metadata.json + tiles.json   (style.json reads)
#
#   Downloads & intermediates (.zip, .shp, .geojson, .mbtiles) and the optional
#   mbutil clone live in .vector-src/, shared by all methods.
# ---------------------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

METHOD="${1:-tile-join}"
MAX_ZOOM="${2:-8}"
MIN_ZOOM=0

OUT="${OUT_DIR:-$ROOT/tiles}"

# Natural Earth 1:10m cultural admin-0 countries (the "countries" source layer)
ZIP_URL="https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip"
ZIP_NAME="${ZIP_URL##*/}"
SHP_BASENAME="ne_10m_admin_0_countries"

WORK="$ROOT/.vector-src"   # downloads + intermediates (gitignored, throwaway)
RAW="$WORK/$SHP_BASENAME"   # extracted shapefile
SHP="$RAW/$SHP_BASENAME.shp"
GEOJSON="$WORK/countries.geojson"
MBTILES="$WORK/countries-z$MAX_ZOOM.mbtiles"

die() { echo "ERROR: $*" >&2; exit 1; }

# tool -> Homebrew formula (Homebrew's tippecanoe formula ships tile-join too)
brew_pkg() {
  case "$1" in
    ogr2ogr)    echo gdal;;
    tippecanoe) echo tippecanoe;;
    tile-join)  echo tippecanoe;;
    python3)    echo python;;
    sqlite3)    echo sqlite;;
    curl)       echo curl;;
    unzip)      echo unzip;;
  esac
}

# Require the given tools; if any are missing, print the Homebrew command(s) to
# install them and exit. No auto-install - the script stays non-interactive.
need() {
  local miss="" pkgs="" pkg
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      miss="$miss $c"
      pkg="$(brew_pkg "$c")"
      [ -n "$pkg" ] && pkgs="$pkgs $pkg"
    fi
  done
  if [ -n "$miss" ]; then
    echo "ERROR: missing required tool(s):$miss" >&2
    if [ -n "$pkgs" ]; then
      echo "  Install with Homebrew:" >&2
      echo "    brew install $(printf '%s\n' $pkgs | sort -u | paste -sd ' ' -)" >&2
    fi
    exit 1
  fi
}

# Validate the method, then handle 'clean' before doing any real work.
case "$METHOD" in
  direct|tile-join|mb-util|ogr2ogr|clean|prune) ;;
  *)
    echo "ERROR: unknown method '$METHOD'." >&2
    echo "Usage: ./create_vector_tiles.sh [method] [maxzoom]" >&2
    echo "  method: direct | tile-join | mb-util | ogr2ogr | clean | prune   (default tile-join)" >&2
    echo "  maxzoom: top zoom of the pyramid                         (default 8)" >&2
    exit 1
    ;;
esac

# 'clean' removes everything this script produces: the dist tiles (./tiles/)
# plus the .vector-src/ build cache (downloads, intermediates, mbutil clone).
# 'prune' removes only that .vector-src/ build cache, keeping ./tiles/ intact.
if [ "$METHOD" = "clean" ] || [ "$METHOD" = "prune" ]; then
  if [ "$METHOD" = "clean" ]; then
    echo ">> clean: removing dist $OUT"
    rm -rf "$OUT"
  fi
  echo ">> $METHOD: removing build cache $WORK"
  rm -rf "$WORK"
  exit 0
fi

case "$METHOD" in
  direct)    need curl unzip ogr2ogr;;
  tile-join) need curl unzip ogr2ogr tippecanoe tile-join;;
  mb-util)   need curl unzip ogr2ogr tippecanoe python3;;
  ogr2ogr)   need curl unzip ogr2ogr tippecanoe;;
esac

mkdir -p "$WORK"

# --- 1. Download + unzip the source shapefile ---------------------------------
if [ ! -f "$WORK/$ZIP_NAME" ]; then
  echo ">> Downloading $ZIP_NAME ..."
  curl -fL "$ZIP_URL" -o "$WORK/$ZIP_NAME"
fi

# Natural Earth zips hold loose files at the archive root (no wrapping folder),
# so extract into $RAW and point SHP at $RAW/$SHP_BASENAME.shp.
if [ ! -f "$SHP" ]; then
  echo ">> Unzipping ..."
  rm -rf "$RAW"
  unzip -q "$WORK/$ZIP_NAME" -d "$RAW"
fi
echo ">> Source shapefile: $SHP"

# --- 2. Convert shp -> GeoJSON (only the tippecanoe methods need it) ----------
if [ "$METHOD" != "direct" ] && [ ! -f "$GEOJSON" ]; then
  echo ">> ogr2ogr shp -> GeoJSON"
  ogr2ogr -f GeoJSON "$GEOJSON" "$SHP"
fi

# --- 3. Build the .mbtiles with tippecanoe (shared by 3 of the 4 methods) -----
if [ "$METHOD" != "direct" ] && [ ! -f "$MBTILES" ]; then
  echo ">> tippecanoe -> $(basename "$MBTILES") (z$MIN_ZOOM-$MAX_ZOOM)"
  tippecanoe -o "$MBTILES" -z "$MAX_ZOOM" \
    --drop-densest-as-needed \
    --extend-zooms-if-still-dropping \
    "$GEOJSON"
fi

# --- 4. Extract the tiles with the chosen method ------------------------------
rm -rf "$OUT"   # drop stale tiles from an earlier, larger run

if [ "$METHOD" = "direct" ]; then
  # GDAL tiles the shapefile straight to MVT. COMPRESS=NO => raw MVT, so no
  # decompress step. -nln countries keeps the layer named like tippecanoe's
  # output ("countries"), which is the source-layer style.json expects.
  echo ">> ogr2ogr (direct) shp -> MVT $OUT  (COMPRESS=NO)"
  ogr2ogr -f MVT "$OUT" "$SHP" -nln countries \
    -dsco MINZOOM=$MIN_ZOOM -dsco MAXZOOM=$MAX_ZOOM -dsco COMPRESS=NO

elif [ "$METHOD" = "tile-join" ]; then
  # tile-join writes RAW tiles when told --no-tile-compression -> no decompress.
  echo ">> tile-join --no-tile-compression -> $OUT"
  tile-join --output-to-directory="$OUT" --no-tile-compression "$MBTILES"

elif [ "$METHOD" = "mb-util" ]; then
  # mbutil copies the .mbtiles blobs out VERBATIM, and tippecanoe stores them
  # gzip-compressed, so this is the ONE method that needs the decompress step.
  if [ -x "$ROOT/build/mbutil/mb-util" ]; then
    MBUTIL="$ROOT/build/mbutil"
  elif [ -x "$WORK/mbutil/mb-util" ]; then
    MBUTIL="$WORK/mbutil"
  else
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
      n=$((n+1))
    fi
  done < <(find "$OUT" -name '*.pbf' -print0)
  echo ">> decompressed $n gzip tile(s) in $OUT"

elif [ "$METHOD" = "ogr2ogr" ]; then
  # GDAL reads the .mbtiles and re-tiles it to MVT. COMPRESS=NO => raw, so no
  # decompress step. The layer name is carried over ("countries").
  echo ">> ogr2ogr (from .mbtiles) -> MVT $OUT  (COMPRESS=NO)"
  ogr2ogr -f MVT "$OUT" "$MBTILES" \
    -dsco MINZOOM=$MIN_ZOOM -dsco MAXZOOM=$MAX_ZOOM -dsco COMPRESS=NO
fi

# --- 5. metadata.json + tiles.json (every method) ---------------------------
# The three .mbtiles methods get a uniform metadata.json rewritten from the
# .mbtiles; 'direct' keeps the one GDAL's MVT driver wrote (it has no .mbtiles).
# tiles.json is written for EVERY method: the .mbtiles methods pass --mbtiles,
# while 'direct' omits it and create_tiles_json.py reads the vector_layers GDAL
# embedded in its metadata.json instead - so no tippecanoe is needed for direct.
if [ "$METHOD" != "direct" ]; then
  echo ">> rewriting $OUT/metadata.json from .mbtiles"
  sqlite3 "$MBTILES" "SELECT json_group_object(name, value) FROM metadata;" > "$OUT/metadata.json"
fi
if [ -f "$ROOT/create_tiles_json.py" ]; then
  echo ">> writing $OUT/tiles.json"
  BASE_URL="${BASE_URL:-http://127.0.0.1:8080/$(basename "$OUT")/}"
  if [ "$METHOD" = "direct" ]; then
    # no .mbtiles: create_tiles_json.py reads vector_layers from GDAL's
    # metadata.json (its "json" field) instead
    python3 "$ROOT/create_tiles_json.py" \
      --metadata="$OUT/metadata.json" \
      --out="$OUT/tiles.json" \
      --base-url="$BASE_URL"
  else
    python3 "$ROOT/create_tiles_json.py" \
      --mbtiles="$MBTILES" \
      --metadata="$OUT/metadata.json" \
      --out="$OUT/tiles.json" \
      --base-url="$BASE_URL"
  fi
fi

# --- 6. Summary -----------------------------------------------------------------
n="$(find "$OUT" -name '*.pbf' | wc -l | tr -d ' ')"
sample="$(find "$OUT" -name '*.pbf' | head -1)"
echo
echo "Done: $n tiles -> $OUT   (method=$METHOD, z$MIN_ZOOM-$MAX_ZOOM)"
if [ "$METHOD" = "mb-util" ]; then
  echo "  decompress step: ran   (mb-util writes gzip; raw MVT needed for hosting)"
else
  echo "  decompress step: not needed (tiles already raw MVT)"
fi
if [ -n "$sample" ]; then
  echo "  sample tile:     $(file -b "$sample" | cut -c1-70)"
fi

echo
echo "Serve it:  style.json's vector source reads ./tiles/tiles.json."
if [ "$OUT" != "$ROOT/tiles" ]; then
  echo "  OUT_DIR was set, so this build is not in ./tiles/ - to ship it:"
  echo "    rm -rf tiles && cp -R \"$OUT\" tiles"
fi
echo "  Regenerate tiles.json for a different host (e.g. GitHub Pages):"
if [ "$METHOD" = "direct" ]; then
  echo "    python3 create_tiles_json.py --metadata=\"$OUT/metadata.json\" \\"
  echo "        --out=\"$OUT/tiles.json\" \\"
  echo "        --base-url=https://<host>/natural-earth-tiles/tiles/"
else
  echo "    python3 create_tiles_json.py --mbtiles=\"$MBTILES\" \\"
  echo "        --metadata=\"$OUT/metadata.json\" --out=\"$OUT/tiles.json\" \\"
  echo "        --base-url=https://<host>/natural-earth-tiles/tiles/"
fi
echo
echo "  Clean up:"
echo "    ./create_vector_tiles.sh prune   remove only the .vector-src/ build cache"
echo "    ./create_vector_tiles.sh clean   also remove ./tiles/ (build cache + dist)"
