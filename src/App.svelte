<script lang="ts">
  import { onMount } from "svelte";
  import type { IControl, Map as MapLibreMap } from "maplibre-gl";
  import { applyFontFaces } from "./lib/apply-font-faces";
  import { createLanguageLabels, type LanguageLabels } from "./lib/create-language-labels";
  import { createMap } from "./lib/create-map";
  import { createStyleSwitcher, type StyleSwitcher } from "./lib/create-style-switcher";
  import { createThemeControl } from "./lib/create-theme-control";
  import { enableCountryHover } from "./lib/enable-country-hover";
  import { loadFontFaces } from "./lib/load-font-faces";
  import { loadTileJson } from "./lib/load-tile-json";
  import { whenStyleLoaded } from "./lib/when-style-loaded";

  type MapApp = {
    map: MapLibreMap;
    languageLabels: LanguageLabels;
    styleSwitcher: StyleSwitcher;
    themeControl: IControl;
  };

  let mapContainer = $state<HTMLDivElement | null>(null);

  const startMap = async (container: HTMLElement): Promise<MapApp> => {
    const [fontFaces, tileJson] = await Promise.all([loadFontFaces(), loadTileJson()]);

    const map = createMap({ container });
    await whenStyleLoaded(map);

    applyFontFaces(map, fontFaces);
    const languageLabels = await createLanguageLabels(map, tileJson);
    enableCountryHover(map);
    const styleSwitcher = createStyleSwitcher(map);

    const themeControl = createThemeControl();
    map.addControl(themeControl);

    return { map, languageLabels, styleSwitcher, themeControl };
  };

  onMount(() => {
    const container = mapContainer;
    if (!container) return;

    let cancelled = false;
    let app: MapApp | null = null;

    const tearDown = (): void => {
      if (!app) return;
      app.styleSwitcher.destroy();
      app.languageLabels.destroy();
      app.map.removeControl(app.themeControl);
      app.map.remove();
      app = null;
    };

    void startMap(container).then((started) => {
      app = started;
      if (cancelled) tearDown();
    });

    return () => {
      cancelled = true;
      tearDown();
    };
  });
</script>

<div id="map" bind:this={mapContainer}></div>