import { mount, unmount } from "svelte";
import type { IControl, Map as MapLibreMap } from "maplibre-gl";
import ThemeControl from "../components/ThemeControl.svelte";

export const createThemeControl = (): IControl => {
  let component: Record<string, unknown> | undefined;

  const onAdd = (_map: MapLibreMap): HTMLElement => {
    const container = document.createElement("div");
    container.className = "maplibregl-ctrl";
    component = mount(ThemeControl, { target: container });
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
