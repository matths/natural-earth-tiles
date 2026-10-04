# natural-earth-tiles - module build dispatcher
#
# Each module is its own self-contained makefile under make/ and runs as its
# own make process (so module variables and clean semantics never collide):
#   make/vector.mk          vector tiles -> ./tiles/    (Natural Earth countries)
#   make/raster.mk          raster tiles -> ./raster/   (Natural Earth II PNG)
#   make/maplibre-gl.mk     maplibre-gl npm dist -> js/ + css/
#   make/font.mk            Noto woff2 font faces -> ./font/  (MapLibre font-faces source)
#   make/app.mk             Svelte 5 app -> ./main.js (Vite bundle)
#   make/country-sizes.mk   label sizes -> ./country-sizes.json (from vector data)
#
# Usage:
#   make                        show this help (default goal)
#   make <module>               build one module with its defaults
#   make all                    build every module
#   make check                  check the tools every module needs
#   make clean                  remove every generated file (published output + caches)
#   make prune                  remove only the re-downloadable caches (keep the output)
#   make <module>-clean|-prune|-check   module maintenance
#   make help                   this message
#
# Module variables pass through to the module makefile, e.g.
#   make vector METHOD=direct MAX_ZOOM=6 OUT_DIR=/tmp/tiles
#   make vector BASE_URL=http://127.0.0.1:8080/tiles/   (tiles.json URL; local dev)
#   make raster RASTER_MAX_ZOOM=4
#   make maplibre-gl            (honours the maplibre-gl version in package.json)
#   make font FONT_DIR=/tmp/font
#
# A module is also runnable directly: make -f make/vector.mk
# Full docs: README.md

SHELL := /bin/bash
ROOT  := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))

.PHONY: help all clean prune check
.DEFAULT_GOAL := help

help:
	@echo 'natural-earth-tiles - build deployable modules'
	@echo ''
	@echo 'Modules (each is make/<module>.mk):'
	@echo '  vector          vector tiles  -> ./tiles/    (Natural Earth countries, MVT z0-8)'
	@echo '  raster          raster tiles  -> ./raster/   (Natural Earth II shaded relief, PNG z0-6)'
	@echo '  maplibre-gl     npm dist of maplibre-gl copied to js/ + css/'
	@echo '  font            Noto woff2 font faces -> ./font/  (glyph source for labels)'
	@echo '  app             Svelte 5 app -> ./main.js   (Vite bundle loaded by index.html)'
	@echo '  country-sizes   country label sizes -> ./country-sizes.json'
	@echo ''
	@echo 'Usage:'
	@echo '  make <module>                   build one module (its defaults)'
	@echo '  make all                        build vector + raster + maplibre-gl + font + country-sizes'
	@echo '  make check                      check the tools every module needs'
	@echo '  make clean                      remove published files + caches (all modules)'
	@echo '  make prune                      remove only the build caches (all modules)'
	@echo '  make <module>-clean|-prune|-check module maintenance'
	@echo '    e.g. make vector-clean, make font-clean, make country-sizes-clean'
	@echo '  make help                       this message'
	@echo ''
	@echo 'Pass module variables through, e.g.:'
	@echo '  make vector METHOD=direct MAX_ZOOM=6 OUT_DIR=/tmp/tiles'
	@echo '  make vector BASE_URL=http://127.0.0.1:8080/tiles/   tiles.json URL (default GitHub Pages)'
	@echo '  make raster RASTER_MAX_ZOOM=4'
	@echo '  make maplibre-gl                (honours package.json maplibre-gl version)'
	@echo '  make font FONT_DIR=/tmp/font'
	@echo ''
	@echo 'A module is also runnable directly: make -f make/vector.mk'

# --- aggregates ------------------------------------------------------------
all: vector raster maplibre-gl font country-sizes app

# Everything the modules generate - published output plus build caches. The
# hand-written files (index.html, style.json, styles.css, src/, Makefile,
# README.md, ...) are never touched, so `make clean && make all` rebuilds the
# committed state. Build variables pass through, e.g. `make clean OUT_DIR=/tmp/x`.
clean: vector-clean raster-clean maplibre-gl-clean font-clean country-sizes-clean app-clean

# Only what is re-downloaded or re-derived (sources + node_modules); tiles/,
# raster/, font/, js/, css/, main.js and country-sizes.json stay in place.
# country-sizes has no cache of its own - its input is the vector cache.
prune: vector-prune raster-prune maplibre-gl-prune font-prune app-prune

check: vector-check raster-check maplibre-gl-check font-check country-sizes-check app-check

# --- vector -----------------------------------------------------------------
.PHONY: vector vector-clean vector-prune vector-check
vector:        ; $(MAKE) -C $(ROOT) -f make/vector.mk
vector-clean:  ; $(MAKE) -C $(ROOT) -f make/vector.mk clean
vector-prune:  ; $(MAKE) -C $(ROOT) -f make/vector.mk prune
vector-check:  ; $(MAKE) -C $(ROOT) -f make/vector.mk check

# --- raster -----------------------------------------------------------------
.PHONY: raster raster-clean raster-prune raster-check
raster:        ; $(MAKE) -C $(ROOT) -f make/raster.mk
raster-clean:  ; $(MAKE) -C $(ROOT) -f make/raster.mk clean
raster-prune:  ; $(MAKE) -C $(ROOT) -f make/raster.mk prune
raster-check:  ; $(MAKE) -C $(ROOT) -f make/raster.mk check

# --- maplibre-gl ------------------------------------------------------------
.PHONY: maplibre-gl maplibre-gl-clean maplibre-gl-prune maplibre-gl-check
maplibre-gl:       ; $(MAKE) -C $(ROOT) -f make/maplibre-gl.mk
maplibre-gl-clean: ; $(MAKE) -C $(ROOT) -f make/maplibre-gl.mk clean
maplibre-gl-prune: ; $(MAKE) -C $(ROOT) -f make/maplibre-gl.mk prune
maplibre-gl-check: ; $(MAKE) -C $(ROOT) -f make/maplibre-gl.mk check

# --- font -------------------------------------------------------------------
.PHONY: font font-clean font-prune font-check
font:        ; $(MAKE) -C $(ROOT) -f make/font.mk
font-clean:  ; $(MAKE) -C $(ROOT) -f make/font.mk clean
font-prune:  ; $(MAKE) -C $(ROOT) -f make/font.mk prune
font-check:  ; $(MAKE) -C $(ROOT) -f make/font.mk check

# --- app (Svelte) -----------------------------------------------------------
.PHONY: app app-clean app-prune app-check
app:        ; $(MAKE) -C $(ROOT) -f make/app.mk
app-clean:  ; $(MAKE) -C $(ROOT) -f make/app.mk clean
app-prune:  ; $(MAKE) -C $(ROOT) -f make/app.mk prune
app-check:  ; $(MAKE) -C $(ROOT) -f make/app.mk check

# --- country-sizes ----------------------------------------------------------
.PHONY: country-sizes country-sizes-clean country-sizes-check
country-sizes:        ; $(MAKE) -C $(ROOT) -f make/country-sizes.mk
country-sizes-clean:  ; $(MAKE) -C $(ROOT) -f make/country-sizes.mk clean
country-sizes-check:  ; $(MAKE) -C $(ROOT) -f make/country-sizes.mk check
