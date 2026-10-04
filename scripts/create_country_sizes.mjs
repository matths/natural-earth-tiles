#!/usr/bin/env node
// Generates country-sizes.json: for every country (ADM0_A3) a "size" value
// describing the extent of its MAIN shape (in degrees, bbox diagonal).
//
// The main shape is picked so that small extraterritorial pieces do NOT count:
//   - use the country's largest polygon (its main landmass). For France this
//     yields metropolitan France (bbox [-4.8,42.3 .. 8.2,51.1]), ignoring
//     French Guiana, Réunion, Mayotte, Guadeloupe, Martinique, ...
//   - if the polygon containing the Natural Earth label point is even larger
//     (rare), prefer that one instead.
//
// Archipelagos are intentionally sized by their largest island.
//
// Usage:
//   make country-sizes                                # from the vector geojson
//   node scripts/create_country_sizes.mjs [input.geojson] [output.json]
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Anchored to the repo root (parent of this scripts/ dir) so defaults work no
// matter where it is invoked from; the Makefile passes explicit paths anyway.
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const INPUT = process.argv[2] || path.join(ROOT, ".vector-src", "countries.geojson");
const OUTPUT = process.argv[3] || path.join(ROOT, "country-sizes.json");

if (!fs.existsSync(INPUT)) {
  console.error(`Input not found: ${INPUT}`);
  console.error("Build it first with `make vector` (the geojson lives in .vector-src/).");
  process.exit(1);
}

const gj = JSON.parse(fs.readFileSync(INPUT, "utf8"));

// --- geometry helpers -----------------------------------------------------

// Returns the outer rings of all polygons of a geometry.
function polygonRings(geometry) {
  if (!geometry) return [];
  if (geometry.type === "Polygon") return [geometry.coordinates];
  if (geometry.type === "MultiPolygon") return geometry.coordinates;
  return [];
}

function outerBBox(coords) {
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  for (const [x, y] of coords[0]) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return { minX, maxX, minY, maxY };
}

// Planar shoelace area in "square degrees" - only used for ranking polygons,
// so the distortion does not matter.
function outerArea(coords) {
  const ring = coords[0];
  let a = 0;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    a += (ring[j][0] + ring[i][0]) * (ring[j][1] - ring[i][1]);
  }
  return Math.abs(a / 2);
}

// Ray casting test against an outer ring.
function pointInRing(x, y, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i][0];
    const yi = ring[i][1];
    const xj = ring[j][0];
    const yj = ring[j][1];
    const intersects = yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;
    if (intersects) inside = !inside;
  }
  return inside;
}

function bboxDiagonal(bbox) {
  return Math.hypot(Math.abs(bbox.maxX - bbox.minX), Math.abs(bbox.maxY - bbox.minY));
}

// --- label-size factor mapping ---------------------------------------------
// Maps the main-shape diagonal (degrees) to a text-size multiplier that
// style.json applies on top of the zoom curve. Tune these to taste, then
// re-run:  make country-sizes
const DEGREE_TO_FACTOR = [
  [0.05, 0.3],
  [0.25, 0.42],
  [1, 0.52],
  [3, 0.6],
  [6, 0.7],
  [10, 0.82],
  [16, 0.92],
  [26, 1.08],
  [38, 1.18],
  [55, 1.3],
  [75, 1.42],
  [110, 1.52],
  [160, 1.62],
];

function factorFor(diag) {
  const first = DEGREE_TO_FACTOR[0];
  const last = DEGREE_TO_FACTOR[DEGREE_TO_FACTOR.length - 1];
  if (diag <= first[0]) return first[1];
  if (diag >= last[0]) return last[1];
  for (let i = 1; i < DEGREE_TO_FACTOR.length; i++) {
    const [x1, y1] = DEGREE_TO_FACTOR[i - 1];
    const [x2, y2] = DEGREE_TO_FACTOR[i];
    if (diag <= x2) return y1 + ((diag - x1) * (y2 - y1)) / (x2 - x1);
  }
  return 1;
}

// --- main -----------------------------------------------------------------

const sizes = {};
const disagreements = [];

for (const feature of gj.features) {
  const p = feature.properties || {};
  const iso = p.ADM0_A3;
  if (!iso) continue;

  const rings = polygonRings(feature.geometry);
  if (rings.length === 0) continue;

  const polys = rings.map((coords) => {
    const bbox = outerBBox(coords);
    return { coords, bbox, area: outerArea(coords), diag: bboxDiagonal(bbox) };
  });

  // Primary: the country's largest polygon (its main landmass).
  let main = polys.reduce((a, b) => (b.area > a.area ? b : a));

  // Secondary: the polygon that actually contains the Natural Earth label
  // point. Use it instead if it is larger than the largest (rare).
  if (Number.isFinite(p.LABEL_X) && Number.isFinite(p.LABEL_Y)) {
    const byLabel = polys.find((pl) => pointInRing(p.LABEL_X, p.LABEL_Y, pl.coords[0]));
    if (byLabel && byLabel.area > main.area) {
      disagreements.push({ iso, name: p.NAME, labelDiag: byLabel.diag, largestDiag: main.diag });
      main = byLabel;
    }
  }

  sizes[iso] = {
    name: p.NAME,
    diag: Math.round(main.diag * 100) / 100, // extent of main shape in degrees
    size: Math.round(factorFor(main.diag) * 1000) / 1000, // label-size multiplier
  };
}

fs.writeFileSync(OUTPUT, JSON.stringify(sizes, null, 2) + "\n");
console.log(`Wrote ${OUTPUT} (${Object.keys(sizes).length} countries).`);
if (disagreements.length) {
  console.log(`Label-point polygon differs from largest polygon for ${disagreements.length} countries:`);
  for (const d of disagreements) console.log(`  ${d.iso} ${d.name}: label ${d.labelDiag}° vs largest ${d.largestDiag}°`);
}
