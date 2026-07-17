"""Minecraft (Anvil/namespaced block state) -> VoxelWorldCraft block_id map.

The right-hand side integers are the `block_id` values consumed by
Scripts/World/Chunk.gd's `create_block_faces()` (and registered as items in
Scripts/Autoload/ItemDatabase.gd where applicable). Keep this file in sync
with Chunk.gd's block palette by hand -- there is no single source of truth
shared between the Python importer and the GDScript engine.

Any `minecraft:*` block name encountered during import that is NOT a key in
MAPPING (and not in AIR_LIKE) is a gap: it gets rendered as the placeholder
block (PLACEHOLDER_BLOCK_ID) and counted in the gap list.
"""

# Blocks that represent "no voxel" -- skipped entirely during import (same as
# an absent Chunk.voxel_data entry), not counted as mapped or as a gap.
AIR_LIKE = {
    "minecraft:air",
    "minecraft:cave_air",
    "minecraft:void_air",
}

# MC namespaced block name -> VoxelWorldCraft block_id (see Chunk.gd).
MAPPING = {
    # --- Terrain / stone family ---
    "minecraft:stone": 3,          # Stone/Bedrock
    "minecraft:bedrock": 3,        # No dedicated Bedrock block in the engine;
                                    # Chunk.gd's own y==0 procedural pass
                                    # already reuses id 3 "Stone/Bedrock" for
                                    # this, so this is a same-engine-precedent
                                    # mapping, not an invented one.
    "minecraft:dirt": 1,           # Dirt
    "minecraft:grass_block": 2,    # Grass

    # --- Ores ---
    "minecraft:coal_ore": 5,       # Coal Ore
    "minecraft:iron_ore": 6,       # Iron Ore
    "minecraft:gold_ore": 81,      # Gold Ore (wave-2 mineral, ORE_TABLE id 81)
    "minecraft:copper_ore": 80,    # Copper Ore (wave-2 mineral, ORE_TABLE id 80)

    # --- Wood ---
    "minecraft:oak_log": 4,        # Oak Wood
    "minecraft:spruce_log": 49,    # Pine Wood (closest existing conifer log)

    # --- Leaves ---
    "minecraft:oak_leaves": 50,    # Leaves (Oak)
    "minecraft:spruce_leaves": 51, # Pine Leaves

    # --- Fluids ---
    "minecraft:water": 40,         # Water
    "minecraft:lava": 41,          # Lava

    # --- Biome surface ---
    "minecraft:snow": 43,          # Snow
    "minecraft:snow_block": 43,    # Snow
    "minecraft:sand": 42,          # Sand
    "minecraft:ice": 52,           # Ice (Tundra)

    # --- Plants / decoration ---
    "minecraft:poppy": 44,         # Red Flower
    "minecraft:dandelion": 45,     # Yellow Flower
    "minecraft:grass": 46,         # Tall Grass (pre-1.20 short-plant name)
    "minecraft:short_grass": 46,   # Tall Grass (1.20+ rename of the above)
    "minecraft:tall_grass": 46,    # Tall Grass (2-tall variant, same block)
    "minecraft:cactus": 47,        # Cactus

    # --- Functional / structural blocks that already exist as our own
    # placeable blocks (spawn_block_entity in VoxelWorld.gd) ---
    "minecraft:oak_planks": 13,    # Planks
    "minecraft:crafting_table": 9, # Crafting Table
    "minecraft:furnace": 8,        # Furnace
    "minecraft:farmland": 14,      # Farmland
}

# Block placed for every unmapped, non-air block found during import. Bright
# magenta/black checkerboard in TextureGenerator.gd (row 6, col 0) -- a
# deliberate "missing texture" look so gaps are visually obvious in the
# rendered screenshot, not silently absorbed into a real block's look.
PLACEHOLDER_BLOCK_ID = 90
