import type { Map as MapLibreMap } from "maplibre-gl";
import maplibregl from "./maplibre";
import { resolveTileRequest } from "./resolve-tile-request";
import { styleUrl } from "./style";

export type MapOptions = {
  container: HTMLElement;
  maxZoom?: number;
};

const defaultMaxZoom = 8;
const globeReferencePixels = 150;

const fitGlobeToContainer = (map: MapLibreMap): void => {
  const { offsetWidth, offsetHeight } = map.getContainer();
  const pixels = Math.min(offsetWidth, offsetHeight);
  map.flyTo({ zoom: Math.log2(pixels / globeReferencePixels), essential: true });
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
