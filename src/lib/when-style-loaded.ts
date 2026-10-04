import type { Map as MapLibreMap } from "maplibre-gl";

export const whenStyleLoaded = (map: MapLibreMap): Promise<void> => {
  if (map.isStyleLoaded()) return Promise.resolve();
  return new Promise((resolve) => {
    map.once("load", () => resolve());
  });
};
