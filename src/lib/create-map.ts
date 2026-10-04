import type { Map as MapLibreMap } from "maplibre-gl";
import maplibregl from "./maplibre";
import { resolveTileRequest } from "./resolve-tile-request";
import { styleUrl } from "./style";

export type MapOptions = {
  container: HTMLElement;
  maxZoom?: number;
};

const defaultMaxZoom = 8;

// Approximate zoom for the globe: MapLibre's globe radius is
// 512 * 2^zoom / (2 * PI * cos(lat)) pixels, so a shorter frame side of ~150 px
// per zoom step lands the disc just inside the frame. `globeFrameUsage` then
// keeps a little space around it, which also leaves room for the atmosphere glow.
const globeFitDivisor = 150;
const globeFrameUsage = 0.9;

const fitGlobeToContainer = (map: MapLibreMap): void => {
  const { offsetWidth: width, offsetHeight: height } = map.getContainer();
  if (!width || !height) return;
  const frame = Math.min(width, height) * globeFrameUsage;
  map.flyTo({ zoom: Math.log2(frame / globeFitDivisor), essential: true });
};

const addCornerControls = (map: MapLibreMap): void => {
  map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-left");
  map.addControl(new maplibregl.GlobeControl(), "top-left");
};

export const createMap = ({
  container,
  maxZoom = defaultMaxZoom,
}: MapOptions): MapLibreMap => {
  const map = new maplibregl.Map({
    container,
    style: styleUrl,
    maxZoom,
    transformRequest: resolveTileRequest,
    attributionControl: { compact: false },
  });

  if (import.meta.env.DEV) (window as unknown as { __map: MapLibreMap }).__map = map;

  map.on("load", () => {
    fitGlobeToContainer(map);
    addCornerControls(map);
  });

  return map;
};
