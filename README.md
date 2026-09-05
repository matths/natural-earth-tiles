# natural-earth-tiles

Builds a self-hosted **vector tile pyramid** (Mapbox Vector Tiles, `.pbf`) from the
[Natural Earth](https://www.naturalearthdata.com/) 1:10m admin-0 countries dataset —
the `countries` source layer behind a MapLibre `style.json`, served from `./tiles/`.

The build is driven by a [`Makefile`](./Makefile); helpers live in [`scripts/`](./scripts/).
Everything is incremental: the heavy steps (download, unzip, shp→GeoJSON,
tippecanoe→`.mbtiles`, tile extraction) only re-run when their inputs change, cached
under the gitignored `.vector-src/`.

## Prerequisites

`make`, `bash`, plus `curl unzip python3 rsync`. Then, per pipeline method:
`ogr2ogr` (GDAL) and `tippecanoe` (which also ships `tile-join`); `sqlite3`; the
`mb-util` method additionally clones [`mapbox/mbutil`](https://github.com/mapbox/mbutil).

Check what's missing for the default method and get the exact install command:

```sh
make check
```

Installers are auto-detected: **Homebrew on macOS**, **`apt-get` on Debian/Ubuntu**
(including **WSL**). `make check` prints, e.g.:

```sh
# macOS
brew install gdal tippecanoe
# Debian / Ubuntu / WSL
sudo apt-get update && sudo apt-get install -y gdal-bin tippecanoe
```

## Quick start

```sh
make                 # tile-join pipeline, zoom 0–8, publishes to ./tiles/
make method=direct   # ogr2ogr shp -> MVT directly (no tippecanoe)
make method=mb-util  # extract with mbutil (gzip blobs auto-decompressed)
make method=ogr2ogr  # ogr2ogr -f MVT from the .mbtiles
make maxzoom=6       # lower top zoom
```

Defaults are `method=tile-join`, `maxzoom=8`, published to `./tiles/`. Run `make help`
for the full list.

## Methods

| method      | pipeline                                              | writes       |
| ----------- | ----------------------------------------------------- | ------------ |
| `direct`    | `shp` → MVT via `ogr2ogr -f MVT` (no tippecanoe)      | raw MVT      |
| `tile-join` | `shp` → GeoJSON → `.mbtiles` → `tile-join`            | raw MVT      |
| `ogr2ogr`   | `shp` → GeoJSON → `.mbtiles` → `ogr2ogr -f MVT`       | raw MVT      |
| `mb-util`   | `shp` → GeoJSON → `.mbtiles` → `mbutil` → decompress  | raw MVT\*    |

\* mbutil copies gzip blobs out verbatim, so that method needs (and runs) an extra
decompress step; the others write raw MVT directly. Raw (uncompressed) MVT is required
because static hosts like GitHub Pages serve `.pbf` **without** `Content-Encoding: gzip`.

`direct`/`ogr2ogr` tiles keep full-precision geometry (no per-zoom simplification) and are
much larger than the tippecanoe methods — best for comparison or low maxzooms. The three
`.mbtiles` methods share the same GeoJSON + `.mbtiles` build cache.

## Options

Passed as `make VAR=value` (or as environment variables):

| variable    | default                              | meaning                             |
| ----------- | ------------------------------------ | ----------------------------------- |
| `method`    | `tile-join`                          | `direct` \| `tile-join` \| `mb-util` \| `ogr2ogr` |
| `maxzoom`   | `8`                                  | top zoom of the pyramid             |
| `OUT_DIR`   | `<repo>/tiles`                       | where finished tiles are published  |
| `BASE_URL`  | `https://matths.github.io/natural-earth-tiles/tiles/` | prefix written into `tiles.json` |

Each method+zoom combination extracts into its own dir under `.vector-src/`
(`tiles-<method>-z<zoom>/`), so switching methods or zooms never serves stale tiles; the
`publish` step syncs the current one into `OUT_DIR`.

## Maintenance

```sh
make help    # list targets and current settings
make check   # verify installed tools for the chosen method
make prune   # remove only the .vector-src/ build cache (keeps ./tiles/)
make clean   # remove the .vector-src/ build cache AND the published OUT_DIR
```

To force a fresh source download, delete `.vector-src/` first.

## Layout

```
Makefile                      target graph + publish/clean (entry point)
scripts/
  check-deps.sh               platform-aware tool check (brew / apt-get)
  extract-mb-util.sh          mbutil clone + extract + gzip-decompress
  summary.sh                  post-publish summary + hints
  create_tiles_json.py        writes tiles.json from metadata (+ .mbtiles)
.vector-src/                  downloads + intermediates (gitignored, throwaway)
tiles/                        {z}/{x}/{y}.pbf + metadata.json + tiles.json (dist)
```

## Serving

`tiles.json` defaults to this repo's GitHub Pages path
(`https://matths.github.io/natural-earth-tiles/tiles/`). For local development,
repoint it without rebuilding tiles (publish re-writes `tiles.json` every run):

```sh
make BASE_URL=http://127.0.0.1:8080/tiles/   # local dev server
```

`make clean` and then commit the regenerated `./tiles/`.
