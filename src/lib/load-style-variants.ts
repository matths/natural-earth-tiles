import type { Map as MapLibreMap } from "maplibre-gl";

export type StyleVariantId = string;

export type LayerStyling = {
  paint: Record<string, unknown>;
  layout: Record<string, unknown>;
};

export type StyleVariant = {
  id: StyleVariantId;
  label: string;
  hint: string;
  layers: Record<string, LayerStyling>;
};

export type StyleVariants = {
  default: StyleVariantId;
  variants: StyleVariant[];
};

type StylingKind = "paint" | "layout";

type StylingKey = {
  layerId: string;
  kind: StylingKind;
  name: string;
};

type VariantDefinition = {
  id: StyleVariantId;
  label: string;
  hint: string;
  overrides: Record<string, LayerStyling>;
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const readStyling = (value: unknown): LayerStyling => ({
  paint: isRecord(value) && isRecord(value.paint) ? value.paint : {},
  layout: isRecord(value) && isRecord(value.layout) ? value.layout : {},
});

const readStyleVariantsSetting = (metadata: unknown): Record<string, unknown> | undefined => {
  if (!isRecord(metadata) || !isRecord(metadata.styleVariants)) return undefined;
  return metadata.styleVariants;
};

const readVariantDefinitions = (metadata: unknown): VariantDefinition[] => {
  const variants = readStyleVariantsSetting(metadata)?.variants;
  if (!Array.isArray(variants)) return [];

  return variants.flatMap((entry) => {
    if (!isRecord(entry) || typeof entry.id !== "string") return [];

    const layers = isRecord(entry.layers) ? entry.layers : {};
    return [
      {
        id: entry.id,
        label: typeof entry.label === "string" ? entry.label : entry.id,
        hint: typeof entry.hint === "string" ? entry.hint : "",
        overrides: Object.fromEntries(
          Object.entries(layers).map(([layerId, styling]) => [layerId, readStyling(styling)]),
        ),
      },
    ];
  });
};

const collectStylingKeys = (definitions: VariantDefinition[]): StylingKey[] => {
  const keys = new Map<string, StylingKey>();

  for (const definition of definitions) {
    for (const [layerId, styling] of Object.entries(definition.overrides)) {
      for (const kind of ["paint", "layout"] as const) {
        for (const name of Object.keys(styling[kind])) {
          keys.set(`${layerId}:${kind}:${name}`, { layerId, kind, name });
        }
      }
    }
  }

  return [...keys.values()];
};

const readDeclaredValue = (map: MapLibreMap, { layerId, kind, name }: StylingKey): unknown =>
  kind === "paint"
    ? map.getPaintProperty(layerId, name as never)
    : map.getLayoutProperty(layerId, name as never);

const resolveStyling = (
  map: MapLibreMap,
  definition: VariantDefinition,
  keys: StylingKey[],
): Record<string, LayerStyling> => {
  const layers: Record<string, LayerStyling> = {};

  for (const key of keys) {
    if (!map.getLayer(key.layerId)) {
      console.warn(`style variation "${definition.id}": style.json has no layer "${key.layerId}"`);
      continue;
    }

    const override = definition.overrides[key.layerId]?.[key.kind][key.name];
    const declared = readDeclaredValue(map, key);
    const value = override ?? declared ?? null;

    const styling = (layers[key.layerId] ??= { paint: {}, layout: {} });
    styling[key.kind][key.name] = value;
  }

  return layers;
};

export const loadStyleVariants = (map: MapLibreMap): StyleVariants => {
  const metadata = map.getStyle().metadata;
  const definitions = readVariantDefinitions(metadata);
  const keys = collectStylingKeys(definitions);

  const variants = definitions.map((definition) => {
    const { id, label, hint } = definition;
    return { id, label, hint, layers: resolveStyling(map, definition, keys) };
  });

  const requested = readStyleVariantsSetting(metadata)?.default;
  const fallback = variants[0]?.id ?? "";

  return {
    default: variants.find(({ id }) => id === requested)?.id ?? fallback,
    variants,
  };
};
