extends Node
## Headless telemetry driver for the "narrow-gap walking gets stuck" bug
## (owner playtesting report). Builds a synthetic, perfectly flat 1-block-wide
## corridor high above natural terrain (so world-gen noise/slope can never
## confound the result), teleports the player to its mouth, drives straight
## "move_forward" input through it for a fixed window, and records the
## player's position every physics frame plus a final pass/fail summary.
##
## Corridor geometry (world/voxel coordinates):
##   - A flat STONE (id 3) floor at y = FLOOR_Y, spanning x in [-2, 2],
##     z in [WALL_Z_END - 1, WALL_Z_START + 1].
##   - Two wall columns, 3 blocks tall (y = FLOOR_Y+1 .. FLOOR_Y+3), running
##     the length of the corridor at x = -1 (occupies world x in [-1, 0]) and
##     x = 1 (occupies world x in [1, 2]).
##   - The gap is the untouched cell at x = 0 (occupies world x in [0, 1]) --
##     an exact 1.0-unit-wide slot, open the whole corridor length.
## The player starts centered at x = 0.5 (dead center of the gap) just outside
## the corridor mouth and is driven straight down -Z (the default forward
## direction at yaw 0, matching how Input.get_vector + head.basis resolve
## "move_forward" -- see Player.gd's _apply_horizontal_movement) with no
## strafe input, so it never approaches the walls at an angle.
##
## "passed" = the player's final Z position is beyond the corridor's far end
## (fully traversed the gap); if stuck, Z stays near the mouth / partway in.
##
## Only active with --narrow-gap-demo (see Scripts/Tools/LaunchTest.gd). Same
## "attach under the tree root" pattern as the other *DemoDriver scripts, for
## the same reason (NetworkManager.host_game() detaches LaunchTest's own
## get_tree() by the time these run).

const STONE_ID := 3
const FLOOR_Y := 200 # Comfortably above all natural terrain (max ~128).
const WALL_HEIGHT := 3
const WALL_Z_START := 2   # Corridor mouth (nearest the player's start).
const WALL_Z_END := -7    # Corridor's far wall row (inclusive).
const GAP_X := 0.5        # Center of the open 1-wide cell (x in [0,1]).
const START_Z := 3.0      # Just outside the mouth.
const PASS_Z_THRESHOLD := WALL_Z_END - 1.0 # Must clear past the far end.
const DRIVE_SECONDS := 8.0

var player: CharacterBody3D = null
var voxel_world: Node = null

var _built := false
var _armed := false
var _settle_timer := 0.0
var _t := 0.0
var _log_timer := 0.0
var _start_pos: Vector3 = Vector3.ZERO
var _done := false

func _ready():
	if not OS.get_cmdline_user_args().has("--narrow-gap-demo"):
		queue_free()
		return
	print("[NarrowGapDemo] driver active, waiting for player...")
	_find_player()

func _find_player():
	player = get_tree().get_first_node_in_group("player")
	if not player:
		await get_tree().create_timer(0.2).timeout
		_find_player()
		return
	player.ai_enabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	voxel_world = get_node_or_null("/root/World/VoxelWorld")
	print("[NarrowGapDemo] player found at ", player.global_position,
		" voxel_world=", voxel_world != null)
	# Log which capsule is actually live -- the runtime setup_nodes() fallback
	# (default-radius CapsuleShape3D.new()) only fires if Player is
	# instantiated WITHOUT Player.tscn (Player.gd _ready(): "if not head:
	# setup_nodes()"); the real spawn path (World.gd spawn_player() ->
	# Player.tscn.instantiate()) always has a Head node, so the scene's own
	# CollisionShape3D is what's live here. Recorded so before/after telemetry
	# proves which collider width was actually tested, not assumed.
	if player.collision_shape and player.collision_shape.shape is CapsuleShape3D:
		var shape: CapsuleShape3D = player.collision_shape.shape
		print("[NarrowGapDemo] active collider: CapsuleShape3D radius=", shape.radius, " height=", shape.height)
	else:
		print("[NarrowGapDemo] WARN: no CapsuleShape3D found on player.collision_shape")
	_build_corridor()

func _build_corridor() -> void:
	if not voxel_world:
		print("[NarrowGapDemo] WARN: no VoxelWorld, cannot build corridor")
		return
	# Flat floor, generous margin around the corridor footprint.
	for x in range(-2, 3):
		for z in range(WALL_Z_END - 1, WALL_Z_START + 2):
			voxel_world.set_voxel(Vector3(x, FLOOR_Y, z) + Vector3(0.5, 0.5, 0.5), STONE_ID)
	# Two wall columns with a 1-wide gap at x=0 (world x in [0,1]) between them.
	for z in range(WALL_Z_END, WALL_Z_START + 1):
		for h in range(1, WALL_HEIGHT + 1):
			voxel_world.set_voxel(Vector3(-1, FLOOR_Y + h, z) + Vector3(0.5, 0.5, 0.5), STONE_ID)
			voxel_world.set_voxel(Vector3(1, FLOOR_Y + h, z) + Vector3(0.5, 0.5, 0.5), STONE_ID)
	_built = true
	print("[NarrowGapDemo] corridor built: gap x=[0,1], z=[", WALL_Z_END, ",", WALL_Z_START, "], floor_y=", FLOOR_Y)

	# Teleport the player to the corridor mouth, centered in the gap, standing
	# on the floor. Zero velocity and yaw so the very first driven frame is a
	# clean, straight approach (no leftover fall velocity/rotation from the
	# normal terrain spawn).
	player.global_position = Vector3(GAP_X, FLOOR_Y + 2.0, START_Z)
	player.velocity = Vector3.ZERO
	if player.head:
		player.head.rotation.y = 0.0
	if player.camera:
		player.camera.rotation.x = 0.0
	print("[NarrowGapDemo] player teleported to corridor mouth: ", player.global_position)

func _process(delta):
	if not player or not _built:
		return

	if not _armed:
		# Settle onto the new floor before driving input, same pattern as
		# ShowcaseDemoDriver -- avoids scripting movement mid-fall.
		if player.is_on_floor() and abs(player.velocity.y) < 0.5:
			_settle_timer += delta
		else:
			_settle_timer = 0.0
		if _settle_timer >= 0.4:
			_armed = true
			_start_pos = player.global_position
			Input.action_press("move_forward")
			if get_node_or_null("/root/Telemetry"):
				Telemetry.log_event("narrow_gap_start", {
					"start_x": _start_pos.x, "start_z": _start_pos.z,
					"collider_radius": player.collision_shape.shape.radius if (player.collision_shape and player.collision_shape.shape is CapsuleShape3D) else -1.0,
					"collider_height": player.collision_shape.shape.height if (player.collision_shape and player.collision_shape.shape is CapsuleShape3D) else -1.0,
				})
			print("[NarrowGapDemo] armed, driving forward from ", _start_pos)
		return

	_t += delta

	_log_timer += delta
	if _log_timer >= 0.25:
		_log_timer = 0.0
		print("[NarrowGapDemo] t=", String.num(_t, 2),
			" pos=", player.global_position,
			" vel=", player.velocity,
			" on_floor=", player.is_on_floor())
		if get_node_or_null("/root/Telemetry"):
			Telemetry.log_event("narrow_gap_tick", {
				"t": _t, "x": player.global_position.x, "y": player.global_position.y,
				"z": player.global_position.z,
			})

	if _t >= DRIVE_SECONDS and not _done:
		_done = true
		Input.action_release("move_forward")
		var end_pos: Vector3 = player.global_position
		var distance: float = Vector2(_start_pos.x, _start_pos.z).distance_to(Vector2(end_pos.x, end_pos.z))
		var passed: bool = end_pos.z <= PASS_Z_THRESHOLD
		print("[NarrowGapDemo] SUMMARY start=(", _start_pos.x, ",", _start_pos.z,
			") end=(", end_pos.x, ",", end_pos.z, ") distance=", String.num(distance, 3),
			" passed=", passed)
		if get_node_or_null("/root/Telemetry"):
			Telemetry.log_event("narrow_gap_summary", {
				"start_x": _start_pos.x, "start_z": _start_pos.z,
				"end_x": end_pos.x, "end_z": end_pos.z,
				"distance_travelled": distance,
				"passed": passed,
			})
		await get_tree().create_timer(0.3).timeout
		print("[NarrowGapDemo] done, quitting")
		get_tree().quit()
