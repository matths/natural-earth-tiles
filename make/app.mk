# make/app.mk - Svelte app module (runs as its own make process)
#
# Bundles the Svelte 5 app in ./src/ into a single ESM file `main.js` in the repo
# root - which is exactly what index.html loads. GitHub Pages serves the repo
# root, so the bundle is committed just like the tiles/fonts (dist/ is not
# deployed and stays gitignored).
#
#   make app          npm install (if needed) + vite build -> ./main.js
#   make app-clean    remove ./dist and the built ./main.js
#   make app-check    verify node + npm
#
# Development: `npm run dev` (Vite dev server with HMR). index.html keeps loading
# /main.js; vite.config.ts aliases that to src/main.ts in dev, so no separate dev
# HTML is needed. `npm run app:watch` rebuilds ./main.js on every change instead.

SHELL := /bin/bash
ROOT  := $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)

# the committed bundle that index.html loads
APP_OUT ?= $(ROOT)/main.js

.PHONY: app clean check
.DEFAULT_GOAL := app

app: check
	@echo ">> npm install (svelte, vite, @sveltejs/vite-plugin-svelte)"
	@cd "$(ROOT)" && npm install --no-audit --no-fund
	@echo ">> vite build -> $(APP_OUT)"
	@cd "$(ROOT)" && npx vite build
	@cp "$(ROOT)/dist/main.js" "$(APP_OUT)"
	@echo ">> wrote $(APP_OUT)"

clean:
	@echo ">> app-clean: removing $(ROOT)/dist and $(APP_OUT)"
	@rm -rf "$(ROOT)/dist" "$(APP_OUT)"

check:
	@$(ROOT)/scripts/check-deps.sh app
