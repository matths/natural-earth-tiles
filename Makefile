# natural-earth-tiles - module build dispatcher
#
# Each module is its own self-contained makefile under make/ and runs as its
# own make process (so module variables and clean semantics never collide):
#   make/vector.mk        vector tiles -> ./tiles/    (Natural Earth countries)
#   make/raster.mk        raster tiles -> ./raster/   (Natural Earth II PNG)
#
# Usage:
#   make                        show this help (default goal)
#   make vector|raster          build one module with its defaults
#   make all                    build vector + raster
#   make check                  check the tools every module needs
#   make <module>-clean|-prune|-check   module maintenance
#   make help                   this message
#
# Module variables pass through to the module makefile, e.g.
#   make vector METHOD=direct MAX_ZOOM=6 OUT_DIR=/tmp/tiles
#   make raster RASTER_MAX_ZOOM=4
#
# A module is also runnable directly: make -f make/vector.mk
# Full docs: README.md

SHELL := /bin/bash
ROOT  := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))

.PHONY: help all check
.DEFAULT_GOAL := help

help:
	@echo 'natural-earth-tiles - build the vector and raster tile modules'
	@echo ''
	@echo 'Modules (each is make/<module>.mk):'
	@echo '  vector        vector tiles  -> ./tiles/    (Natural Earth countries, MVT z0-8)'
	@echo '  raster        raster tiles  -> ./raster/   (Natural Earth II shaded relief, PNG z0-6)'
	@echo ''
	@echo 'Usage:'
	@echo '  make vector|raster            build one module (its defaults)'
	@echo '  make all                      build vector + raster'
	@echo '  make check                    check the tools every module needs'
	@echo '  make <module>-clean|-prune|-check module maintenance'
	@echo '    e.g. make vector-clean, make vector-prune, make raster-clean'
	@echo '  make help                     this message'
	@echo ''
	@echo 'Pass module variables through, e.g.:'
	@echo '  make vector METHOD=direct MAX_ZOOM=6 OUT_DIR=/tmp/tiles'
	@echo '  make raster RASTER_MAX_ZOOM=4'
	@echo ''
	@echo 'A module is also runnable directly: make -f make/vector.mk'

# --- aggregates ------------------------------------------------------------
all: vector raster

check: vector-check raster-check

# --- vector -----------------------------------------------------------------
.PHONY: vector vector-clean vector-prune vector-check
vector:        ; $(MAKE) -C $(ROOT) -f make/vector.mk
vector-clean:  ; $(MAKE) -C $(ROOT) -f make/vector.mk clean
vector-prune:  ; $(MAKE) -C $(ROOT) -f make/vector.mk prune
vector-check:  ; $(MAKE) -C $(ROOT) -f make/vector.mk check

# --- raster -----------------------------------------------------------------
.PHONY: raster raster-clean raster-check
raster:        ; $(MAKE) -C $(ROOT) -f make/raster.mk
raster-clean:  ; $(MAKE) -C $(ROOT) -f make/raster.mk clean
raster-check:  ; $(MAKE) -C $(ROOT) -f make/raster.mk check
