import { createReadStream, existsSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";

const root = fileURLToPath(new URL(".", import.meta.url));

// The app is built as ONE ESM bundle named `main.js` in the repo root, so the
// committed GitHub Pages layout (index.html + main.js + tiles/ raster/ font/
// js/ css/) stays exactly as it is and nothing has to be deployed from dist/.
//
// `maplibre-gl` is kept external (see resolve.alias / build.rollupOptions below),
// so the browser keeps loading the committed js/maplibre-gl.mjs instead of a
// second, bundled copy of MapLibre.
export default defineConfig({
  plugins: [
    svelte(),
    {
      // index.html always loads /main.js. During dev that path is either the
      // stale build artifact or missing entirely, so serve the source entry.
      // `vite dev` therefore gives you HMR against src/ with no extra file.
      name: "app:dev-entry-alias",
      apply: "serve",
      configureServer(server) {
        server.middlewares.use((req, _res, next) => {
          if (req.url === "/main.js") req.url = "/src/main.ts";
          next();
        });
      },
    },
    {
      // js/ is a VENDORED build (`make maplibre-gl` copies maplibre-gl/dist/),
      // and GitHub Pages serves it byte for byte. Vite would otherwise run its
      // module pipeline over js/maplibre-gl*.mjs, which injects the HMR client
      // and prints "the above dynamic import cannot be analyzed by Vite" for
      // MapLibre's own blob-worker fallback. Serve these three files raw so dev
      // matches what is deployed and the warnings stay away.
      name: "app:vendored-maplibre-raw",
      apply: "serve",
      configureServer(server) {
        server.middlewares.use((req, res, next) => {
          const path = decodeURIComponent((req.url ?? "").split("?")[0]);
          if (!path.startsWith("/js/") || !path.endsWith(".mjs")) return next();

          const file = root + path.slice(1);
          if (!existsSync(file)) return next();

          // Revalidate instead of re-downloading: maplibre-gl.mjs alone is
          // ~800 kB and `make maplibre-gl` replaces it in place.
          const modified = statSync(file).mtime.toUTCString();
          if (req.headers["if-modified-since"] === modified) {
            res.statusCode = 304;
            res.end();
            return;
          }

          res.setHeader("Content-Type", "text/javascript");
          res.setHeader("Cache-Control", "no-cache");
          res.setHeader("Last-Modified", modified);
          createReadStream(file).pipe(res);
        });
      },
    },
  ],
  server: {
    // Pinned host+port so `npm run dev` is predictable and serves the whole
    // repo (index.html, style.json, tiles/, raster/, font/, js/ ...) on ONE
    // origin. An explicit IP matters on macOS: a bare `localhost` can bind
    // IPv6-only, which makes http://127.0.0.1:<port> refuse connections even
    // though Vite printed a ready URL. The port is only a convention - the tile
    // template in tiles.json is relative, so any port works.
    host: "127.0.0.1",
    port: 8080,
  },
  resolve: {
    // Dev: resolve the bare specifier to the vendored build. The production
    // build keeps it external instead and rewrites the path via output.paths.
    alias: {
      "maplibre-gl": fileURLToPath(new URL("js/maplibre-gl.mjs", import.meta.url)),
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
    target: "es2022",
    // Off for the published bundle: the browser would look for ./main.js.map
    // next to the copied main.js and 404 (only dist/ gets the map, and dist/ is
    // never deployed). `npm run dev` still gives you full sourcemaps. To debug
    // the deployed bundle instead, set this to true AND copy dist/main.js.map to
    // the repo root in make/app.mk.
    sourcemap: false,
    rollupOptions: {
      input: fileURLToPath(new URL("src/main.ts", import.meta.url)),
      external: ["maplibre-gl"],
      output: {
        format: "es",
        // `maplibre-gl` stays external, so tell rollup what to emit for it: a
        // path that is correct relative to the built ./main.js.
        paths: {
          "maplibre-gl": "./js/maplibre-gl.mjs",
        },
        entryFileNames: "main.js",
        chunkFileNames: "[name].js",
        assetFileNames: "app.[ext]",
        banner: "/* GENERATED FILE - built by `make app` from src/. Do not edit. */",
      },
    },
  },
});
