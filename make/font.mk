# make/font.mk - Noto web-font module (runs as its own make process)
#
# Downloads Noto woff2 subsets from Google Fonts into ./font/faces/ and writes
# ./font/font-faces.json - the per-character font fallback map that main.js
# merges into style.json's "font-faces" property.
#
#   make font          download/refresh the font faces -> ./font/
#   make font-clean    remove ./font/ and the .font-src/ cache
#   make font-check    verify curl + node
#
# Why not glyph PBFs: a glyph stack holds ONE font, and MapLibre cannot fall
# back to a second stack for characters it cannot draw (the glyphs URL contains
# a single comma-joined {fontstack} path segment, which 404s on static hosts).
# "font-faces" instead resolves every character against a list of font files
# with unicode-ranges, so one text-font name covers Latin/Greek/Cyrillic/
# Devanagari/Arabic/Hebrew/Bengali. CJK/Hangul stay local, drawn by MapLibre
# via localIdeographFontFamily.
#
# The engine lives in scripts/font-build.mjs (fetch CSS + download woff2 +
# emit JSON); this file only orchestrates.

SHELL := /bin/bash
ROOT  := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)
SCRIPTS := $(ROOT)/scripts

# where the fonts are published - commit this folder
FONT_DIR ?= $(ROOT)/font

.PHONY: font clean check
.DEFAULT_GOAL := font

font: check
	@node $(SCRIPTS)/font-build.mjs "$(ROOT)" "$(FONT_DIR)"

clean:
	@echo ">> font-clean: removing $(FONT_DIR) and cache .font-src/"
	@rm -rf "$(FONT_DIR)" "$(ROOT)/.font-src"

check:
	@$(SCRIPTS)/check-deps.sh font
