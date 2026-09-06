# make/country-sizes.mk - country label-size module (runs as its own make process)
#
# Produces ./country-sizes.json: for every country (ADM0_A3) a "size" text-size
# multiplier (from the bbox diagonal of its MAIN landmass), read by
# main.js/style.json. Input is the vector module's countries.geojson
# (.vector-src/), which this module builds on demand via `make vector`'s
# geojson step - no tiles needed.
#
#   make country-sizes          regenerate -> ./country-sizes.json
#   make country-sizes-clean    remove ./country-sizes.json
#   make country-sizes-check    verify node
#
# Requires: node (vector's geojson step needs curl/unzip/ogr2ogr if not cached).
# Engine: scripts/create_country_sizes.mjs.

SHELL := /bin/bash
ROOT  := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)

GEOJSON := $(ROOT)/.vector-src/countries.geojson
# where the generated JSON goes - commit this file (read by main.js)
OUT ?= $(ROOT)/country-sizes.json

.PHONY: country-sizes clean check
.DEFAULT_GOAL := country-sizes

country-sizes: check
	@$(MAKE) -C $(ROOT) -f make/vector.mk geojson
	@node $(ROOT)/scripts/create_country_sizes.mjs "$(GEOJSON)" "$(OUT)"

clean:
	@echo ">> country-sizes-clean: removing $(OUT)"
	@rm -f "$(OUT)"

check:
	@$(ROOT)/scripts/check-deps.sh country-sizes
