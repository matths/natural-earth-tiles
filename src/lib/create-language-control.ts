import { mount, unmount } from "svelte";
import type { IControl, Map as MapLibreMap } from "maplibre-gl";
import LanguageControl from "../components/LanguageControl.svelte";
import type { LanguageOption } from "./load-languages";

export type LanguageControlOptions = {
  languages: LanguageOption[];
  getLanguage: () => string;
  onSelect: (language: string) => void;
};

export const createLanguageControl = (options: LanguageControlOptions): IControl => {
  let component: Record<string, unknown> | undefined;

  const onAdd = (_map: MapLibreMap): HTMLElement => {
    const container = document.createElement("div");
    container.className = "maplibregl-ctrl";
    component = mount(LanguageControl, { target: container, props: options });
    return container;
  };

  const onRemove = (): void => {
    if (component) unmount(component);
    component = undefined;
  };

  return {
    getDefaultPosition: () => "top-left",
    onAdd,
    onRemove,
  };
};
