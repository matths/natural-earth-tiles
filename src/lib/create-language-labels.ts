import type { Map as MapLibreMap } from "maplibre-gl";
import { createLabels, type LabelController } from "./create-labels";
import { createLanguageControl } from "./create-language-control";
import { defaultLanguage, loadLanguages, type LanguageOption } from "./load-languages";
import type { VectorTileJson } from "./load-tile-json";

export type LanguageLabels = {
  languages: LanguageOption[];
  setLanguage: (value: string) => void;
  destroy: () => void;
};

export const createLanguageLabels = async (
  map: MapLibreMap,
  tileJson: VectorTileJson,
): Promise<LanguageLabels> => {
  const { options, labelFields } = loadLanguages(tileJson);

  let currentLanguage = defaultLanguage;
  let labels: LabelController | null = null;

  const setLanguage = (value: string): void => {
    currentLanguage = value;
    labels?.setLanguage(value);
  };

  map.addControl(
    createLanguageControl({
      languages: options,
      getLanguage: () => currentLanguage,
      onSelect: setLanguage,
    }),
  );

  labels = await createLabels(map, labelFields, currentLanguage);

  return {
    languages: options,
    setLanguage,
    destroy: () => {
      labels?.destroy();
      labels = null;
    },
  };
};
