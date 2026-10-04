<script lang="ts">
  import { applyTheme, readTheme, toggleTheme, type Theme } from "../lib/theme";

  // U+FE0E keeps the sun as a glyph instead of an emoji on platforms that would
  // otherwise pick the colourful presentation.
  const sun = "\u2600\uFE0E";
  const moon = "\u263E";

  let theme = $state<Theme>(readTheme());
  const label = $derived(theme === "dark" ? "Switch to light mode" : "Switch to dark mode");

  const flip = (): void => {
    theme = toggleTheme(theme);
    applyTheme(theme);
  };
</script>

<div class="map-control">
  <div class="maplibregl-ctrl-group">
    <button
      type="button"
      class="control-button"
      title={label}
      aria-label={label}
      aria-pressed={theme === "dark"}
      onclick={flip}
    >
      {theme === "dark" ? sun : moon}
    </button>
  </div>
</div>
