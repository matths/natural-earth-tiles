import type { GeoJSONSource, Map as MapLibreMap } from "maplibre-gl";
import type { Feature, FeatureCollection, Point } from "geojson";
import { defaultLanguage } from "./load-languages";
import { labelLayer, labelSource, sourceId, sourceLayer } from "./style";

const defaultLabelSize = 0.85;
const countrySizesUrl = "country-sizes.json";

export type LabelController = {
  setLanguage: (value: string) => void;
  destroy: () => void;
};

type CountrySizes = Record<string, { size?: number } | undefined>;

const loadCountrySizes = async (): Promise<CountrySizes> => {
  try {
    return (await (await fetch(countrySizesUrl)).json()) as CountrySizes;
  } catch {
    console.warn(`${countrySizesUrl} not available; using default label size`);
    return {};
  }
};

const readCountrySize = (countrySizes: CountrySizes, iso: string): number =>
  countrySizes[iso]?.size ?? defaultLabelSize;

const toLabelProperties = (
  sourceProperties: Record<string, unknown> | null | undefined,
  iso: string,
  labelFields: string[],
  countrySizes: CountrySizes,
): Record<string, unknown> => {
  const properties: Record<string, unknown> = {
    ADM0_A3: iso,
    SIZE: readCountrySize(countrySizes, iso),
  };
  for (const field of labelFields) properties[field] = sourceProperties?.[field];
  return properties;
};

const toLabelFeature = (
  feature: Feature,
  iso: string,
  labelFields: string[],
  countrySizes: CountrySizes,
): Feature<Point> => ({
  type: "Feature",
  properties: toLabelProperties(feature.properties, iso, labelFields, countrySizes),
  geometry: {
    type: "Point",
    coordinates: [
      feature.properties?.LABEL_X as number,
      feature.properties?.LABEL_Y as number,
    ],
  },
});

const collectLabelFeatures = (
  map: MapLibreMap,
  labelFields: string[],
  countrySizes: CountrySizes,
): Map<string, Feature<Point>> => {
  const labelFeatures = new Map<string, Feature<Point>>();

  for (const feature of map.querySourceFeatures(sourceId, { sourceLayer })) {
    const iso = feature.properties?.ADM0_A3 as string | undefined;
    if (!iso || labelFeatures.has(iso)) continue;
    labelFeatures.set(iso, toLabelFeature(feature, iso, labelFields, countrySizes));
  }

  return labelFeatures;
};

const writeLabelSource = (
  map: MapLibreMap,
  labelFields: string[],
  countrySizes: CountrySizes,
): void => {
  const source = map.getSource(labelSource) as GeoJSONSource | undefined;
  if (!source) return;

  const collection: FeatureCollection<Point> = {
    type: "FeatureCollection",
    features: [...collectLabelFeatures(map, labelFields, countrySizes).values()],
  };
  void source.setData(collection);
};

const labelPropertyOf = (language: string): string =>
  language === defaultLanguage ? "NAME" : language;

const applyLabelLanguage = (map: MapLibreMap, language: string): void => {
  const textField = ["get", labelPropertyOf(language)];
  map.setLayoutProperty(labelLayer, "text-field", textField as never);
};

export const createLabels = async (
  map: MapLibreMap,
  labelFields: string[],
  initialLanguage: string = defaultLanguage,
): Promise<LabelController> => {
  const countrySizes = await loadCountrySizes();

  const refresh = (): void => writeLabelSource(map, labelFields, countrySizes);

  refresh();
  map.on("idle", refresh);
  applyLabelLanguage(map, initialLanguage);

  return {
    setLanguage: (value: string) => applyLabelLanguage(map, value),
    destroy: () => {
      map.off("idle", refresh);
    },
  };
};
