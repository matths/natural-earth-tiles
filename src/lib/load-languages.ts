import type { VectorTileJson } from "./load-tile-json";

export type LanguageOption = {
  value: string;
  label: string;
};

export type LanguageSet = {
  options: LanguageOption[];
  labelFields: string[];
};

type LanguageEntry = {
  field: string;
  subtag: string;
  native: string;
  english: string;
};

export const defaultLanguage = "auto";

const subtagAliases: Record<string, string> = { ZHT: "zh-Hant" };
const nativeNameOverrides: Record<string, string> = { id: "Bahasa Indonesia" };
const fallbackLabelFields = ["NAME"];
const englishDefaultLabel = "English";

const displayName = (subtag: string, locale: string): string | null => {
  try {
    return new Intl.DisplayNames([locale], { type: "language" }).of(subtag) ?? null;
  } catch {
    return null;
  }
};

const capitalise = (value: string): string =>
  value === "" ? value : value.charAt(0).toUpperCase() + value.slice(1);

const isLanguageField = (field: string): boolean =>
  /^NAME_[A-Z]{2}$/.test(field) || field.slice("NAME_".length) in subtagAliases;

const subtagOf = (field: string): string =>
  subtagAliases[field.slice("NAME_".length)] ?? field.slice("NAME_".length).toLowerCase();

const toLanguageEntry = (field: string): LanguageEntry => {
  const subtag = subtagOf(field);
  const english = displayName(subtag, "en") ?? subtag;
  const native =
    nativeNameOverrides[subtag] ?? capitalise(displayName(subtag, subtag) ?? english);
  return { field, subtag, native, english };
};

const byEnglishName = (a: LanguageEntry, b: LanguageEntry): number =>
  a.english.localeCompare(b.english);

const toLanguageOption = ({ field, native, english }: LanguageEntry): LanguageOption => ({
  value: field,
  label: `${native} (${english})`,
});

const readLayerFields = (tileJson: VectorTileJson): string[] => {
  const layers = tileJson.vector_layers ?? [];
  const labeled = layers.find(({ fields }) => fields && "NAME" in fields);
  const layerFields = Object.keys((labeled ?? layers[0])?.fields ?? {});

  if (layerFields.length === 0) {
    console.warn("tile manifest has no vector_layers; no label languages available");
  }

  return layerFields;
};

const findLabelFields = (layerFields: string[]): string[] => {
  const labelFields = layerFields.filter((field) => field.startsWith("NAME"));
  return labelFields.length > 0 ? labelFields : fallbackLabelFields;
};

export const loadLanguages = (tileJson: VectorTileJson): LanguageSet => {
  const layerFields = readLayerFields(tileJson);

  const options: LanguageOption[] = [
    { value: defaultLanguage, label: displayName("en", "en") ?? englishDefaultLabel },
    ...layerFields
      .filter(isLanguageField)
      .map(toLanguageEntry)
      .filter(({ subtag }) => subtag !== "en")
      .sort(byEnglishName)
      .map(toLanguageOption),
  ];

  return { options, labelFields: findLabelFields(layerFields) };
};
