extends Node
## Headless verification/showcase driver for the Torch + Sheep content
## (and the iron/gold/copper/amethyst/bucket additions alongside them).
## Mirrors Wave2DemoDriver.gd's convention: a pure-logic self-check that
## needs no rendering (runs under plain `godot --headless ... --
## --torchsheep-demo`, dummy renderer, no Xvfb) plus a scripted in-world
## timeline (place a torch, spawn a sheep in front of the player) for an
## actual recorded/screenshotted clip via Xvfb, same as the wave2/movement
## drivers.
##
## Only active with --torchsheep-demo on the command line (see
## Scripts/Tools/LaunchTest.gd, which instantiates this under the scene
## root).

var player: CharacterBody3D = null
var voxel_world = null
var _t: float = 0.0
var _done_steps: Dictionary = {}

const DISPLAY_FORWARD := Vector3(0, 0, -1)
const ALTITUDE_LIFT := 10.0
var _hold_altitude_y: float = 0.0
var _holding_altitude: bool = false

func _ready():
	if not OS.get_cmdline_user_args().has("--torchsheep-demo"):
		queue_free()
		return
	print("[TorchSheepDemo] driver active")
	_self_check()
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
	print("[TorchSheepDemo] player + voxel_world found, starting scripted timeline")

func _process(delta):
	if not player or not voxel_world:
		return
	_t += delta

	if _holding_altitude:
		player.velocity.y = 0
		player.global_position.y = _hold_altitude_y

	if _t >= 0.3 and not _done_steps.has("frame_camera"):
		_done_steps["frame_camera"] = true
		_frame_camera()

	if _t >= 0.5 and not _done_steps.has("place_torch"):
		_done_steps["place_torch"] = true
		_place_torch_display()

	if _t >= 0.8 and not _done_steps.has("spawn_sheep"):
		_done_steps["spawn_sheep"] = true
		_spawn_sheep_display()

	if _t >= 1.2 and not _done_steps.has("runtime_checks"):
		_done_steps["runtime_checks"] = true
		_runtime_world_checks()

	# Safety self-terminate well beyond any recorded clip length, so a
	# plain log-only run (no --write-movie) exits on its own.
	if _t >= 40.0 and not _done_steps.has("quit"):
		_done_steps["quit"] = true
		print("[TorchSheepDemo] t=", String.num(_t, 2), " safety timeout, quitting")
		get_tree().quit()

func _frame_camera() -> void:
	if player.camera:
		player.camera.rotation.x = deg_to_rad(-8.0)
	if player.head:
		player.head.rotation.y = 0.0

	_hold_altitude_y = player.global_position.y + ALTITUDE_LIFT
	player.global_position.y = _hold_altitude_y
	_holding_altitude = true
	print("[TorchSheepDemo] t=", String.num(_t, 2), " camera framed, lifted to y=", _hold_altitude_y)

# Places a Torch directly in front of the player via VoxelWorld.set_voxel()
# -- the same call Player.gd's real placement path uses -- so it's
# guaranteed on-camera for a recorded clip, and darkens the sky so the
# torchlight is visually obvious rather than washed out by daylight.
func _place_torch_display() -> void:
	var pos = player.global_position + DISPLAY_FORWARD * 3.0 + Vector3(0, -1.0, 0)
	voxel_world.set_voxel(pos, 56) # Torch
	var time_cycle = get_node_or_null("/root/World/TimeCycle")
	if time_cycle and time_cycle.sun:
		time_cycle.sun.light_energy = 0.0 # Force night so the torch's light is visibly the light source
	print("[TorchSheepDemo] t=", String.num(_t, 2), " placed Torch at ", pos, ", forced night for contrast")

func _spawn_sheep_display() -> void:
	var scene = load("res://Scenes/Sheep.tscn")
	if not scene:
		print("[TorchSheepDemo] WARNING: could not load Sheep.tscn")
		return
	var sheep = scene.instantiate()
	sheep.position = player.global_position + DISPLAY_FORWARD * 3.0 + Vector3(1.5, -1.0, 0)
	get_tree().current_scene.add_child(sheep)
	print("[TorchSheepDemo] t=", String.num(_t, 2), " spawned Sheep at ", sheep.position)

# Confirms, at runtime (not just parse-time), that the placed torch's
# block-entity actually exists with a lit OmniLight3D, and that the world
# has zero solid voxel_data at that cell (proving the "no double-cube"
# design in VoxelWorld.set_voxel actually behaves as commented).
func _runtime_world_checks() -> void:
	var pos = player.global_position + DISPLAY_FORWARD * 3.0 + Vector3(0, -1.0, 0)
	var pos_i = Vector3i(floor(pos.x), floor(pos.y), floor(pos.z))

	var entity = voxel_world.get_block_entity(pos_i)
	var ok_entity = entity != null and is_instance_valid(entity)
	print("[TorchSheepDemo] CHECK torch block-entity spawned: ", "PASS" if ok_entity else "FAIL")

	var light: OmniLight3D = null
	if ok_entity:
		light = entity.get_node_or_null("Light")
	var ok_light = light != null and light.light_energy > 0.0
	print("[TorchSheepDemo] CHECK torch OmniLight3D present with energy>0: ", "PASS" if ok_light else "FAIL",
		" (energy=", light.light_energy if light else "n/a", ", range=", light.omni_range if light else "n/a", ")")

	var block_type = player.get_block_at(voxel_world, pos)
	var ok_no_cube = block_type == 0
	print("[TorchSheepDemo] CHECK torch cell has NO solid voxel_data (block_type==0, no double-cube): ",
		"PASS" if ok_no_cube else "FAIL (block_type=%d)" % block_type)

	var sheep_nodes = get_tree().get_nodes_in_group("animals")
	var ok_sheep = sheep_nodes.size() > 0
	print("[TorchSheepDemo] CHECK sheep entity present in 'animals' group: ", "PASS" if ok_sheep else "FAIL")
	if ok_sheep:
		var s = sheep_nodes[0]
		print("[TorchSheepDemo] CHECK sheep has take_damage(): ", "PASS" if s.has_method("take_damage") else "FAIL")
		print("[TorchSheepDemo] CHECK sheep health=", s.health if "health" in s else "n/a")

# Pure ItemDatabase/content self-check -- no world/player needed, runs
# immediately (same idiom as Wave2DemoDriver's _self_check_ore_table).
func _self_check() -> void:
	var checks = {
		"Torch (56) registered as BLOCK": ItemDatabase.get_item(56) != null and ItemDatabase.get_item(56).type == 0,
		"Wool (71) registered": ItemDatabase.get_item(71) != null,
		"Mutton (72) registered as CONSUMABLE": ItemDatabase.get_item(72) != null and ItemDatabase.get_item(72).type == 3,
		"Raw Iron (62) registered": ItemDatabase.get_item(62) != null,
		"Iron Ingot (63) registered": ItemDatabase.get_item(63) != null,
		"Gold Ingot (64) registered": ItemDatabase.get_item(64) != null,
		"Copper Ingot (65) registered": ItemDatabase.get_item(65) != null,
		"Amethyst Shard (66) registered": ItemDatabase.get_item(66) != null,
		"Amethyst Ore (85) registered as BLOCK": ItemDatabase.get_item(85) != null and ItemDatabase.get_item(85).type == 0,
		"Amethyst Ore (85) is pickaxe category": ItemDatabase.get_block_category(85) == "pickaxe",
		"Bucket (67) registered": ItemDatabase.get_item(67) != null,
		"Water Bucket (68) registered": ItemDatabase.get_item(68) != null,
		"Lava Bucket (69) registered": ItemDatabase.get_item(69) != null,
	}
	var pass_count = 0
	for label in checks:
		var ok = checks[label]
		if ok: pass_count += 1
		print("[TorchSheepDemo] CHECK ", label, ": ", "PASS" if ok else "FAIL")
	print("[TorchSheepDemo] self-check: ", pass_count, "/", checks.size(), " passed")

	# TorchBlock.tscn / Sheep.tscn actually instantiate cleanly (scene
	# resource is valid, script attaches, expected child nodes exist) --
	# catches broken .tscn resources that --headless --import's parse pass
	# alone would not (a scene can parse as valid Godot resource syntax and
	# still fail to reference nodes correctly at instantiate time).
	var torch_scene = load("res://Scenes/Blocks/TorchBlock.tscn")
	var torch_inst = torch_scene.instantiate() if torch_scene else null
	var torch_ok = torch_inst != null and torch_inst.get_node_or_null("Light") != null
	print("[TorchSheepDemo] CHECK TorchBlock.tscn instantiates with a Light node: ", "PASS" if torch_ok else "FAIL")
	if torch_inst: torch_inst.queue_free()

	var sheep_scene = load("res://Scenes/Sheep.tscn")
	var sheep_inst = sheep_scene.instantiate() if sheep_scene else null
	var sheep_ok = sheep_inst != null and sheep_inst.has_method("take_damage")
	print("[TorchSheepDemo] CHECK Sheep.tscn instantiates with take_damage(): ", "PASS" if sheep_ok else "FAIL")
	if sheep_inst: sheep_inst.queue_free()
