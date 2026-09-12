# natural-earth-tiles

Builds the deployable assets of a MapLibre map served from GitHub Pages:

| module                          | command            | output                              | source                                        |
| ------------------------------- | ------------------ | ----------------------------------- | --------------------------------------------- |
| **vector** (MVT tiles)          | `make vector`      | `./tiles/` `{z}/{x}/{y}.pbf` z0-8   | Natural Earth 1:10m admin-0 countries         |
| **raster** (PNG tiles)          | `make raster`      | `./raster/` `{z}/{x}/{y}.png` z0-6  | Natural Earth II 1:10m LR shaded relief        |
| **maplibre-gl** (vendored JS)   | `make maplibre-gl` | `js/` + `css/`                      | the `maplibre-gl` npm package (see package.json) |
| **font** (webfonts)             | `make font`        | `./font/` `faces/*.woff2` + `font-faces.json` | Google Fonts Noto subsets (woff2)  |
| **country-sizes** (label sizes) | `make country-sizes` | `./country-sizes.json`           | vector module's `countries.geojson`           |

The root [`Makefile`](./Makefile) is a small **dispatcher**; each module is its own
self-contained makefile under [`make/`](./make/), run as its own make process so module
variables and clean semantics never collide. Builds are incremental and cached under the
gitignored `.vector-src/`, `.raster-src/`, `.font-src/` (`node_modules/` too).

## Quick start

```sh
make             # help (default goal)
make vector      # vector tiles -> ./tiles/
make raster      # raster tiles -> ./raster/
make maplibre-gl # maplibre-gl dist -> js/ + css/
make font        # Noto woff2 font faces -> ./font/
make country-sizes # country label sizes -> ./country-sizes.json
make all         # all modules, in order
make check       # check the tools every module needs
```

`make` with no target always prints help; pick a module from there. A module is also
runnable directly, e.g. `make -f make/vector.mk`.

Module variables pass straight through the dispatcher to the module makefile, e.g.:

```sh
make vector METHOD=direct MAX_ZOOM=6 OUT_DIR=/tmp/tiles
make raster RASTER_MAX_ZOOM=4
```

## Maintenance

| action                | command                |
| --------------------- | ---------------------- |
| help / check          | `make help` · `make check` |
| vector build / clean / prune / check | `make vector` · `make vector-clean` · `make vector-prune` · `make vector-check` |
| raster build / clean / check        | `make raster` · `make raster-clean` · `make raster-check` |
| maplibre-gl build / clean / check   | `make maplibre-gl` · `make maplibre-gl-clean` · `make maplibre-gl-check` |
| font build / clean / check          | `make font` · `make font-clean` · `make font-check` |
| country-sizes build / clean / check | `make country-sizes` · `make country-sizes-clean` · `make country-sizes-check` |

`vector-prune` removes only the vector build cache (keeps `./tiles/`); `vector-clean`
also removes the published `./tiles/`. `raster-clean` removes `./raster/` + its cache.
`maplibre-gl-clean` removes `js/`, `css/` and `node_modules/`. `font-clean` removes
`./font/` plus the `.font-src/` cache.
`country-sizes-clean` removes `./country-sizes.json`.

## Vector module

Self-hosted vector tiles (`{z}/{x}/{y}.pbf`, Mapbox Vector Tiles, Web Mercator) from
Natural Earth countries — the `countries` source layer behind `style.json`.

```sh
make vector                          # tile-join, z0-8 -> ./tiles/
make vector METHOD=direct            # ogr2ogr shp -> MVT directly (no tippecanoe)
make vector METHOD=mb-util           # extract with mbutil (gzip blobs auto-decompressed)
make vector METHOD=ogr2ogr           # ogr2ogr -f MVT from the .mbtiles
make vector MAX_ZOOM=6               # lower top zoom
```

| variable   | default                                  | meaning                          |
| ---------- | ---------------------------------------- | -------------------------------- |
| `METHOD`   | `tile-join`                              | `direct` \| `tile-join` \| `mb-util` \| `ogr2ogr` |
| `MAX_ZOOM` | `8`                                      | top zoom of the pyramid          |
| `OUT_DIR`  | `<repo>/tiles`                           | where tiles are published        |
| `BASE_URL` | `https://matths.github.io/natural-earth-tiles/tiles/` | prefix written into `tiles.json` |

All methods write **raw (uncompressed) MVT**, which static hosts like GitHub Pages need
because they serve `.pbf` without `Content-Encoding: gzip`. `direct`/`ogr2ogr` keep
full-precision geometry and are much larger than the tippecanoe methods — best for
comparison or low maxzooms. Each method+zoom builds its own dir under `.vector-src/`
(`tiles-<method>-z<zoom>/`), so switching methods or zooms never serves stale tiles.

## Raster module

Self-hosted raster tiles (`{z}/{x}/{y}.png`, Web Mercator, 256px) from the Natural
Earth II 1:10m **LR** raster (shaded relief + water + drainages) — the look of
OpenFreeMap's `ne2_shaded`.

```sh
make raster               # z0-6 -> ./raster/
make raster RASTER_MAX_ZOOM=4
```

| variable          | default            | meaning                       |
| ----------------- | ------------------ | ----------------------------- |
| `RASTER_MAX_ZOOM` | `6`                | top zoom (LR is native to ~z6) |
| `RASTER_OUT`      | `<repo>/raster`    | where PNG tiles are written    |

Requires GDAL (`gdal2tiles.py`, `gdalinfo`, `gdal_translate`) — see `make raster-check`.
Use the output in `style.json` as a raster source:

```json
"ne2_shaded": {
  "type": "raster",
  "tiles": ["raster/{z}/{x}/{y}.png"],
  "tileSize": 256,
  "maxzoom": 6
}
```

## maplibre-gl module

Installs the `maplibre-gl` npm package (the version pinned in `package.json`) and copies
its ESM dist — `maplibre-gl.mjs` (+ source maps), `maplibre-gl-worker.mjs` and
`maplibre-gl.css` — into `js/` and `css/` for static hosting.

```sh
make maplibre-gl
```

To bump MapLibre: `npm install maplibre-gl@latest --save-dev`, then
`make maplibre-gl-clean && make maplibre-gl`. Requires `node`/`npm` (`make maplibre-gl-check`).

## Font module

Noto **webfonts** - `./font/faces/*.woff2` plus the generated `./font/font-faces.json`
- downloaded from Google Fonts. `main.js` merges `font-faces.json` into the style's
`font-faces` property, which tells MapLibre which font file to use for each character
based on that file's `unicode-range`. One `text-font` name therefore covers Latin,
Greek, Cyrillic, Devanagari, Arabic, Hebrew and Bengali at once - no per-language font
choice and no per-script font stack.

```sh
make font                 # download/refresh faces + write font-faces.json
make font FONT_DIR=/tmp/font
make font-clean           # remove ./font/ and the .font-src/ cache
```

Requires `curl` and `node` (`make font-check`). Google's CSS responses are cached in the
gitignored `.font-src/`; woff2 files that already exist are not re-downloaded.

**Why not glyph PBFs?** A glyph stack is a *single* font, and MapLibre cannot fall back
to another stack for characters it cannot draw (the `glyphs` URL contains one
comma-joined `{fontstack}` path segment, which 404s on static hosts). `font-faces` gives
real per-character fallback; the price is that the client downloads only the subsets the
visible labels need (~0.6 MB for the whole set, fetched lazily per script).

CJK/Hangul are intentionally **not** bundled (they are very large); MapLibre draws
ideographs locally using the map's `localIdeographFontFamily` (default `sans-serif`).

## country-sizes module

Writes `./country-sizes.json`: for every country (`ADM0_A3`) a `size` text-size
multiplier derived from the bbox diagonal of the country's **main** landmass (engine:
`scripts/create_country_sizes.mjs`). `main.js`/`style.json` read it to scale country
label sizes.

```sh
make country-sizes            # from the vector geojson -> ./country-sizes.json
make country-sizes-clean      # remove ./country-sizes.json
```

Input is the vector module's `countries.geojson` (`.vector-src/`); this module runs
only `make vector`'s `geojson` step, so no tiles are built. Requires `node`
(`make country-sizes-check`).

## Serving

Commit the module outputs to the GitHub Pages branch: `./tiles/`, `./raster/`, `js/`,
`css/`, `./font/`, `./country-sizes.json` (caches `.vector-src/`, `.raster-src/`,
`.font-src/`, `node_modules/` are gitignored).

`tiles.json` defaults to the repo's GitHub Pages path
(`https://matths.github.io/natural-earth-tiles/tiles/`). For local development, repoint
it without rebuilding (publish re-writes `tiles.json` every run):

```sh
make vector BASE_URL=http://127.0.0.1:8080/tiles/   # local dev server
```

## Layout

```
Makefile                  module dispatcher: help, all, <module>[-clean|-prune|-check]
make/
  vector.mk               vector module (build + publish)
  raster.mk               raster module
  maplibre-gl.mk          maplibre-gl module
  font.mk                 Noto webfont module
  country-sizes.mk        country label-size module
scripts/                  shared helpers (check-deps, raster-prep, font-build.mjs, create_country_sizes.mjs, ...)
.vector-src/              vector cache (gitignored)
.raster-src/              raster cache (gitignored)
.font-src/                font download cache (gitignored)
tiles/                    vector tiles output (committed)
raster/                   raster tiles output (committed)
js/ css/                  maplibre-gl dist (committed)
font/                     Noto woff2 faces + font-faces.json (committed)
country-sizes.json        country label sizes (committed)
package.json              maplibre-gl npm dependency
```
