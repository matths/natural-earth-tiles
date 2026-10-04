import { mount, unmount } from "svelte";
import type { IControl, Map as MapLibreMap } from "maplibre-gl";
import StyleControl from "../components/StyleControl.svelte";
import type { StyleVariant, StyleVariantId } from "./load-style-variants";

export type StyleControlOptions = {
  variants: StyleVariant[];
  getVariant: () => StyleVariantId;
  onSelect: (variant: StyleVariantId) => void;
};

export const createStyleControl = (options: StyleControlOptions): IControl => {
  let component: Record<string, unknown> | undefined;

  const onAdd = (_map: MapLibreMap): HTMLElement => {
    const container = document.createElement("div");
    container.className = "maplibregl-ctrl";
    component = mount(StyleControl, { target: container, props: options });
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
