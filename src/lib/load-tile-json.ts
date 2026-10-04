import { absoluteTileJsonUrl, tileJsonUrl } from "./style";

export type VectorTileJson = {
  vector_layers?: { id?: string; fields?: Record<string, string> }[];
};

export const loadTileJson = async (): Promise<VectorTileJson> => {
  const response = await fetch(absoluteTileJsonUrl);
  if (!response.ok) {
    throw new Error(`could not load ${tileJsonUrl} (HTTP ${response.status})`);
  }
  return (await response.json()) as VectorTileJson;
};
