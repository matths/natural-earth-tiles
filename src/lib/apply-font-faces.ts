import type { Map as MapLibreMap } from "maplibre-gl";
import type { FontFaces } from "./load-font-faces";

export const applyFontFaces = (map: MapLibreMap, fontFaces: FontFaces): void => {
  if (Object.keys(fontFaces).length > 0) map.setFontFaces(fontFaces);
};
