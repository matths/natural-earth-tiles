# make/maplibre-gl.mk - maplibre-gl module (runs as its own make process)
#
# Installs the maplibre-gl npm package (version from package.json) and copies
# its ESM dist (mjs + source maps + web worker + css) into js/ and css/ so the
# site can serve it from GitHub Pages, like ./tiles/.
#
#   make maplibre-gl            install (if needed) + copy -> js/ + css/
#   make maplibre-gl-clean      remove js/ css/ and node_modules/
#   make maplibre-gl-check      verify node + npm
#
# The MapLibre version is whatever package.json pins. To fetch a newer one:
#   npm install maplibre-gl@latest --save-dev   # updates package.json
#   make maplibre-gl-clean && make maplibre-gl  # refresh node_modules + js/css

SHELL := /bin/bash
ROOT  := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)

DIST  := $(ROOT)/node_modules/maplibre-gl/dist
FILES := maplibre-gl.mjs maplibre-gl.mjs.map \
         maplibre-gl-shared.mjs maplibre-gl-shared.mjs.map \
         maplibre-gl-worker.mjs maplibre-gl-worker.mjs.map

# bare `make -f make/maplibre-gl.mk` (as the dispatcher does) builds the module
.DEFAULT_GOAL := maplibre-gl

.PHONY: maplibre-gl clean prune check
maplibre-gl: check
	@test -d "$(DIST)" || (cd "$(ROOT)" && npm install)
	@mkdir -p "$(ROOT)/js" "$(ROOT)/css"
	@for f in $(FILES); do cp "$(DIST)/$$f" "$(ROOT)/js/"; done
	@cp "$(DIST)/maplibre-gl.css" "$(ROOT)/css/"
	@v=$$(node -p "require('$(ROOT)/node_modules/maplibre-gl/package.json').version"); \
	echo ">> maplibre-gl $$v dist -> js/ + css/"

clean:
	@echo ">> maplibre-gl-clean: removing js/ css/ and node_modules/"
	@rm -rf "$(ROOT)/js" "$(ROOT)/css" "$(ROOT)/node_modules"

prune:
	@echo ">> maplibre-gl-prune: removing node_modules/"
	@rm -rf "$(ROOT)/node_modules"

check:
	@$(ROOT)/scripts/check-deps.sh maplibre-gl
