# Changelog

All notable changes to VoxelWorldCraft are documented here.

## [0.2.0] - Speedrun update

Five feature branches (biomes, flowers/food, UI polish, tools & building,
movement feel) built in a single "speedrun" session and consolidated into
`main` in one integration pass.

### Added

- **Biomes**: Plains biome (open grassland, sparse flora, rare lone trees)
  completes the 4-biome set alongside Forest/Desert/Tundra. Tundra now
  splits into Snow and Ice patches based on moisture, instead of always
  generating Snow.
- **Flowers & food**: Berry Bush world decoration (harvestable for Berries,
  a new consumable that restores Hunger), plus Blue and Pink decorative
  flowers scattered through Forest biomes. Eating a consumable from the
  hotbar now actually restores Hunger via `PlayerStats` instead of only
  printing to the console.
- **Tools & building**: Held tools now affect block-break speed (pickaxe on
  stone/ore, axe on wood/planks, shovel on dirt/sand, all via a new
  block-category lookup); the wooden tool set (Pickaxe/Shovel/Axe/Hoe) is
  now actually craftable (it previously silently no-opped). Block placement
  now consumes from inventory instead of placing infinitely, and places the
  item's correct declared block (fixing Sand/Snow, which reuse different
  item vs. block ids). Added a Sticks crafting recipe (2 Planks -> 4
  Sticks).
- **UI polish**: Bright, chunky HUD overlay -- health and hunger bars with
  icons, hotbar, and a crosshair -- replacing the old bare `ProgressBar`
  placeholders.
- **Movement feel**: Acceleration/friction-based movement (replacing
  instant-snap velocity), asymmetric jump gravity (floaty rise / snappy
  fall), coyote time, jump buffering, sprint (Shift) with a matching FOV
  kick, speed-scaled head-bob, and light mouse-look smoothing. All movement
  constants are `@export`ed for tuning from the Inspector.

### Fixed

- **Item id collision**: `feat/biomes` and `feat/flowers-food` independently
  claimed item/block id 52 for two different blocks (Ice vs. Berry Bush).
  Berry Bush was reassigned to id 55 during integration; Ice keeps 52. All
  references (`ItemDatabase.gd`, `Chunk.gd` terrain generation + texture
  atlas mapping, `Player.gd` harvest check) were updated consistently.

### Version

- `project.godot` `config/version` bumped to `0.2.0`.

## [0.1.0] - Prototype

Initial voxel world prototype: chunked terrain generation across four
biomes (Forest/Desert/Tundra/base), block break/place, a basic inventory
and crafting system, mob/villager entities, save system, and a first-person
player controller.
