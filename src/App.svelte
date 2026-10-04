<script lang="ts">
  import { onMount } from "svelte";
  import type { Map as MapLibreMap } from "maplibre-gl";
  import { applyFontFaces } from "./lib/apply-font-faces";
  import { createLanguageLabels, type LanguageLabels } from "./lib/create-language-labels";
  import { createMap } from "./lib/create-map";
  import { createStyleSwitcher, type StyleSwitcher } from "./lib/create-style-switcher";
  import { enableCountryHover } from "./lib/enable-country-hover";
  import { loadFontFaces } from "./lib/load-font-faces";
  import { loadTileJson } from "./lib/load-tile-json";
  import { whenStyleLoaded } from "./lib/when-style-loaded";

  type MapApp = {
    map: MapLibreMap;
    languageLabels: LanguageLabels;
    styleSwitcher: StyleSwitcher;
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

    return { map, languageLabels, styleSwitcher };
  };

  onMount(() => {
    const container = mapContainer;
    if (!container) return;

    let cancelled = false;
    let app: MapApp | null = null;

    const tearDown = (): void => {
      app?.styleSwitcher.destroy();
      app?.languageLabels.destroy();
      app?.map.remove();
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