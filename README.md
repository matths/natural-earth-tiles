# natural-earth-tiles

Builds the deployable assets of a MapLibre map served from GitHub Pages:

| module                          | command            | output                              | source                                        |
| ------------------------------- | ------------------ | ----------------------------------- | --------------------------------------------- |
| **vector** (MVT tiles)          | `make vector`      | `./tiles/` `{z}/{x}/{y}.pbf` z0-8   | Natural Earth 1:10m admin-0 countries + physical ocean |
| **raster** (PNG tiles)          | `make raster`      | `./raster/` `{z}/{x}/{y}.png` z0-6  | Natural Earth II 1:10m LR shaded relief        |
| **maplibre-gl** (vendored JS)   | `make maplibre-gl` | `js/` + `css/`                      | the `maplibre-gl` npm package (see package.json) |
| **font** (webfonts)             | `make font`        | `./font/` `faces/*.woff2` + `font-faces.json` | Google Fonts Noto subsets (woff2)  |
| **app** (Svelte front-end)      | `make app`         | `./main.js` (Vite bundle)           | `src/` (Svelte 5 + TypeScript)                |
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
make app         # Svelte 5 app -> ./main.js (Vite bundle)
make country-sizes # country label sizes -> ./country-sizes.json
make all         # all modules, in order
make check       # check the tools every module needs
make clean       # remove every generated file (rebuild it all with `make all`)
make prune       # remove only the build caches, keep the built output
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
| everything build / clean / prune | `make all` · `make clean` · `make prune` |
| vector build / clean / prune / check | `make vector` · `make vector-clean` · `make vector-prune` · `make vector-check` |
| raster build / clean / prune / check | `make raster` · `make raster-clean` · `make raster-prune` · `make raster-check` |
| maplibre-gl build / clean / prune / check | `make maplibre-gl` · `make maplibre-gl-clean` · `make maplibre-gl-prune` · `make maplibre-gl-check` |
| font build / clean / prune / check   | `make font` · `make font-clean` · `make font-prune` · `make font-check` |
| app build / clean / prune / check    | `make app` · `make app-clean` · `make app-prune` · `make app-check` |
| country-sizes build / clean / check  | `make country-sizes` · `make country-sizes-clean` · `make country-sizes-check` |

`*-clean` removes a module's published output **and** its build cache; `*-prune` removes
only the cache, so `./tiles/`, `./raster/`, `./font/`, `js/`, `css/`, `./main.js` stay in
place and the next build only has to re-download the sources. `country-sizes` has no cache
of its own (its input is the vector module's `countries.geojson`), so it only has `clean`.

`make clean` and `make prune` do that for **every** module at once. The hand-written
files (`index.html`, `style.json`, `styles.css`, `src/`, `Makefile`, `README.md`, …) are
never touched, so `make clean && make all` rebuilds exactly the committed state - at the
price of re-downloading ~200 MB of Natural Earth data and the Google fonts. Build
variables pass through to the clean/prune targets too, e.g. `make clean OUT_DIR=/tmp/tiles`
cleans that output instead.

## Vector module

Self-hosted vector tiles (`{z}/{x}/{y}.pbf`, Mapbox Vector Tiles, Web Mercator) from
Natural Earth — the `countries` and `ocean` source layers behind `style.json`.

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
| `BASE_URL` | *(empty = relative)*                | prefix written into `tiles.json` |

Both Natural Earth sources land in **one tileset, one layer per source**, so the water
needs no second source in `style.json`:

| layer       | Natural Earth 1:10m                    | used by                     |
| ----------- | -------------------------------------- | --------------------------- |
| `countries` | *Admin 0 – Countries* (cultural)        | fill, lines, hover, labels  |
| `ocean`     | *Ocean* (physical)                      | the `mixed` variation veils the water white |

The ocean covers the whole globe, so every tile of the grid now exists — the published
tileset roughly doubles (167 MB → 356 MB at z8, ~87k files). Building the ocean as a
second, lower-maxzoom source is the cheap alternative if that ever becomes a problem.

All methods write **raw (uncompressed) MVT**, which static hosts like GitHub Pages need
because they serve `.pbf` without `Content-Encoding: gzip`. `direct`/`ogr2ogr` keep
full-precision geometry and are much larger than the tippecanoe methods — best for
comparison or low maxzooms. `direct` tiles a two-layer `.vrt` (`.vector-src/sources.vrt`,
written from the two shapefiles) because ogr2ogr can only name one layer per run. Each
method+zoom builds its own dir under `.vector-src/` (`tiles-<method>-z<zoom>/`), so
switching methods or zooms never serves stale tiles.

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
`style.json` already consumes the output as its `ne2_shaded` raster source:

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

## App module (Svelte)

The front-end is a **Svelte 5 + TypeScript** app in [`src/`](./src/), bundled by
[Vite](https://vite.dev) into a single **`./main.js`** in the repo root - the file
`index.html` loads. GitHub Pages serves the repo root, so the bundle is committed
like the tiles and fonts; `dist/` is just a gitignored build directory.

The committed documents are used **as they are**: MapLibre loads `style.json` (and the
`tiles/tiles.json` manifest it points at) itself, the generated `font/font-faces.json` is
registered with `map.setFontFaces()` (the style's `text-font` therefore stays the
regular stack), and the label dropdown reads `vector_layers` from `tiles.json`. The only glue is the `transformRequest` hook in `src/lib/resolve-tile-request.ts`: MapLibre
fetches the manifest on the main thread, but requests the individual tiles from its worker
script, so a relative `1/1/0.pbf` would resolve next to `js/maplibre-gl-worker.mjs` -
the hook resolves tile requests against the URL of the document that declares their
template instead: the vector tiles against the `tiles/tiles.json` manifest, the raster
tiles (`raster/{z}/{x}/{y}.png`) against `style.json` itself. Neither file is rewritten.

```sh
npm run dev            # Vite dev server + HMR on http://127.0.0.1:8080
npm run app:watch      # rebuild ./main.js on every change
make app               # npm install + vite build -> ./main.js
make app-clean         # remove ./dist and the built ./main.js
npm run check          # svelte-check (TypeScript + Svelte diagnostics)
```

`npm run dev` serves the **whole repository**, because the repo root *is* the site:
`index.html`, `styles.css`, `style.json`, `tiles/`, `raster/`, `font/`, `js/` and
`country-sizes.json` are all read straight from disk with HMR for `src/`. One server,
no tile regeneration, no second terminal - and since the tile template in `tiles.json`
is relative, the port doesn't matter.

`index.html` always loads `/main.js`. During dev `vite.config.ts` aliases that
request to `src/main.ts`, so there is no second dev HTML to keep in sync. The dev
server is pinned to `127.0.0.1:8080` (`server` in `vite.config.ts`) for predictability;
an explicit IP avoids the macOS pitfall where `localhost` binds IPv6-only and
`127.0.0.1:<port>` then refuses connections.

MapLibre is **not** bundled: the `maplibre-gl` specifier is aliased to the vendored
`js/maplibre-gl.mjs` in dev and kept external for the build (rollup `output.paths`
emits `./js/maplibre-gl.mjs`), so `make maplibre-gl` stays the one MapLibre build.

`src/main.ts` mounts `src/App.svelte`; `src/lib/` holds the plain modules (style
constants and tile requests, map creation, labels, languages, font faces, hover, the
style variations) and `src/components/` the presentational pieces. Requires `node` + `npm`
(`make app-check`).

The style switcher (the ❏ button) offers three variations — **vector tiles**, **raster
tiles** and **mixed** — and "transitions" between them: it only writes paint (and layout)
properties, so MapLibre animates the change with the `transition` duration from
`style.json` instead of swapping styles.

### Tweaking the variations

The variations are **part of `style.json`**, not of the app — `metadata.styleVariants`
is the single place to edit:

```json
"metadata": {
  "styleVariants": {
    "default": "vector",
    "variants": [
      { "id": "vector", "label": "Vector tiles", "hint": "Countries drawn from the MVT tiles" },
      {
        "id": "mixed",
        "label": "Mixed",
        "hint": "Grey relief shining through the vector fill",
        "layers": {
          "countries-fill": { "paint": { "fill-opacity": 0.6 } },
          "ne2-shaded": { "paint": { "raster-opacity": 1, "raster-saturation": -1 } }
        }
      }
    ]
  }
}
```

`id` is what the picker reports, `label`/`hint` are the flyout texts, and `layers` maps
**layer id → `paint`/`layout` overrides**, using the ordinary style-spec property names
(`fill-opacity`, `raster-saturation`, `text-size`, `visibility`, …). A variant without
`layers` is simply the style as declared; anything a variant does not override keeps the
value from the layer's own `paint`/`layout` — that declared value is read once at startup
and reapplied, so switching back always restores it (even expressions such as the hover
highlight).

To experiment, just edit `style.json` and reload the page — the style document is served
as-is, so **no rebuild is needed** (that is only required for `src/` changes, via
`make app`). With `npm run dev` the map is also exposed as `window.__map`, so a value can
be poked live and copied into `metadata.styleVariants` once it looks right:

```js
__map.setPaintProperty('ne2-shaded', 'raster-saturation', -0.5)
```

A variant may name any layer of the style; an unknown layer or a property that
`style.json` does not declare is reported as a console warning instead of failing.

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

`tiles.json` writes the tile template **relative** (`{z}/{x}/{y}.pbf`) and the manifest
sits next to the tiles it points at. `style.json` references it by relative `url`, so the
same committed pair works on GitHub Pages (repo root) **and** behind a local dev server on
any port - no repointing, no localhost URL to accidentally commit. Regenerating it is
instant (it reads `metadata.json` only, no tile rebuild):

```sh
make vector                                  # rewrites ./tiles/tiles.json (rsync + manifest)
python3 scripts/create_tiles_json.py --out=tiles/tiles.json   # manifest only, ~1s
```

Only override it when the tiles are served from a different origin (CDN):

```sh
make vector BASE_URL=https://cdn.example.com/tiles/
```

## Layout

```
Makefile                  module dispatcher: help, all, <module>[-clean|-prune|-check]
make/
  vector.mk               vector module (build + publish)
  raster.mk               raster module
  maplibre-gl.mk          maplibre-gl module
  font.mk                 Noto webfont module
  app.mk                  Svelte app module (Vite bundle -> ./main.js)
  country-sizes.mk        country label-size module
src/                      Svelte 5 + TypeScript sources (app entry: src/main.ts)
vite.config.ts            Vite config (single main.js bundle, maplibre external)
svelte.config.js          Svelte compiler options (vitePreprocess)
tsconfig.json             TypeScript settings for src/ + config files
scripts/                  shared helpers (check-deps, raster-prep, font-build.mjs, create_country_sizes.mjs, ...)
.vector-src/              vector cache (gitignored)
.raster-src/              raster cache (gitignored)
.font-src/                font download cache (gitignored)
tiles/                    vector tiles output (committed)
raster/                   raster tiles output (committed)
js/ css/                  maplibre-gl dist (committed)
font/                     Noto woff2 faces + font-faces.json (committed)
main.js                   Svelte app bundle (generated by `make app`, committed)
dist/                     app build output before publishing (gitignored)
country-sizes.json        country label sizes (committed)
package.json              dev toolchain: maplibre-gl, svelte, vite, typescript
```
