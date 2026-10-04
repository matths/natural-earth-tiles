import type { FeatureIdentifier, Map as MapLibreMap } from "maplibre-gl";
import { fillLayer, labelSource, sourceId, sourceLayer } from "./style";

const hoverTargets: FeatureIdentifier[] = [
  { source: sourceId, sourceLayer },
  { source: labelSource },
];

export const enableCountryHover = (map: MapLibreMap): void => {
  let hoveredIso: string | null = null;

  const setHover = (iso: string, hover: boolean): void => {
    for (const target of hoverTargets) {
      map.setFeatureState({ ...target, id: iso }, { hover });
    }
  };

  const clearHoveredCountry = (): void => {
    if (hoveredIso === null) return;
    setHover(hoveredIso, false);
    hoveredIso = null;
  };

  const hoverCountry = (iso: string): void => {
    if (iso === hoveredIso) return;
    clearHoveredCountry();
    hoveredIso = iso;
    setHover(iso, true);
  };

  map.on("mousemove", fillLayer, (event) => {
    const iso = event.features?.[0]?.properties?.ADM0_A3 as string | undefined;
    if (iso) hoverCountry(iso);
  });

  map.on("mouseleave", fillLayer, clearHoveredCountry);
};
