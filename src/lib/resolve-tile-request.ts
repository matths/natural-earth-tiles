import { absoluteStyleUrl, absoluteTileJsonUrl, rasterTilePrefix } from "./style";

export const resolveTileRequest = (url: string, resourceType?: string): { url: string } => {
  if (resourceType !== "Tile") return { url };
  const base = url.startsWith(rasterTilePrefix) ? absoluteStyleUrl : absoluteTileJsonUrl;
  return { url: new URL(url, base).href };
};
