<script lang="ts">
  import type { LanguageOption } from "../lib/load-languages";

  type Props = {
    languages: LanguageOption[];
    getLanguage: () => string;
    onSelect: (language: string) => void;
  };

  let { languages, getLanguage, onSelect }: Props = $props();

  let open = $state(false);
  let root = $state<HTMLDivElement | null>(null);

  const choose = (option: LanguageOption): void => {
    onSelect(option.value);
    open = false;
  };

  const closeOnOutsidePointerDown = (event: PointerEvent): void => {
    if (open && !root?.contains(event.target as Node)) open = false;
  };

  const closeOnEscape = (event: KeyboardEvent): void => {
    if (event.key === "Escape") open = false;
  };
</script>

<svelte:window onpointerdowncapture={closeOnOutsidePointerDown} onkeydown={closeOnEscape} />

<div class="map-control" bind:this={root}>
  <div class="maplibregl-ctrl-group">
    <button
      type="button"
      class="control-button"
      class:open
      title="Label language"
      aria-label="Label language"
      aria-haspopup="menu"
      aria-expanded={open}
      onclick={() => (open = !open)}
    >
      ⛿
    </button>
  </div>

  {#if open}
    {@const current = getLanguage()}
    <div class="control-flyout" role="menu" aria-label="Label language">
      {#each languages as option (option.value)}
        <button
          type="button"
          role="menuitemradio"
          aria-checked={option.value === current}
          class:selected={option.value === current}
          onclick={() => choose(option)}
        >
          {option.label}
        </button>
      {/each}
    </div>
  {/if}
</div>
