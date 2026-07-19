# VoxelWorldCraft

A Minecraft-like voxel sandbox prototype built in Godot 4.3: chunked terrain
generation, first-person movement, block break/place, crafting, and a
lightweight multiplayer layer.

Current version: **0.2.0** ("Speedrun update" -- see [CHANGELOG.md](CHANGELOG.md)).

## Features

### World generation & biomes
- Chunked infinite terrain (16x16 columns) with noise-based height, ore
  veins, and structure scattering (trees, cacti).
- Four biomes: **Forest** (dense trees, flowers, tall grass, Berry Bushes),
  **Plains** (open grassland, sparse flora, rare lone trees), **Desert**
  (sand, cacti), and **Tundra** (Snow and Ice, split by moisture).
- **Mineral ores** (wave 2): Coal, Iron, Copper, Gold, Quartz, Hematite, and
  Malachite, each depth- and (for some) biome-gated for plausible geology --
  see `Chunk.gd`'s `ORE_TABLE`. All mine with the pickaxe break-speed
  category.

### Field Journal (wave 2)
- A naturalist-fantasy codex, toggled with **J**: two categories, Plants and
  Minerals, each entry showing real facts (botanical family/habitat/edible?
  for plants; geological category/Mohs hardness/common use for minerals).
- Entries start locked ("??? -- undiscovered") and unlock the first time the
  player collects that species -- mining a mineral, picking a flower, or
  harvesting Berries. See `CodexDatabase.gd` (entry data) and
  `PlayerStats.discover_item()` / `Inventory.item_picked_up` (discovery
  wiring).

### Flowers & food
- Berry Bush world decoration, harvestable by breaking it for **Berries** --
  a consumable that restores Hunger.
- Blue and Pink decorative flowers alongside the existing Red/Yellow set.
- Eating a consumable from the hotbar restores Hunger via `PlayerStats`.

### Tools & building
- Held tools affect block-break speed: pickaxe on stone/ore, axe on
  wood/planks, shovel on dirt/sand/farmland. Bare hands (or the wrong tool)
  break slower.
- The full wooden tool set (Pickaxe, Shovel, Axe, Hoe) is craftable.
- Block placement consumes from inventory and places the item's correct
  underlying block (handles items that reuse a different block id, like
  Sand/Snow).
- Crafting recipes: Wood -> Planks, Planks -> Crafting Table, Wheat ->
  Bread, Planks -> wooden tools, Planks -> Sticks.

### UI
- Chunky HUD: health and hunger bars with icons, hotbar, and a crosshair.

### Movement feel
- Acceleration/friction-based movement (not an instant velocity snap),
  with reduced air control while airborne.
- Asymmetric jump gravity (floaty rise, snappy fall), coyote time (jump
  briefly after leaving a ledge), and jump buffering (a jump press just
  before landing still fires).
- Sprint (Shift) with a matching camera FOV kick.
- Speed-scaled head-bob that fades to neutral when idle or airborne.
- Light mouse-look smoothing.
- All of the above are `@export`ed on `Player.gd` for tuning from the
  Inspector.

### Also included
- Basic inventory, save system, mobs/villagers, bed/furnace/crafting-table
  block entities, a simple chat UI, and a headless `AutoTester` /
  `MovementDemoDriver` / `Wave2DemoDriver` set for automated verification
  (see below).

## Running headless (verification / CI)

Godot is not installed on the host; all headless verification runs inside
the `barichello/godot-ci:4.3`-based container via podman (or Docker). See
`tools/record_movie_maker.sh` for the gameplay-recording recipe.

- **Import / parse check**: `godot --headless --path . --import`
- **Automated crafting/tools smoke test**: `godot --headless --path .
  Scenes/LaunchTest.tscn --run-tests` (drives `Scripts/Testing/AutoTester.gd`
  -- gathers wood, crafts planks/table/tools, logs to
  `playthrough_log.json`). Note: pass `--run-tests` as a direct engine
  argument, *not* after a `--` separator -- `AutoTester.gd` checks
  `OS.get_cmdline_args()`, which does not include user args after `--`.
- **Movement-feel demo**: `godot --path . Scenes/LaunchTest.tscn --
  --movement-demo` (drives `Scripts/Testing/MovementDemoDriver.gd` --
  scripted walk/sprint/jump/strafe timeline through the real manual-input
  code path; opt-in flags after `--` land in `OS.get_cmdline_user_args()`).
- **Wave 2 (minerals + Field Journal) demo/verification**: `godot --headless
  --path . Scenes/LaunchTest.tscn -- --wave2-demo` (drives
  `Scripts/Testing/Wave2DemoDriver.gd` -- runs a statistical self-check of
  the ore-generation table, places real mineral blocks via
  `VoxelWorld.set_voxel()` and mines one back out, grants a handful of
  plant/mineral pickups through the real `Inventory.add_item()` path to
  exercise Field Journal discovery, then opens the Field Journal
  programmatically via `FieldJournalUI.open()` -- everything logged with a
  `[Wave2Demo]` prefix). This is also the scene/flag combo used with
  `tools/record_movie_maker.sh` to capture the wave-2 showcase clip.
- **Torch + Sheep demo/verification**: `godot --headless --path .
  Scenes/LaunchTest.tscn -- --torchsheep-demo` (drives
  `Scripts/Testing/TorchSheepDemoDriver.gd` -- self-checks that Torch/
  Sheep/iron-chain/gold/copper/Amethyst/Bucket items are all registered in
  `ItemDatabase` and that `TorchBlock.tscn`/`Sheep.tscn` actually
  instantiate, then places a real Torch via `VoxelWorld.set_voxel()` and
  spawns a real Sheep in front of the player and asserts at runtime that
  the torch's block-entity has a lit `OmniLight3D` and that its cell has
  no solid `voxel_data` (proving the "no double-cube" placement design
  actually behaves as intended) -- everything logged with a
  `[TorchSheepDemo]` prefix).
