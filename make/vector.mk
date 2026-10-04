# natural-earth-tiles - vector tile pyramid build
#
# Produces {z}/{x}/{y}.pbf + metadata.json + tiles.json from the Natural Earth
# 1:10m admin-0 countries (cultural) and ocean (physical) shapefiles into
# ./tiles/ - the "countries" and "ocean" source layers behind style.json, in one
# tileset so the water needs no second source. Heavy steps are incremental and
# cached in .vector-src/.
#
# Targets/settings: `make help`. Docs: README.md. Methods: direct | tile-join |
# mb-util | ogr2ogr (default tile-join, z0-8). Paths are $(ROOT)-anchored, so
# `make` works from any directory.

SHELL := /bin/bash

# Repo root: this file lives in make/, so go up one level.
ROOT    := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)
WORK    := $(ROOT)/.vector-src
SCRIPTS := $(ROOT)/scripts
PYJSON  := $(SCRIPTS)/create_tiles_json.py

# ---------------------------------------------------------------------------
# User knobs (override on the command line or via environment)
# ---------------------------------------------------------------------------
# direct | tile-join | mb-util | ogr2ogr
METHOD   ?= tile-join
# top zoom of the pyramid
MAX_ZOOM ?= 8
MIN_ZOOM := 0
# where the finished tiles are published
OUT_DIR  ?= $(ROOT)/tiles
OUT      := $(abspath $(OUT_DIR))
# tiles.json URL prefix. Empty = a relative template ("{z}/{x}/{y}.pbf"), which
# works both on GitHub Pages and behind any local dev server on any port, since
# MapLibre resolves it against the page URL. Set it only for a CDN, e.g.
# `make vector BASE_URL=https://cdn.example.com/tiles/`.
BASE_URL ?=

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
ifeq ($(filter $(METHOD),direct tile-join mb-util ogr2ogr),)
$(error Unknown METHOD '$(METHOD)'. Choose one of: direct tile-join mb-util ogr2ogr)
endif
ifeq ($(strip $(MAX_ZOOM)),)
$(error MAX_ZOOM is empty - pass e.g. 'make maxzoom=6')
endif
ifneq ($(filter $(WORK)%,$(OUT)),)
$(error OUT_DIR must not point inside the build cache ($(WORK)) - pick a separate output dir)
endif

# ---------------------------------------------------------------------------
# Artifacts: two Natural Earth 1:10m sources -> one two-layer tileset
# ---------------------------------------------------------------------------
# layer names style.json refers to (source "netiles", source-layer ...)
LAYER_COUNTRIES := countries
LAYER_OCEAN     := ocean

ADMIN_URL := https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip
ADMIN_ZIP := $(WORK)/ne_10m_admin_0_countries.zip
ADMIN_RAW := $(WORK)/ne_10m_admin_0_countries
ADMIN_SHP := $(ADMIN_RAW)/ne_10m_admin_0_countries.shp

OCEAN_URL := https://naciscdn.org/naturalearth/10m/physical/ne_10m_ocean.zip
OCEAN_ZIP := $(WORK)/ne_10m_ocean.zip
OCEAN_RAW := $(WORK)/ne_10m_ocean
OCEAN_SHP := $(OCEAN_RAW)/ne_10m_ocean.shp

GEOJSON       := $(WORK)/countries.geojson
OCEAN_GEOJSON := $(WORK)/ocean.geojson
# two-layer VRT: gives 'direct' a single dataset whose layers are already named
# the way style.json expects, instead of ogr2ogr's -nln (one name only).
SOURCES_VRT := $(WORK)/sources.vrt

MBTILES := $(WORK)/natural-earth-z$(MAX_ZOOM).mbtiles
BUILD   := $(WORK)/tiles-$(METHOD)-z$(MAX_ZOOM)
STAMP   := $(WORK)/.stamp-$(METHOD)-z$(MAX_ZOOM)

# create_tiles_json.py needs --mbtiles only for the tippecanoe-based methods;
# 'direct' keeps the vector_layers GDAL embeds in its metadata.json instead.
ifeq ($(METHOD),direct)
MB_ARGS :=
else
MB_ARGS := --mbtiles=$(MBTILES)
endif

# ---------------------------------------------------------------------------
# 1. Download + unzip the Natural Earth source shapefiles
# ---------------------------------------------------------------------------
$(ADMIN_ZIP): | check-deps
	@mkdir -p $(WORK)
	@echo ">> Downloading $(notdir $@) ..."
	@curl -fL $(ADMIN_URL) -o $@

$(OCEAN_ZIP): | check-deps
	@mkdir -p $(WORK)
	@echo ">> Downloading $(notdir $@) ..."
	@curl -fL $(OCEAN_URL) -o $@

# unzip restores the archive's original (old) mtimes, which would make the .shp
# look perpetually older than the freshly downloaded .zip; touch it so the
# expensive shp -> geojson -> mbtiles chain only re-runs when data really changed.
$(ADMIN_SHP): $(ADMIN_ZIP)
	@echo ">> Unzipping into $(ADMIN_RAW) ..."
	@rm -rf $(ADMIN_RAW)
	@mkdir -p $(ADMIN_RAW)
	@unzip -q $(ADMIN_ZIP) -d $(ADMIN_RAW)
	@touch $@
	@echo ">> Source shapefile: $@"

$(OCEAN_SHP): $(OCEAN_ZIP)
	@echo ">> Unzipping into $(OCEAN_RAW) ..."
	@rm -rf $(OCEAN_RAW)
	@mkdir -p $(OCEAN_RAW)
	@unzip -q $(OCEAN_ZIP) -d $(OCEAN_RAW)
	@touch $@
	@echo ">> Source shapefile: $@"

# ---------------------------------------------------------------------------
# 2. shp -> GeoJSON
# ---------------------------------------------------------------------------
$(GEOJSON): $(ADMIN_SHP)
	@echo ">> ogr2ogr shp -> GeoJSON"
	@ogr2ogr -f GeoJSON $@ $(ADMIN_SHP)

$(OCEAN_GEOJSON): $(OCEAN_SHP)
	@echo ">> ogr2ogr shp -> GeoJSON"
	@ogr2ogr -f GeoJSON $@ $(OCEAN_SHP)

# Only the 'direct' method needs this, but writing it is instant and keeps the
# shapefile -> layer-name mapping next to the sources it wraps. SrcLayer is the
# OGR layer name inside a shapefile, i.e. the file's basename.
$(SOURCES_VRT): $(ADMIN_SHP) $(OCEAN_SHP)
	@echo ">> writing $(notdir $@) ($(LAYER_COUNTRIES) + $(LAYER_OCEAN))"
	@printf '%s\n' \
		'<OGRVRTDataSource>' \
		'  <OGRVRTLayer name="$(LAYER_COUNTRIES)">' \
		'    <SrcDataSource relativeToVRT="0">$(ADMIN_SHP)</SrcDataSource>' \
		'    <SrcLayer>$(basename $(notdir $(ADMIN_SHP)))</SrcLayer>' \
		'  </OGRVRTLayer>' \
		'  <OGRVRTLayer name="$(LAYER_OCEAN)">' \
		'    <SrcDataSource relativeToVRT="0">$(OCEAN_SHP)</SrcDataSource>' \
		'    <SrcLayer>$(basename $(notdir $(OCEAN_SHP)))</SrcLayer>' \
		'  </OGRVRTLayer>' \
		'</OGRVRTDataSource>' > $@

# Public: build only the countries GeoJSON (used by the country-sizes module,
# which does not need the tiles).
.PHONY: geojson
geojson: $(GEOJSON)

# ---------------------------------------------------------------------------
# 3. tippecanoe -> .mbtiles (one tileset, one layer per source)
# ---------------------------------------------------------------------------
$(MBTILES): $(GEOJSON) $(OCEAN_GEOJSON)
	@echo ">> tippecanoe -> $(notdir $@) (z$(MIN_ZOOM)-$(MAX_ZOOM): $(LAYER_COUNTRIES) + $(LAYER_OCEAN))"
	@tippecanoe -o $@ -z $(MAX_ZOOM) --drop-densest-as-needed --extend-zooms-if-still-dropping \
		-L $(LAYER_COUNTRIES):$(GEOJSON) -L $(LAYER_OCEAN):$(OCEAN_GEOJSON)

# ---------------------------------------------------------------------------
# 4. Extract {z}/{x}/{y}.pbf with the chosen method. Each method+zoom builds its
#    own $(BUILD) dir (keyed by a stamp file) so switching never serves stale
#    tiles. COMPRESS=NO / --no-tile-compression write raw MVT for static hosts;
#    only mb-util needs the gzip-decompress helper.
# ---------------------------------------------------------------------------
ifeq ($(METHOD),direct)
# ogr2ogr tiles the shapefiles straight to MVT. The two-layer VRT is what gives
# the layers the names style.json expects (GDAL would otherwise use the .shp
# basenames, and -nln can only name a single layer).
$(STAMP): $(SOURCES_VRT) | check-deps
	@echo ">> ogr2ogr (direct) shp -> MVT $(BUILD)  (COMPRESS=NO)"
	@rm -rf $(BUILD)
	@ogr2ogr -f MVT $(BUILD) $(SOURCES_VRT) \
		-dsco MINZOOM=$(MIN_ZOOM) -dsco MAXZOOM=$(MAX_ZOOM) -dsco COMPRESS=NO
	@touch $@

else ifeq ($(METHOD),tile-join)
$(STAMP): $(MBTILES) | check-deps
	@echo ">> tile-join --no-tile-compression -> $(BUILD)"
	@rm -rf $(BUILD)
	@mkdir -p $(BUILD)
	@tile-join --output-to-directory=$(BUILD) --no-tile-compression $(MBTILES)
	@echo ">> rewriting $(BUILD)/metadata.json from .mbtiles"
	@sqlite3 $(MBTILES) "SELECT json_group_object(name, value) FROM metadata;" > $(BUILD)/metadata.json
	@touch $@

else ifeq ($(METHOD),mb-util)
# extract-mb-util.sh handles the mbutil clone + gzip-decompress steps.
$(STAMP): $(MBTILES) | check-deps
	@$(SCRIPTS)/extract-mb-util.sh "$(ROOT)" "$(MBTILES)" "$(BUILD)"
	@echo ">> rewriting $(BUILD)/metadata.json from .mbtiles"
	@sqlite3 $(MBTILES) "SELECT json_group_object(name, value) FROM metadata;" > $(BUILD)/metadata.json
	@touch $@

else ifeq ($(METHOD),ogr2ogr)
# GDAL re-tiles the .mbtiles; the layer name is carried over ("countries").
$(STAMP): $(MBTILES) | check-deps
	@echo ">> ogr2ogr (from .mbtiles) -> MVT $(BUILD)  (COMPRESS=NO)"
	@rm -rf $(BUILD)
	@ogr2ogr -f MVT $(BUILD) $(MBTILES) \
		-dsco MINZOOM=$(MIN_ZOOM) -dsco MAXZOOM=$(MAX_ZOOM) -dsco COMPRESS=NO
	@echo ">> rewriting $(BUILD)/metadata.json from .mbtiles"
	@sqlite3 $(MBTILES) "SELECT json_group_object(name, value) FROM metadata;" > $(BUILD)/metadata.json
	@touch $@
endif

# ---------------------------------------------------------------------------
# 5. Publish (default goal): rsync $(BUILD) -> $(OUT), then write tiles.json.
#    Phony on purpose: always re-syncs (cheap) and re-writes tiles.json, so a
#    changed BASE_URL/OUT_DIR always takes effect.
# ---------------------------------------------------------------------------
.DEFAULT_GOAL := publish

.PHONY: publish
publish: $(STAMP) | check-deps
	@echo ">> Publishing $(BUILD) -> $(OUT)"
	@mkdir -p $(OUT)
	@rsync -a --delete $(BUILD)/ $(OUT)/
	@echo ">> writing $(OUT)/tiles.json"
	@python3 $(PYJSON) --metadata="$(OUT)/metadata.json" --out="$(OUT)/tiles.json" --base-url="$(BASE_URL)" $(MB_ARGS)
	@$(SCRIPTS)/summary.sh "$(OUT)" "$(METHOD)" "$(MIN_ZOOM)" "$(MAX_ZOOM)"

# ---------------------------------------------------------------------------
# Maintenance targets
# ---------------------------------------------------------------------------
.PHONY: check-deps check
check-deps:
	@$(SCRIPTS)/check-deps.sh $(METHOD)

check: check-deps

.PHONY: prune
prune:
	@echo ">> prune: removing build cache $(WORK)"
	@rm -rf $(WORK)

.PHONY: clean
clean:
	@echo ">> clean: removing dist $(OUT)"
	@rm -rf $(OUT)
	@echo ">> clean: removing build cache $(WORK)"
	@rm -rf $(WORK)

.PHONY: help
help:
	@echo 'natural-earth-tiles - build the vector tile pyramid (tiles/)'
	@echo ''
	@echo 'Targets:'
	@echo '  make                build (default method=tile-join, maxzoom=8) and publish to ./tiles/'
	@echo '  make method=NAME    direct | tile-join | mb-util | ogr2ogr'
	@echo '  make maxzoom=N      top zoom of the pyramid (each zoom caches its own .mbtiles)'
	@echo '  make OUT_DIR=PATH   publish somewhere else (default ./tiles)'
	@echo '  make BASE_URL=URL   override the tiles.json URL prefix'
	@echo '  make check          verify installed tools for the chosen method'
	@echo '  make prune          remove only the .vector-src/ build cache'
	@echo '  make clean          remove .vector-src/ build cache + published dist'
	@echo '  make help           show this message'
	@echo ''
	@echo 'Current settings: METHOD=$(METHOD) MAX_ZOOM=$(MAX_ZOOM) OUT_DIR=$(OUT) BASE_URL=$(BASE_URL)'
