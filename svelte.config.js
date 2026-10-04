import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

/** @type {import('@sveltejs/vite-plugin-svelte').SvelteConfig} */
export default {
  // Enables TypeScript inside <script lang="ts"> (type-only features work
  // without this, but `{ script: true }` also covers the rest).
  preprocess: vitePreprocess({ script: true }),
};
