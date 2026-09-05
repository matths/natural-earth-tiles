# natural-earth-tiles - vector tile pyramid build
#
# Produces {z}/{x}/{y}.pbf + metadata.json + tiles.json from the Natural Earth
# 1:10m admin-0 countries shapefile into ./tiles/ (the "countries" source layer
# behind style.json). Heavy steps are incremental and cached in .vector-src/.
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
# tiles.json URL prefix
BASE_URL ?= https://matths.github.io/natural-earth-tiles/tiles/

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
# Artifacts
# ---------------------------------------------------------------------------
ZIP_URL := https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip
ZIP     := $(WORK)/ne_10m_admin_0_countries.zip
RAW     := $(WORK)/ne_10m_admin_0_countries
SHP     := $(RAW)/ne_10m_admin_0_countries.shp
GEOJSON := $(WORK)/countries.geojson
MBTILES := $(WORK)/countries-z$(MAX_ZOOM).mbtiles
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
# 1. Download + unzip the Natural Earth source shapefile
# ---------------------------------------------------------------------------
$(ZIP): | check-deps
	@mkdir -p $(WORK)
	@echo ">> Downloading $(notdir $(ZIP)) ..."
	@curl -fL $(ZIP_URL) -o $@

# unzip restores the archive's original (old) mtimes, which would make $(SHP)
# look perpetually older than the freshly downloaded $(ZIP); touch it so the
# expensive shp -> geojson -> mbtiles chain only re-runs when data really changed.
$(SHP): $(ZIP)
	@echo ">> Unzipping into $(RAW) ..."
	@rm -rf $(RAW)
	@mkdir -p $(RAW)
	@unzip -q $(ZIP) -d $(RAW)
	@touch $@
	@echo ">> Source shapefile: $@"

# ---------------------------------------------------------------------------
# 2. shp -> GeoJSON
# ---------------------------------------------------------------------------
$(GEOJSON): $(SHP)
	@echo ">> ogr2ogr shp -> GeoJSON"
	@ogr2ogr -f GeoJSON $@ $(SHP)

# ---------------------------------------------------------------------------
# 3. tippecanoe -> .mbtiles
# ---------------------------------------------------------------------------
$(MBTILES): $(GEOJSON)
	@echo ">> tippecanoe -> $(notdir $@) (z$(MIN_ZOOM)-$(MAX_ZOOM))"
	@tippecanoe -o $@ -z $(MAX_ZOOM) --drop-densest-as-needed --extend-zooms-if-still-dropping $(GEOJSON)

# ---------------------------------------------------------------------------
# 4. Extract {z}/{x}/{y}.pbf with the chosen method. Each method+zoom builds its
#    own $(BUILD) dir (keyed by a stamp file) so switching never serves stale
#    tiles. COMPRESS=NO / --no-tile-compression write raw MVT for static hosts;
#    only mb-util needs the gzip-decompress helper.
# ---------------------------------------------------------------------------
ifeq ($(METHOD),direct)
# ogr2ogr tiles the shapefile straight to MVT; -nln countries keeps the layer
# name style.json expects (GDAL would otherwise use the .shp basename).
$(STAMP): $(SHP) | check-deps
	@echo ">> ogr2ogr (direct) shp -> MVT $(BUILD)  (COMPRESS=NO)"
	@rm -rf $(BUILD)
	@ogr2ogr -f MVT $(BUILD) $(SHP) -nln countries \
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
