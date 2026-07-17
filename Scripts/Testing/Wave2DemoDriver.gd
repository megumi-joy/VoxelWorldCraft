extends Node
## Headless wave-2 verification/showcase driver: minerals + Field Journal +
## discovery wiring, all driven programmatically (not via real keypresses --
## Godot's --write-movie headless capture has no keyboard). Mirrors
## MovementDemoDriver.gd's opt-in-flag convention.
##
## Only active with --wave2-demo on the command line (see
## Scripts/Tools/LaunchTest.gd, which instantiates this under the scene
## root).
##
## What it proves, all through REAL code paths (not test-only shortcuts):
## 1. Ore generation logic: a quick statistical self-check of Chunk.pick_ore()
##    across depth/biome combos (pure function, no world needed) -- confirms
##    every wave-2 ore id is reachable under its documented depth/biome gate.
## 2. "A mineral generates + is minable": places real mineral blocks via
##    VoxelWorld.set_voxel() (the same function Player.gd's block-breaking
##    and placement use) directly in front of the player so they're
##    guaranteed on-camera regardless of where ore actually rolled
##    underground, then removes one the same way breaking would.
## 3. Discovery wiring: grants a few items via the real Inventory.add_item()
##    path -- the same call mining/crafting/trading use -- which fires
##    Inventory.item_picked_up -> PlayerStats.discover_item() ->
##    Player.show_message() toast, exactly like a real pickup would.
## 4. The Field Journal: opens via FieldJournalUI.open() (the same public
##    API a headless verifier or a future non-keyboard input source would
##    use), showing a mix of unlocked (just-discovered) and still-locked
##    ("??? -- undiscovered") entries in both categories.

var player: CharacterBody3D = null
var voxel_world = null
var _t: float = 0.0
var _done_steps: Dictionary = {} # step name -> true, so each runs once

# Fixed world-axis facing (not the player's spawn-time head rotation, which
# is deterministic but arbitrary) and a held altitude for the display
# window -- see _frame_camera(). Both the mineral placement and the mining
# step reuse these so they stay consistent with what's actually on-camera.
const DISPLAY_FORWARD := Vector3(0, 0, -1)
const DISPLAY_RIGHT := Vector3(1, 0, 0)
var _hold_altitude_y: float = 0.0
var _holding_altitude: bool = false

func _ready():
	# Args after "--" land in OS.get_cmdline_user_args(), not
	# OS.get_cmdline_args() (which only holds engine-recognized args).
	if not OS.get_cmdline_user_args().has("--wave2-demo"):
		queue_free()
		return
	print("[Wave2Demo] driver active, waiting for player...")
	_self_check_ore_table()
	_find_player()

func _find_player():
	player = get_tree().get_first_node_in_group("player")
	voxel_world = get_node_or_null("/root/World/VoxelWorld")
	if not player or not voxel_world:
		await get_tree().create_timer(0.2).timeout
		_find_player()
		return
	player.ai_enabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("[Wave2Demo] player + voxel_world found, starting scripted timeline")

func _process(delta):
	if not player or not voxel_world:
		return
	_t += delta

	# Counteract gravity during the display window -- the player would
	# otherwise fall away from the elevated spot _frame_camera() puts them
	# at (CharacterBody3D's own _physics_process still applies gravity every
	# physics tick regardless of what this driver does in _process).
	if _holding_altitude:
		player.velocity.y = 0
		player.global_position.y = _hold_altitude_y

	if _t >= 0.3 and not _done_steps.has("frame_camera"):
		_done_steps["frame_camera"] = true
		_frame_camera()

	if _t >= 0.5 and not _done_steps.has("place_minerals"):
		_done_steps["place_minerals"] = true
		_place_mineral_display()

	if _t >= 0.8 and not _done_steps.has("grant_discoveries"):
		_done_steps["grant_discoveries"] = true
		_grant_partial_discoveries()

	if _t >= 1.2 and not _done_steps.has("mine_one"):
		_done_steps["mine_one"] = true
		_mine_one_display_block()

	if _t >= 1.8 and not _done_steps.has("open_journal"):
		_done_steps["open_journal"] = true
		_open_journal()

	# Safety self-terminate, WAY beyond any clip length this driver is
	# actually used to record (~15-20s) -- exists only so a plain log-only
	# verification run (godot --headless ... -- --wave2-demo, no
	# --write-movie) doesn't need an external `timeout` wrapper to exit. When
	# recording video, --write-movie's own --quit-after N frame count is what
	# actually terminates the process; this threshold must stay well above
	# that so it never fires mid-recording and truncates the clip.
	if _t >= 40.0 and not _done_steps.has("quit"):
		_done_steps["quit"] = true
		print("[Wave2Demo] t=", String.num(_t, 2), " safety timeout, quitting")
		get_tree().quit()

# Points the player at a deterministic world direction, lifts them well
# above the local terrain, and holds that altitude for the rest of the clip
# (see the gravity-counteraction in _process()). The very first render of
# this driver placed the mineral display relative to the player's own
# spawn-time facing/height and got unlucky: spawn landed right next to a
# local terrain bump, so the display ended up out of frame / occluded by a
# close dirt wall. Elevating well above any nearby terrain and using a fixed
# facing direction (not "wherever the player happens to be looking")
# guarantees the display is in open air, on-camera, every run -- regardless
# of where world-gen noise puts the spawn column.
const ALTITUDE_LIFT := 10.0

func _frame_camera() -> void:
	if player.camera:
		player.camera.rotation.x = deg_to_rad(-12.0)
	if player.head:
		player.head.rotation.y = 0.0 # face DISPLAY_FORWARD (world -Z)

	_hold_altitude_y = player.global_position.y + ALTITUDE_LIFT
	player.global_position.y = _hold_altitude_y
	_holding_altitude = true

	print("[Wave2Demo] t=", String.num(_t, 2), " camera pitched to -12 deg, lifted to y=", _hold_altitude_y)

# Places one of each of the 5 wave-2 mineral ores in a row directly in front
# of the player at eye height, via the same VoxelWorld.set_voxel() call
# Player.gd's own block placement uses -- guarantees they're on-camera
# without depending on where ore actually rolled underground (real ore is
# depth-gated to y<75, well below the ~y98 default spawn height).
const DISPLAY_MINERAL_IDS = [80, 81, 82, 83, 84] # Copper, Gold, Quartz, Hematite, Malachite

func _place_mineral_display() -> void:
	var origin = player.global_position + Vector3(0, -0.3, 0)
	var forward = DISPLAY_FORWARD
	var right = DISPLAY_RIGHT

	for i in range(DISPLAY_MINERAL_IDS.size()):
		var offset = forward * 3.0 + right * (i - 2) * 1.0
		var pos = origin + offset
		voxel_world.set_voxel(pos, DISPLAY_MINERAL_IDS[i])
	print("[Wave2Demo] t=", String.num(_t, 2), " placed mineral display row: ", DISPLAY_MINERAL_IDS)

# Grants items for SOME (not all) plant/mineral species via the real
# Inventory.add_item() pickup path, so the Field Journal shows a mix of
# unlocked and still-"??? -- undiscovered" entries in the same clip --
# proving both visual states render correctly, not just the all-unlocked
# happy path.
func _grant_partial_discoveries() -> void:
	var inv = player.get_node_or_null("Inventory")
	if not inv:
		print("[Wave2Demo] WARNING: no Inventory found, cannot grant items")
		return
	inv.add_item(70, 1) # Berries -> discovers Berry Bush
	inv.add_item(53, 1) # Blue Flower -> discovers Blue Flower
	# Pink Flower (54) intentionally left undiscovered.
	inv.add_item(80, 1) # Copper Ore -> discovers Copper Ore
	inv.add_item(81, 1) # Gold Ore -> discovers Gold Ore
	inv.add_item(82, 1) # Quartz -> discovers Quartz
	# Hematite (83) / Malachite Ore (84) intentionally left undiscovered,
	# even though both are visible in the placed display row above --
	# seeing a mineral in the world isn't the same as having identified it.
	print("[Wave2Demo] t=", String.num(_t, 2), " granted partial discoveries, stats.discovered_species=",
		player.stats.discovered_species if player.stats else "N/A")

# Breaks one of the placed display blocks the same way a real left-click
# would (VoxelWorld.set_voxel to 0), proving the placed minerals are
# actually minable, not just decorative.
func _mine_one_display_block() -> void:
	var origin = player.global_position + Vector3(0, -0.3, 0)
	var pos = origin + DISPLAY_FORWARD * 3.0 # the center (Quartz) slot
	var before = player.get_block_at(voxel_world, pos)
	voxel_world.set_voxel(pos, 0)
	var after = player.get_block_at(voxel_world, pos)
	print("[Wave2Demo] t=", String.num(_t, 2), " mined display block at ", pos,
		" block_type before=", before, " after=", after)

func _open_journal() -> void:
	var journal = player.get_node_or_null("HUD/FieldJournalUI")
	if journal and journal.has_method("open"):
		journal.open()
		print("[Wave2Demo] t=", String.num(_t, 2), " Field Journal opened")
	else:
		print("[Wave2Demo] WARNING: FieldJournalUI not found at HUD/FieldJournalUI")

# Pure-logic statistical check of Chunk.gd's ORE_TABLE / pick_ore(): rolls
# many (y, biome) combinations covering each ore's documented depth/biome
# gate and confirms every wave-2 ore id (plus the pre-existing Coal/Iron)
# actually comes out at least once. Doesn't need a world/player, so it runs
# immediately in _ready() rather than waiting on the timeline above.
func _self_check_ore_table() -> void:
	var chunk_script = load("res://Scripts/World/Chunk.gd")
	var chunk = Node3D.new()
	chunk.set_script(chunk_script)
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	var biomes = ["Forest", "Plains", "Desert", "Tundra"]
	var expected_ids = [5, 6, 80, 81, 82, 83, 84]
	var seen: Dictionary = {}
	var rolls = 0
	for y in range(1, 90):
		for biome in biomes:
			for _i in range(200):
				rolls += 1
				var id = chunk.pick_ore(y, biome, rng)
				if id != 0:
					seen[id] = seen.get(id, 0) + 1

	var missing = []
	for id in expected_ids:
		if not seen.has(id):
			missing.append(id)

	print("[Wave2Demo] ORE_TABLE self-check: ", rolls, " rolls, counts=", seen)
	if missing.is_empty():
		print("[Wave2Demo] ORE_TABLE self-check: PASS -- all expected ore ids (", expected_ids, ") appeared")
	else:
		print("[Wave2Demo] ORE_TABLE self-check: FAIL -- missing ids ", missing)

	chunk.queue_free()
