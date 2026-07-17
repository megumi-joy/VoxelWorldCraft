# Changelog

All notable changes to VoxelWorldCraft are documented here.

## [Unreleased] - Wave 2: minerals + Field Journal

The naturalist-fantasy direction: the core loop is observe -> identify ->
catalog, not mine-craft-fight-survive. This wave lays the Field Journal
(codex) foundation and adds mineral ore species to identify. Fauna/animals
are explicitly out of scope for this wave (a later wave).

### Added

- **Mineral ores**: five new real-world minerals as minable ore blocks --
  Copper Ore, Gold Ore, Quartz, Hematite, and Malachite Ore -- alongside the
  existing Coal/Iron. Each has a distinct procedurally-generated texture and
  spawns with plausible depth/biome gating (see `Chunk.gd`'s `ORE_TABLE`):
  Gold is very deep and rare; Hematite is gated to Desert (its rust-red iron
  oxide color also tints desert rock); Quartz favors the two "hard ground"
  biomes (Desert/Tundra); Malachite forms in shallow oxidized zones gated to
  Forest/Plains; Copper is shallow-mid and common everywhere. All five mine
  with the existing pickaxe break-speed category.
- **Field Journal**: a toggleable panel (default key `J`) cataloging two
  categories -- Plants and Minerals -- with real educational facts per
  species (botanical family/habitat/edibility for plants; geological
  category/Mohs hardness/common use for minerals). Entries are locked
  ("??? -- undiscovered") until the player has collected that species at
  least once. Seeded with the three existing plants (Berry Bush, Blue
  Flower, Pink Flower) plus the five new minerals.
- **Discovery wiring**: picking up an item for the first time (mining,
  crafting, trading, ...) can unlock its Field Journal entry --
  `Inventory.item_picked_up` -> `PlayerStats.discover_item()` -> a toast via
  the existing message banner. Breaking a mineral or a decorative flower
  (Blue/Pink Flower) now actually yields itself into the inventory, which
  previously silently gave nothing for anything other than the Berry Bush's
  special-cased Berries harvest.

### Changed

- **HUD scale/layout**: the always-on HUD (health/hunger bars, hotbar,
  AI toggle button, gold display) was resized and re-anchored to a compact
  corner-overlay scale so the voxel world dominates the frame instead of a
  large banner, and the hotbar's slot size now adapts to the viewport width
  at runtime so the same layout works in both landscape and portrait
  orientations (`project.godot` also gained `canvas_items` stretch mode so
  HUD scale stays consistent across render resolutions). The gold display
  changed from a bare "G: 0" label to a small rounded coin-icon chip.
  Note for reviewers: this HUD sizing is expected to be revisited once the
  in-progress UI-variant exploration lands -- treat these files as a
  functional baseline, not the final look.

### Fixed

- **Health/hunger bar fill notch**: the bar fill's rounded corners on both
  edges produced a visible crescent-shaped "bite" out of the bar at any
  partial (non-0/100) value. Only the leading edge is rounded now.

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
