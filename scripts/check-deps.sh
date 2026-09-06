#!/usr/bin/env bash
# scripts/check-deps.sh <method>
#
# Verifies every command-line tool the chosen pipeline needs is installed and,
# if any are missing, prints the exact install command for this platform:
#   macOS                        -> Homebrew  (brew install ...)
#   Debian / Ubuntu / WSL        -> apt-get   (sudo apt-get install ...)
# Never auto-installs; exits non-zero so `make` stops before doing any real work.
set -u

METHOD="${1:-tile-join}"

# Pick a package manager: prefer Homebrew, fall back to apt-get.
PKG_MGR=""
if command -v brew >/dev/null 2>&1; then
  PKG_MGR=brew
elif command -v apt-get >/dev/null 2>&1; then
  PKG_MGR=apt
fi

pkg() {
  local tool="$1" mgr="$2"
  case "$tool:$mgr" in
    ogr2ogr:brew|gdal_translate:brew|gdalinfo:brew|gdal2tiles.py:brew) echo gdal ;;
    ogr2ogr:apt|gdal_translate:apt|gdalinfo:apt|gdal2tiles.py:apt)    echo gdal-bin ;;
    python3:brew)     echo python ;;   # Homebrew's python formula installs python3
    sqlite3:brew)     echo sqlite ;;
    tippecanoe:*)     echo tippecanoe ;;  # the tippecanoe package ships tile-join too
    tile-join:*)      echo tippecanoe ;;
    node:brew|npm:brew) echo node ;;  # Homebrew's node formula ships npm
    node:apt)         echo nodejs ;;
    npm:apt)          echo npm ;;
    *)                echo "$tool" ;;
  esac
}

# dedupe $1 into $pkgs (macOS ships bash 3.2 - no assoc arrays)
add_pkg() {
  case " $pkgs " in
    *" $1 "*) ;;
    *) pkgs="${pkgs:+$pkgs }$1" ;;
  esac
}

# tools each module/method needs (vector methods, raster, maplibre-gl, font, country-sizes)
tools() {
  case "$1" in
    country-sizes) echo node ;;
    font)          echo curl node npm ;;
    maplibre-gl)   echo node npm ;;
    raster)        echo curl unzip python3 gdalinfo gdal_translate gdal2tiles.py ;;
    direct)      echo curl unzip python3 rsync ogr2ogr ;;
    tile-join)   echo curl unzip python3 rsync ogr2ogr tippecanoe tile-join sqlite3 ;;
    mb-util)     echo curl unzip python3 rsync ogr2ogr tippecanoe sqlite3 git ;;  # git: to clone mbutil
    ogr2ogr)     echo curl unzip python3 rsync ogr2ogr tippecanoe sqlite3 ;;
  esac
}

missing=""
for t in $(tools "$METHOD"); do
  if ! command -v "$t" >/dev/null 2>&1; then
    missing="$missing $t"
  fi
done
[ -z "$missing" ] && exit 0

echo "ERROR: missing required tool(s):$missing" >&2

case "$PKG_MGR" in
  brew)
    pkgs=""
    for t in $missing; do add_pkg "$(pkg "$t" brew)"; done
    echo "  Install with Homebrew:" >&2
    echo "    brew install $pkgs" >&2
    ;;
  apt)
    pkgs=""
    for t in $missing; do add_pkg "$(pkg "$t" apt)"; done
    if [ "$(id -u)" -eq 0 ]; then
      cmd="apt-get update && apt-get install -y $pkgs"
    elif command -v sudo >/dev/null 2>&1; then
      cmd="sudo apt-get update && sudo apt-get install -y $pkgs"
    else
      cmd="apt-get install -y $pkgs"
    fi
    echo "  Install with apt (Debian/Ubuntu/WSL):" >&2
    echo "    $cmd" >&2
    ;;
  *)
    echo "  No supported package manager found (Homebrew or apt-get)." >&2
    echo "  Install these tools manually, then re-run make: $missing" >&2
    ;;
esac
exit 1
