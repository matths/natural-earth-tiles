import type { Map as MapLibreMap } from "maplibre-gl";
import type { LayerStyling } from "./load-style-variants";

export const applyStyleVariant = (map: MapLibreMap, layers: Record<string, LayerStyling>): void => {
  for (const [layerId, styling] of Object.entries(layers)) {
    for (const [name, value] of Object.entries(styling.paint)) {
      map.setPaintProperty(layerId, name as never, value as never);
    }
    for (const [name, value] of Object.entries(styling.layout)) {
      map.setLayoutProperty(layerId, name as never, value as never);
    }
  }
};
