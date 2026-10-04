import type { Map as MapLibreMap } from "maplibre-gl";
import { applyStyleVariant } from "./apply-style-variant";
import { createStyleControl } from "./create-style-control";
import { loadStyleVariants, type LayerStyling, type StyleVariantId } from "./load-style-variants";

export type StyleSwitcher = {
  getVariant: () => StyleVariantId;
  setVariant: (variant: StyleVariantId) => void;
  destroy: () => void;
};

export const createStyleSwitcher = (map: MapLibreMap): StyleSwitcher => {
  const { default: initialVariant, variants } = loadStyleVariants(map);
  const layersOf = (variant: StyleVariantId): Record<string, LayerStyling> =>
    variants.find((entry) => entry.id === variant)?.layers ?? {};

  if (variants.length === 0) {
    console.warn("style.json declares no metadata.styleVariants; no style picker");
    return { getVariant: () => initialVariant, setVariant: () => {}, destroy: () => {} };
  }

  let current = initialVariant;

  const setVariant = (variant: StyleVariantId): void => {
    current = variant;
    applyStyleVariant(map, layersOf(variant));
  };

  const control = createStyleControl({
    variants,
    getVariant: () => current,
    onSelect: setVariant,
  });
  map.addControl(control);
  setVariant(current);

  return {
    getVariant: () => current,
    setVariant,
    destroy: () => map.removeControl(control),
  };
};
