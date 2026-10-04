# make/raster.mk - raster tile module (runs as its own make process)
#
# Builds a self-hosted raster pyramid ({z}/{x}/{y}.png, Web Mercator, 256px)
# from the Natural Earth II 1:10m LR raster ("Shaded Relief + Water +
# Drainages") - the same look as OpenFreeMap's ne2_shaded:
#   https://tiles.openfreemap.org/natural_earth/ne2sr/{z}/{x}/{y}.png
#
#   make raster          build (default RASTER_MAX_ZOOM=6) -> ./raster/
#   make raster-clean    remove ./raster/ + .raster-src/ build cache
#   make raster-check    verify the GDAL tools are installed
#
# LR is native up to ~z6 (z7 is a mild upscale), so 6 is the natural cap;
# higher zooms multiply tile count/size quickly.
# Requires: curl unzip + GDAL (gdal2tiles.py, gdalinfo, gdal_translate).

SHELL := /bin/bash
ROOT  := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)

# downloads + intermediates (gitignored)
RASTER_WORK := $(ROOT)/.raster-src
RASTER_RAW  := $(RASTER_WORK)/raw
# prepared, georeferenced input
RASTER_SRC  := $(RASTER_WORK)/source.tif
# tile output - commit this folder
RASTER_OUT  ?= $(ROOT)/raster
RASTER_MIN  := 0
RASTER_MAX_ZOOM ?= 6

ZIP_URL := https://naciscdn.org/naturalearth/10m/raster/NE2_LR_LC_SR_W_DR.zip
ZIP     := $(RASTER_WORK)/NE2_LR_LC_SR_W_DR.zip
UNZIP   := $(RASTER_WORK)/.unzipped
STAMP   := $(RASTER_WORK)/.tiled-$(RASTER_MAX_ZOOM)

# bare `make -f make/raster.mk` (as the dispatcher does) builds the module
.DEFAULT_GOAL := raster

# --- 1. download -----------------------------------------------------------
$(ZIP): | check
	@mkdir -p $(RASTER_WORK)
	@echo ">> Downloading $(notdir $(ZIP)) ..."
	@curl -fL $(ZIP_URL) -o $@

# --- 2. unzip (touch so a re-download re-triggers extraction) ---------------
$(UNZIP): $(ZIP)
	@echo ">> Unzipping into $(RASTER_RAW) ..."
	@rm -rf $(RASTER_RAW)
	@mkdir -p $(RASTER_RAW)
	@unzip -o -q $(ZIP) -d $(RASTER_RAW)
	@touch $@

# --- 3. prepare: locate the largest image + guarantee georeferencing ---------
$(RASTER_SRC): $(UNZIP)
	@echo ">> Preparing georeferenced source $(notdir $@)"
	@$(ROOT)/scripts/raster-prep.sh "$(RASTER_RAW)" "$@"

# --- 4. cut tiles with gdal2tiles --------------------------------------------
# gdal2tiles creates $(RASTER_OUT) itself, so it must not exist beforehand.
$(STAMP): $(RASTER_SRC) | check
	@echo ">> Tiling (Web Mercator, z$(RASTER_MIN)-$(RASTER_MAX_ZOOM), 256px) -> $(RASTER_OUT)"
	@rm -rf $(RASTER_OUT)
	@gdal2tiles.py -p mercator -z $(RASTER_MIN)-$(RASTER_MAX_ZOOM) -w none --xyz -s EPSG:4326 $(RASTER_SRC) $(RASTER_OUT)
	@touch $@

# --- public targets ----------------------------------------------------------
.PHONY: raster clean prune check
raster: $(STAMP)
	@n=$$(find "$(RASTER_OUT)" -name '*.png' | wc -l | tr -d ' '); \
	echo; \
	echo "Done: $$n raster tiles -> $(RASTER_OUT) (z$(RASTER_MIN)-$(RASTER_MAX_ZOOM))"; \
	echo 'Use in style.json as a raster source, e.g.'; \
	echo '  "ne2_shaded": { "type": "raster", "tiles": ["raster/{z}/{x}/{y}.png"], "tileSize": 256, "maxzoom": $(RASTER_MAX_ZOOM) }'

clean:
	@echo ">> raster-clean: removing $(RASTER_OUT) and build cache $(RASTER_WORK)"
	@rm -rf $(RASTER_OUT) $(RASTER_WORK)

prune:
	@echo ">> raster-prune: removing build cache $(RASTER_WORK)"
	@rm -rf $(RASTER_WORK)

check:
	@$(ROOT)/scripts/check-deps.sh raster
