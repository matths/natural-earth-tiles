import type { Map as MapLibreMap } from "maplibre-gl";

export const fontFacesUrl = "font/font-faces.json";

export type FontFaces = NonNullable<Parameters<MapLibreMap["setFontFaces"]>[0]>;

export const loadFontFaces = async (): Promise<FontFaces> => {
  try {
    return (await (await fetch(fontFacesUrl)).json()) as FontFaces;
  } catch {
    console.warn(`${fontFacesUrl} not available; labels fall back to local fonts`);
    return {};
  }
};
