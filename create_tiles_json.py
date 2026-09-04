import sqlite3
import json
import sys
import os

base_url = 'https://matths.github.io/natural-earth-tiles/tiles/'
mbtiles_file = None
metadata_file = 'tiles/metadata.json'
tiles_file = 'tiles/tiles.json'

for arg in sys.argv:
    if arg.startswith('--base-url='):
        base_url = arg.split('=')[1]
    if arg.startswith('--mbtiles='):
        mbtiles_file = arg.split('=')[1]
    if arg.startswith('--metadata='):
        metadata_file = arg.split('=')[1]
    if arg.startswith('--out='):
        tiles_file = arg.split('=')[1]

vector_layers = []

# vector_layers come from the .mbtiles when one is passed (the tippecanoe-based
# methods). If there is no .mbtiles - the 'direct' method tiles straight from
# the shapefile - fall back to the vector_layers that GDAL's MVT driver embeds
# in the "json" field of its own metadata.json.
if mbtiles_file is not None and os.path.exists(mbtiles_file):
    conn = sqlite3.connect(mbtiles_file)
    cursor = conn.cursor()
    metadata = {row[0]: row[1] for row in cursor.execute("SELECT name, value FROM metadata")}
    if "json" in metadata:
        vector_layers = json.loads(metadata["json"]).get("vector_layers", [])

with open(metadata_file, 'r') as f:
    metadata = json.load(f)

# Fallback for methods with no .mbtiles (e.g. 'direct'): GDAL's own
# metadata.json carries the same vector_layers under its "json" key.
if not vector_layers and "json" in metadata:
    json_metadata = metadata["json"]
    if isinstance(json_metadata, str):
        json_metadata = json.loads(json_metadata)
    vector_layers = json_metadata.get("vector_layers", [])

tiles_json = {
    "tilejson": "2.2.0",
    "name": metadata.get("name", "tiles"),
    "description": metadata.get("description", "tiles"),
    "profile": metadata.get("profile", "mercator"),
    "attribution": "Made with <a href='https://www.naturalearthdata.com/'>Natural Earth</a>.",
    "version": "1.0.0",
    "format": "pbf",
    "tiles": [base_url + "{z}/{x}/{y}.pbf"],
    "minzoom": int(metadata.get("minzoom", "0")),
    "maxzoom": int(metadata.get("maxzoom", "0")),
    "bounds": list(map(float, metadata.get("bounds", "-180, -85.0511, 180, 85.0511").split(','))),
    "center": list(map(float, metadata.get("center", "0, 0").split(','))),
    "vector_layers": vector_layers
}

with open(tiles_file, 'w') as f:
    json.dump(tiles_json, f, indent=2)

print(tiles_file + "has been created.")
