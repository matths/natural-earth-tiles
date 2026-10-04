<script lang="ts">
  import type { StyleVariant, StyleVariantId } from "../lib/load-style-variants";

  type Props = {
    variants: StyleVariant[];
    getVariant: () => StyleVariantId;
    onSelect: (variant: StyleVariantId) => void;
  };

  let { variants, getVariant, onSelect }: Props = $props();

  let open = $state(false);
  let root = $state<HTMLDivElement | null>(null);

  const choose = (variant: StyleVariant): void => {
    onSelect(variant.id);
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
      title="Style variation"
      aria-label="Style variation"
      aria-haspopup="menu"
      aria-expanded={open}
      onclick={() => (open = !open)}
    >
      ❏
    </button>
  </div>

  {#if open}
    {@const current = getVariant()}
    <div class="control-flyout" role="menu" aria-label="Style variation">
      {#each variants as variant (variant.id)}
        <button
          type="button"
          role="menuitemradio"
          aria-checked={variant.id === current}
          class:selected={variant.id === current}
          onclick={() => choose(variant)}
        >
          <strong>{variant.label}</strong>
          <small>{variant.hint}</small>
        </button>
      {/each}
    </div>
  {/if}
</div>
