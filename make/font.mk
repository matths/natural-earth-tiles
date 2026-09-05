# make/font.mk - Noto glyph module (runs as its own make process)
#
# Builds MapLibre glyph PBFs into ./font/<Font Stack>/<range>.pbf from Google
# Fonts' Noto Sans (Regular/Bold + Arabic + Hebrew) via fontnik. This is what
# style.json's "glyphs" source reads.
#
#   make font          build all glyph sets (incremental) -> ./font/
#   make font-clean    remove ./font/ + .font-src/ + .font-tools/ caches
#   make font-check    verify curl, node, npm
#
# Requires: curl, node, npm (fontnik installs prebuilt binaries - see
# scripts/font-build.sh). The engine lives in scripts/font-build.sh and handles
# the CSS fetch, ttf download and glyph building; this file only orchestrates.
#
# In style.json point text-font at ONE built font (e.g. "Noto Sans Regular") -
# static hosts serve one glyph request per stack and cannot merge glyphs across
# the separate ./font/<font>/ folders.

SHELL := /bin/bash
ROOT  := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)

# where the glyph pbf output goes - commit this folder
FONT_DIR ?= $(ROOT)/font

.PHONY: font clean check
.DEFAULT_GOAL := font

font: check
	@$(ROOT)/scripts/font-build.sh "$(ROOT)" "$(FONT_DIR)"

clean:
	@echo ">> font-clean: removing $(FONT_DIR) and caches .font-src/ .font-tools/"
	@rm -rf "$(FONT_DIR)" "$(ROOT)/.font-src" "$(ROOT)/.font-tools"

check:
	@$(ROOT)/scripts/check-deps.sh font
