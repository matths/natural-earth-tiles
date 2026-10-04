#!/usr/bin/env node
/**
 * scripts/font-build.mjs <root> <fontdir>
 *
 * Builds the <root>/<fontdir>/font-faces.json (+ downloaded woff2 files in
 * <fontdir>/faces/) that style.json/main.js feed to MapLibre's "font-faces".
 *
 * Why font-faces instead of glyph PBFs?
 *   A glyph-PBF stack is a single font: whatever script it does not contain is
 *   simply missing, and MapLibre cannot fall back to another stack for the
 *   characters it cannot draw (text-font is a single comma-joined URL segment,
 *   which 404s on static hosts). With "font-faces" MapLibre instead resolves
 *   EVERY character against a list of font files and their unicode-range, so a
 *   single text-font name covers Latin, Greek, Cyrillic, Devanagari, Arabic,
 *   Hebrew, Bengali, ... automatically. No fontnik, no empty range files.
 *
 * Source: Google Fonts CSS2 with a browser User-Agent, which returns woff2
 * subsets each with an explicit unicode-range - exactly the shape font-faces
 * wants. Files are cached: existing woff2 are not re-downloaded.
 *
 * CJK/Hangul are intentionally not bundled (very large); MapLibre draws those
 * locally via the map's localIdeographFontFamily.
 *
 * Output is deterministic: font/<faces>/<family>-<weight>-<subset>.woff2 and a
 * font-faces map keyed by stack name (e.g. "Noto Sans Regular").
 */
import fs from "node:fs";
import path from "node:path";

const [ROOT, FONT_DIR] = process.argv.slice(2);
if (!ROOT || !FONT_DIR) {
  console.error("usage: font-build.mjs <root> <fontdir>");
  process.exit(2);
}

const FACE_DIR = path.join(FONT_DIR, "faces");
const CACHE_DIR = path.join(ROOT, ".font-src");
const OUT_JSON = path.join(FONT_DIR, "font-faces.json");

// Google Fonts serves woff2 (with unicode-range) only for browser-like agents.
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";

// Stack name -> weight. The name is what style.json's "text-font" refers to.
const STACKS = [
  { name: "Noto Sans Regular", weight: 400 },
  { name: "Noto Sans Bold", weight: 700 },
];

// Families merged into every stack. "Noto Sans" covers Latin/Greek/Cyrillic/
// Devanagari; the others add the scripts it does not have. Order matters:
// MapLibre uses the FIRST face whose unicode-range contains the character.
const FAMILIES = [
  "Noto Sans",
  "Noto Sans Arabic",
  "Noto Sans Hebrew",
  "Noto Sans Bengali",
];

const slug = (s) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

async function fetchCss(family, weight) {
  const cache = path.join(CACHE_DIR, `${slug(family)}-${weight}.css`);
  if (fs.existsSync(cache) && fs.statSync(cache).size > 0) {
    return fs.readFileSync(cache, "utf8");
  }
  const url = `https://fonts.googleapis.com/css2?family=${family.replace(
    / /g,
    "+",
  )}:wght@${weight}&display=swap`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) return null;
  const css = await res.text();
  fs.writeFileSync(cache, css);
  return css;
}

// Each "/* subset */ @font-face { ... }" block -> { subset, url, ranges }.
function parseFaces(css) {
  const faces = [];
  const re = /\/\*\s*([^*]+?)\s*\*\/\s*@font-face\s*\{([^}]*)\}/g;
  let m;
  while ((m = re.exec(css))) {
    const subset = m[1].trim().replace(/\s+/g, "-");
    const body = m[2];
    const url = (body.match(/url\((https:[^)]+)\)/) || [])[1];
    if (!url) continue;
    const rangeStr = (body.match(/unicode-range:\s*([^;]+);/) || [])[1];
    const ranges = rangeStr
      ? rangeStr.split(",").map((s) => s.trim()).filter(Boolean)
      : null;
    faces.push({ subset, url, ranges });
  }
  return faces;
}

async function downloadFace(url, file) {
  if (fs.existsSync(file) && fs.statSync(file).size > 0) {
    return fs.statSync(file).size;
  }
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  if (!buf.length) throw new Error("empty body");
  fs.writeFileSync(file, buf);
  return buf.length;
}

fs.mkdirSync(FACE_DIR, { recursive: true });
fs.mkdirSync(CACHE_DIR, { recursive: true });

const out = {};
const skipped = [];
let bytes = 0;
let files = 0;

for (const { name, weight } of STACKS) {
  const faces = [];
  for (const family of FAMILIES) {
    let css;
    try {
      css = await fetchCss(family, weight);
    } catch (err) {
      css = null;
      skipped.push(`${family} ${weight} (${err.message})`);
    }
    if (!css) {
      if (!skipped.some((s) => s.startsWith(`${family} ${weight}`))) {
        skipped.push(`${family} ${weight} (no CSS / weight unavailable)`);
      }
      continue;
    }
    for (const face of parseFaces(css)) {
      const file = path.join(FACE_DIR, `${slug(family)}-${weight}-${face.subset}.woff2`);
      try {
        const size = await downloadFace(face.url, file);
        bytes += size;
        files++;
        const entry = { url: `font/faces/${path.basename(file)}` };
        if (face.ranges?.length) entry["unicode-range"] = face.ranges;
        faces.push(entry);
      } catch (err) {
        skipped.push(`${path.basename(file)} (${err.message})`);
      }
    }
  }
  out[name] = faces;
}

fs.writeFileSync(OUT_JSON, `${JSON.stringify(out, null, 2)}\n`);

console.log(">> font-faces written to " + path.relative(ROOT, OUT_JSON));
for (const [stack, faces] of Object.entries(out)) {
  console.log(`   ${stack}: ${faces.length} face(s)`);
}
console.log(
  `   ${files} woff2 file(s), ${(bytes / 1048576).toFixed(2)} MB in ${path.relative(
    ROOT,
    FACE_DIR,
  )}/`,
);
if (skipped.length) {
  console.log("   skipped: " + skipped.join(", "));
}

const legacy = fs
  .readdirSync(FONT_DIR, { withFileTypes: true })
  .filter((e) => e.isDirectory() && e.name !== "faces");
if (legacy.length) {
  console.log(
    `   note: legacy glyph folders still present (${legacy
      .map((e) => e.name)
      .join(", ")}) - run 'make font-clean' to drop them`,
  );
}

console.log();
console.log("Next steps:");
console.log('  style.json: no "glyphs" URL needed; keep "text-font": ["Noto Sans Regular"]');
console.log("  main.js merges font/font-faces.json into the style at startup.");
