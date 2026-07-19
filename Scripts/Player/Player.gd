extends CharacterBody3D

# --- Movement feel tuning --------------------------------------------------
# Exported so game-feel can be iterated on from the Inspector. Defaults aim
# for a snappy, weighty first-person feel (Minecraft-like), not floaty or
# robotic-instant.

@export_group("Speed")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0

@export_group("Acceleration / Friction")
# Ground accel/friction: responsive but not instant (a hair of slide when
# stopping). Air accel/friction are lower -- reduced air control, momentum
# carries like a real jump arc instead of steering on a dime mid-air.
@export var ground_acceleration: float = 22.0
@export var ground_friction: float = 18.0
@export var air_acceleration: float = 6.0
@export var air_friction: float = 2.0

@export_group("Jump")
@export var jump_velocity: float = 4.5
# Asymmetric gravity: floaty-ish on the way up, snappy on the way down.
# This one lever does more for jump "feel" than the jump height itself --
# symmetric gravity at this same apex reads as mushy/floaty.
@export var rise_gravity_scale: float = 0.85
@export var fall_gravity_scale: float = 1.6
# Coyote time: jump still allowed briefly after walking off a ledge.
@export var coyote_time: float = 0.1
# Jump buffering: a jump press shortly before landing still fires on landing.
@export var jump_buffer_time: float = 0.12

@export_group("Sprint FOV Kick")
@export var sprint_fov_kick_deg: float = 8.0
@export var fov_lerp_speed: float = 8.0

@export_group("Head Bob")
@export var head_bob_enabled: bool = true
@export var head_bob_amplitude: float = 0.045
@export var head_bob_side_amplitude: float = 0.02
# Radians of bob-cycle progressed per second per 1 unit/s of horizontal speed.
@export var head_bob_frequency: float = 2.2
@export var head_bob_smoothing: float = 10.0

@export_group("Look")
# 0 = raw/instant mouse look, closer to 1 = smoother but laggier. Kept low so
# it only shaves off jitter rather than adding perceptible input delay.
@export_range(0.0, 0.95) var look_smoothing: float = 0.3
@export var mouse_sensitivity: float = 0.003

@export_group("Step Climb")
# CharacterBody3D has no built-in stair-stepping -- move_and_slide() treats a
# single 1-block-tall voxel ledge exactly like a wall. In a voxel world that
# is nearly every hill, grass tuft, or door sill, so without this the player
# walks into it and stops dead: reads to a player as "getting stuck" even
# though nothing is actually wrong, just an un-climbable ledge. Slightly
# above one full voxel (1.0) so a full single-block step still clears with a
# hair of margin. See _apply_step_climb() below (Mob.gd has its own
# jump-based version of this same problem -- "Obstacle Avoidance (Auto
# Jump)" -- which is corroborating evidence ledges are a known snag here).
@export var step_height: float = 1.1

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Movement-feel runtime state (see _ready for init, _physics_process/helpers
# below for use).
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _bob_time: float = 0.0
var _camera_base_local_pos: Vector3 = Vector3.ZERO
var _base_fov: float = 75.0
var _smoothed_look_delta: Vector2 = Vector2.ZERO

# Throttled "[Шаги]" (footsteps) sound-subtitle caption -- see
# SoundCaptions.gd. Fires at most once per FOOTSTEP_CAPTION_INTERVAL while
# actually walking/sprinting on the ground, not every physics frame (there's
# no footstep audio to caption yet, just the accessibility cue, so a steady
# "you are currently walking" pulse is enough -- once per real footfall
# would need actual foot-cycle timing this game doesn't have).
const FOOTSTEP_CAPTION_INTERVAL := 1.8
var _footstep_caption_cooldown: float = 0.0

# Respawn XZ column used both for the normal death respawn and the void-fall
# catch below -- kept as one constant so both paths can never drift apart.
# Y is deliberately NOT a constant: it used to be hardcoded to 100 (so every
# single death respawned the player ~30-40 units in the sky, however far
# above whatever the terrain height happens to be at this column, and they'd
# fall for a couple of seconds before regaining control) -- confusing, and
# very likely a real chunk of "непонятно че респавнился" (unclear respawn).
# See _compute_respawn_position() below, which mirrors the exact
# ground-height formula World.gd's spawn_player() uses for the player's very
# first spawn, so a death respawn lands gently on the surface the same way.
const RESPAWN_XZ := Vector2(0, 0)

# Void-fall catch: if the player ends up below all real terrain (bedrock is
# always y=0, see Chunk.gd's generate_data()) -- e.g. walking off the edge
# of a not-yet-generated chunk, or any other way to end up outside the
# collidable world -- respawn instead of free-falling forever. Comfortably
# below bedrock so it never fires from legitimate terrain/caves.
const VOID_FALL_Y := -10.0
# Guards against re-triggering every physics frame while still below the
# threshold; cleared once _on_death() respawns the player back above it.
var _void_fall_handled: bool = false

# Mouse-capture UX state (see _unhandled_input/_notification below). True
# only while the player deliberately released the cursor via Esc -- lets a
# click back into the game view re-capture without fighting a menu/panel
# that owns MOUSE_MODE_VISIBLE for its own reasons (inventory, settings, ...).
var _manually_released_mouse: bool = false

# Gameplay actions that must never be left "stuck" pressed -- see
# _release_movement_input() / _notification().
const MOVEMENT_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right", "jump", "sprint"]

# Control-panel nodes under Player.tscn's "HUD" CanvasLayer (see Scenes/
# Player.tscn) that each own their own MOUSE_MODE_VISIBLE/CAPTURED toggle on
# open/close (InventoryUI.gd, SettingsPanel.gd, ...). Used by _is_menu_open()
# so the click-to-recapture and focus-in-recapture logic below never yanks
# the cursor back while one of these is actually open.
const MENU_PANEL_NAMES := ["InventoryUI", "CraftingUI", "FurnaceUI", "TradingUI", "SettingsPanel", "FieldJournalUI"]

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var raycast = $Head/Camera3D/RayCast3D
# The player's capsule collider. May resolve to null in the setup_nodes()
# fallback path (that CollisionShape3D is created later than this @onready
# resolves) -- callers null-check it defensively.
@onready var collision_shape = get_node_or_null("CollisionShape3D")

@onready var stats = $PlayerStats # Ensure this matches Scene tree

@onready var hotbar_ui = $HUD/HotbarUI
@onready var inventory = get_node_or_null("Inventory")
var selected_block_id: int = 1 # Default Dirt

# Blocks that yield themselves (item id == block id) into the inventory when
# mined, feeding Field Journal discovery. See manual_interaction_check().
const COLLECTIBLE_BLOCK_IDS = [53, 54, 80, 81, 82, 83, 84] # Blue/Pink Flower, Copper/Gold/Quartz/Hematite/Malachite

func _ready():
	# Lock + hide the cursor and start feeding InputEventMouseMotion.relative
	# to the camera -- works in windowed mode exactly like fullscreen (Godot's
	# MOUSE_MODE_CAPTURED isn't fullscreen-gated). This alone used to be
	# undone almost instantly in real play: Scripts/Testing/AutoTester.gd is
	# an always-loaded autoload whose _input() forced the mouse back to
	# MOUSE_MODE_VISIBLE on the player's very first keypress or click, even
	# outside --run-tests bot runs. That's fixed at the source now (AutoTester
	# gates its whole _input() on the bot actually being active), so this
	# capture sticks.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("player")

	# The interaction ray must never hit the player's own body. Aiming
	# steeply down made it self-hit this CharacterBody3D, which fell into
	# manual_interaction_check()'s "collider has take_damage()" branch and
	# called self.take_damage() every frame -> a death loop with
	# cause="damage" (the real "копание вниз убивает"). Excluding self also
	# ROUTES the down-ray to the terrain below, so _process_mining() targets
	# the block under you and digging straight down works.
	if raycast:
		raycast.add_exception(self)

	if stats:
		stats.died.connect(_on_death)

		# Connect HUD Bars. "PlayerHUD" is the Scenes/HUD.tscn instance nested
		# inside the "HUD" CanvasLayer (see Scenes/Player.tscn).
		var hud = get_node_or_null("HUD/PlayerHUD")
		if hud:
			if hud.get("health_bar"):
				stats.health_changed.connect(func(val, max_val): hud.health_bar.value = (val / max_val) * 100)
			
			if hud.get("hunger_bar"):
				stats.hunger_changed.connect(func(val, max_val): hud.hunger_bar.value = (val / max_val) * 100)
			
			if hud.get("armor_bar"):
				stats.armor_changed.connect(func(val): hud.armor_bar.value = val) # Armor is literal? Or max 100?
				# Let's assume max 100 for visual.

		# Field Journal discovery: any real item pickup (mining a mineral or
		# a collectible flower, crafting, trading, ...) can unlock a codex
		# entry -- see PlayerStats.discover_item() / CodexDatabase.gd. Toast
		# on a brand-new discovery.
		stats.species_discovered.connect(_on_species_discovered)

	if inventory:
		inventory.item_picked_up.connect(_on_item_picked_up)

	# Setup WASD if not defined
	add_input_mapping("move_forward", KEY_W)
	add_input_mapping("move_backward", KEY_S)
	add_input_mapping("move_left", KEY_A)
	add_input_mapping("move_right", KEY_D)
	add_input_mapping("jump", KEY_SPACE)
	add_input_mapping("sprint", KEY_SHIFT)
	add_input_mapping("inventory", KEY_E)
	add_input_mapping("field_journal", KEY_J)

	# Ensure nodes exist
	if not head:
		setup_nodes()

	# Movement-feel init: capture the camera's authored local position/FOV as
	# the "neutral" values head-bob and the sprint FOV kick animate around and
	# return to (works whether Head/Camera3D came from the scene or the
	# setup_nodes() fallback above).
	if camera:
		_camera_base_local_pos = camera.position
		_base_fov = camera.fov

	# Connect Hotbar
	if hotbar_ui:
		hotbar_ui.on_slot_selected.connect(on_hotbar_select)
		
	# Auto-enable AI if requested via command line
	if OS.get_cmdline_args().has("--ai") or OS.has_feature("headless"):
		ai_enabled = true
		print("--- PLAYER: AI AUTO-ENABLED ---")

func on_hotbar_select(item_id: int):
	# Update selected block
	# Assuming item_id maps to block_id via ItemDatabase, check if block
	# ItemDatabase logic: 
	# Block IDs in VoxelWorld match Item IDs? 
	# ItemDB: 1=Dirt (Block 1), 4=Wood (Block 4), 8=Furnace (Block 8)
	# So we can use item_id directly as block_id for now if it is a block.
	# We should ideally check item type.
	if item_id == 0: return # Empty
	
	# Direct use for prototype
	selected_block_id = item_id

func _on_item_picked_up(id: int, _count: int) -> void:
	if stats:
		stats.discover_item(id)

func _on_species_discovered(_species_key: String, entry: Dictionary) -> void:
	show_message("Discovered: " + str(entry.get("name", "???")))

func add_input_mapping(action, key):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var ev = InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func setup_nodes():
	# Fallback if nodes aren't in the scene tree (e.g. testing)
	head = Node3D.new()
	head.name = "Head"
	head.position.y = 1.7
	add_child(head)
	
	camera = Camera3D.new()
	camera.name = "Camera3D"
	head.add_child(camera)
	
	raycast = RayCast3D.new()
	raycast.name = "RayCast3D"
	raycast.target_position = Vector3(0, 0, -5)
	raycast.enabled = true
	camera.add_child(raycast)
	# Fallback-path twin of _ready()'s exception: this freshly-created ray
	# must also ignore the player's own body (see _ready()). setup_nodes()
	# REPLACES the raycast node, so the exception must be re-added here or
	# it's lost.
	raycast.add_exception(self)
	
	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape = CapsuleShape3D.new()
	col.shape = shape
	add_child(col)
	
	# Visual Body (Simple Capsule)
	var body_mesh = MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	body_mesh.mesh = CapsuleMesh.new()
	add_child(body_mesh)
	
	# Visual Hand (Attached to Camera)
	var hand = MeshInstance3D.new()
	hand.name = "Hand"
	hand.mesh = BoxMesh.new()
	hand.mesh.size = Vector3(0.2, 0.2, 0.5)
	hand.position = Vector3(0.3, -0.3, -0.5)
	camera.add_child(hand)

	var inv = load("res://Scripts/UI/Inventory.gd").new()
	inv.name = "Inventory"
	add_child(inv)
	inventory = inv
	
	# Create basic HUD if missing (defensive fallback for contexts where
	# Player isn't instanced from the full Player.tscn, e.g. isolated tests).
	# Mirrors Player.tscn's real layout: a "HUD" CanvasLayer containing the
	# PlayerHUD overlay (Scenes/HUD.tscn) plus the hotbar, so the node paths
	# used elsewhere in this script ("HUD/PlayerHUD", "HUD/HotbarUI") resolve
	# the same way regardless of which path created them.
	if not has_node("HUD"):
		var hud_layer = CanvasLayer.new()
		hud_layer.name = "HUD"
		add_child(hud_layer)

		var hud_scene = load("res://Scenes/HUD.tscn")
		var player_hud = hud_scene.instantiate()
		player_hud.name = "PlayerHUD"
		hud_layer.add_child(player_hud)

		var hotbar_res = load("res://Scenes/HotbarUI.tscn")
		if hotbar_res:
			var hotbar = hotbar_res.instantiate()
			hotbar.name = "HotbarUI"
			hud_layer.add_child(hotbar)

		var settings_res = load("res://Scenes/SettingsPanel.tscn")
		if settings_res:
			var settings_panel = settings_res.instantiate()
			settings_panel.name = "SettingsPanel"
			settings_panel.visible = false
			hud_layer.add_child(settings_panel)

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		# Mouse-look only while the cursor is actually captured -- otherwise
		# a mouse move on the way to click a HUD/menu button would also spin
		# the camera underneath it. (Touch-drag look bypasses this on purpose
		# via apply_look_delta() directly from TouchControls.gd -- touch has
		# no concept of cursor capture.)
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			apply_look_delta(event.relative)

	if event.is_action_pressed("ui_cancel"): # Escape
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_manually_released_mouse = true
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			_manually_released_mouse = false
		return

	# Click back into the game re-captures the mouse after an Esc release.
	# Only acts on the flag Esc itself sets (not e.g. an inventory panel's own
	# VISIBLE) and only reaches here at all if no menu Control with
	# mouse_filter STOP consumed the click first -- Godot routes GUI input to
	# the scene tree's Controls before _unhandled_input, so an open menu's own
	# clicks never trigger this.
	if _manually_released_mouse and event is InputEventMouseButton and event.pressed \
			and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE and not _is_menu_open():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_manually_released_mouse = false

## True while any of the player's HUD control panels (inventory, crafting,
## furnace, trading, settings, field journal) is open and owns the visible
## cursor -- see MENU_PANEL_NAMES above.
func _is_menu_open() -> bool:
	var hud = get_node_or_null("HUD")
	if not hud:
		return false
	for panel_name in MENU_PANEL_NAMES:
		var panel = hud.get_node_or_null(panel_name)
		if panel and panel.visible:
			return true
	return false

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release_movement_input()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			# Defensive re-assert: some platforms silently drop a
			# MOUSE_MODE_CAPTURED request made while the window doesn't yet
			# have real OS input focus. Re-apply once focus is confirmed
			# regained, but never fight a deliberate Esc release, an open
			# menu, or AI mode (toggle_ai() wants the cursor visible while
			# the bot drives).
			if not _manually_released_mouse and not _is_menu_open() and not ai_enabled:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

## Root cause of "keyboard sticks": if a key's release event arrives while
## the OS window doesn't have focus (alt-tab, clicking another app/the
## taskbar, ...), Godot never sees the key-up and Input.is_action_pressed()
## for that action latches true forever -- WASD/jump/sprint read as still
## held even though the physical key is up, so the player keeps "moving" on
## its own after focus returns. Force every held gameplay action to release
## the instant focus is lost so nothing can latch, and zero the horizontal
## velocity too so movement doesn't keep coasting on the latched input for
## the one physics frame before the release takes effect.
func _release_movement_input() -> void:
	for action in MOVEMENT_ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)
	velocity.x = 0.0
	velocity.z = 0.0

## Rotates the camera by a raw pixel delta, with the same smoothing curve
## mouse-look uses. Shared entry point for mouse motion (above) and
## TouchControls.gd's look-drag area, so touch and mouse camera control are
## identical in feel instead of two parallel implementations.
func apply_look_delta(relative: Vector2) -> void:
	# Light smoothing: blend each raw delta with the previous smoothed delta
	# so small jitter doesn't translate 1:1 into camera shake, while staying
	# responsive (low smoothing weight by default).
	_smoothed_look_delta = _smoothed_look_delta.lerp(relative, 1.0 - look_smoothing)
	head.rotate_y(-_smoothed_look_delta.x * mouse_sensitivity)
	camera.rotate_x(-_smoothed_look_delta.y * mouse_sensitivity)
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

# AI Control
@export var ai_enabled: bool = false # Default to Manual
var ai_target: Node3D = null
var ai_timer: float = 0.0

func _physics_process(delta):
	# --- Jump timers: coyote time (grace period to still jump shortly after
	# walking off a ledge) and jump buffering (a jump press shortly before
	# landing still fires the instant we touch down). Tracked every frame
	# regardless of AI/manual so both feel the same. ---
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
	_jump_buffer_timer -= delta

	# Add the gravity -- asymmetric: floaty-ish rise, snappy fall (see
	# rise_gravity_scale/fall_gravity_scale above for why).
	if not is_on_floor():
		var gravity_scale = rise_gravity_scale if velocity.y > 0.0 else fall_gravity_scale
		velocity.y -= gravity * gravity_scale * delta

	var is_sprinting := false

	if ai_enabled:
		# AI autoplay: wanders forward, jumps occasionally, and turns on its own.
		# (Unchanged -- AI drives velocity directly rather than through the
		# accel/friction model below.)
		process_ai(delta)
	else:
		if Input.is_action_just_pressed("jump") or _touch_jump_requested:
			_jump_buffer_timer = jump_buffer_time
			_touch_jump_requested = false

		# Get the input direction and turn it into a world-space move direction
		# relative to where the player is looking (Head yaw), then run it
		# through acceleration/friction toward a target speed instead of
		# snapping straight to it -- this is what makes movement feel weighty
		# rather than instant/robotic.
		# touch_move_vector (set live by TouchControls.gd's virtual joystick,
		# zero when not touched) is a fallback, not an override -- keyboard
		# still wins if both happen to be active at once (e.g. a keyboard
		# plugged into a tablet mid-touch-drag).
		var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		if input_dir == Vector2.ZERO:
			input_dir = touch_move_vector
		is_sprinting = input_dir != Vector2.ZERO and Input.is_action_pressed("sprint")
		_apply_horizontal_movement(delta, input_dir, is_sprinting)

	# Consume a buffered jump the instant we have floor/coyote grace,
	# regardless of which branch above requested it.
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		# Coarse action telemetry (see mining's "target_changed" below) --
		# lets a session log show *how* the player was actually moving, not
		# just what broke/placed, e.g. to tell "stuck standing still" apart
		# from "jumping around but not going anywhere".
		Telemetry.log_event("jump", {})

	_apply_head_bob(delta)
	_apply_sprint_fov(delta, is_sprinting)

	# Must run before move_and_slide(): it pre-lifts the body over a short
	# ledge so the same move_and_slide() call below clears it, instead of
	# discovering the ledge as a wall a frame later.
	_apply_step_climb(delta)

	move_and_slide()

	# Fix jitter: If the player is on floor, stop subtle vertical movement
	if is_on_floor() and velocity.y < 0:
		velocity.y = 0

	_check_void_fall()

	# Runs in both manual and AI mode: real clicks drive it in manual mode,
	# mock_left_click/mock_right_click (set externally, e.g. by AutoTester or
	# an AI driver) drive it in AI mode -- previously gated to manual-only,
	# which meant a bot/AI could never trigger the mocked tool interaction.
	manual_interaction_check(delta)

## Minecraft-style auto-step: while grounded and moving into something that
## blocks flat horizontal motion, check whether it's actually just a short
## ledge (clear headroom + clear forward path one step up) and, if so, nudge
## the body up by the ledge's exact height so it climbs instead of stopping.
## Leaves genuine walls/overhangs alone (headroom or forward-at-height check
## fails) so this can't be used to clip through anything solid.
func _apply_step_climb(delta: float) -> void:
	if not is_on_floor():
		return
	var horizontal = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < 0.01:
		return

	var motion = horizontal * delta
	# Nothing in the way at current height -- ordinary move_and_slide()
	# handles this frame fine, no step assist needed.
	if not test_move(global_transform, motion):
		return

	# Something blocks flat movement. Only treat it as a climbable ledge if
	# there's clear headroom one step up AND clear room to move forward from
	# up there -- otherwise it's a real wall/overhang and we leave it alone.
	var raised = global_transform.translated(Vector3(0, step_height, 0))
	if test_move(raised, Vector3.ZERO):
		return
	if test_move(raised, motion):
		return

	# Sweep back down from the raised, forward-moved position to find the
	# ledge's exact height, so the step lands flush on top of the block
	# instead of hovering or over/under-shooting on partial-height ledges.
	var probe = raised.translated(motion)
	var down_collision = KinematicCollision3D.new()
	if test_move(probe, Vector3(0, -step_height, 0), down_collision):
		var step_up = step_height + down_collision.get_travel().y
		if step_up > 0.01 and step_up <= step_height:
			global_position.y += step_up
			apply_floor_snap()

## See VOID_FALL_Y above. Routes through the same death/respawn feedback
## path as a normal death (_on_death) so a void fall always gets a clear
## on-screen reason instead of the player just silently reappearing.
func _check_void_fall() -> void:
	if global_position.y < VOID_FALL_Y and not _void_fall_handled:
		_void_fall_handled = true
		_on_death("void")

## Ground height at RESPAWN_XZ, using the exact same noise formula World.gd's
## spawn_player() uses for the player's very first spawn (Chunk.gd fills
## columns solid from y=0 up to this same height) -- so a death respawn lands
## the player just above the surface instead of the old hardcoded
## Vector3(0, 100, 0), which dropped them from the sky on literally every
## single death regardless of how high the terrain actually is at that spot.
func _compute_respawn_position() -> Vector3:
	var voxel_world = get_node_or_null("/root/World/VoxelWorld")
	if voxel_world and voxel_world.get("noise") and voxel_world.noise:
		var surface_height = int((voxel_world.noise.get_noise_2d(RESPAWN_XZ.x, RESPAWN_XZ.y) + 1) * 32) + 64
		return Vector3(RESPAWN_XZ.x, surface_height + 2, RESPAWN_XZ.y)
	# Fallback if VoxelWorld/noise isn't reachable (e.g. a stripped-down test
	# scene) -- the same value the old hardcoded constant used.
	return Vector3(RESPAWN_XZ.x, 100, RESPAWN_XZ.y)

func _apply_horizontal_movement(delta: float, input_dir: Vector2, is_sprinting: bool) -> void:
	var horizontal = Vector2(velocity.x, velocity.z)
	var target = Vector2.ZERO

	if input_dir != Vector2.ZERO:
		var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		var target_speed = sprint_speed if is_sprinting else walk_speed
		target = Vector2(direction.x, direction.z) * target_speed

	var grounded = is_on_floor()
	var accel: float
	if input_dir != Vector2.ZERO:
		accel = ground_acceleration if grounded else air_acceleration
	else:
		accel = ground_friction if grounded else air_friction

	horizontal = horizontal.move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	_footstep_caption_cooldown -= delta
	if grounded and input_dir != Vector2.ZERO and horizontal.length() > 0.5:
		if _footstep_caption_cooldown <= 0.0:
			_footstep_caption_cooldown = FOOTSTEP_CAPTION_INTERVAL
			SoundCaptions.caption("[Шаги]")
	else:
		_footstep_caption_cooldown = 0.0

func _apply_head_bob(delta: float) -> void:
	if not head_bob_enabled or not camera:
		return

	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var target_offset = Vector3.ZERO

	if is_on_floor() and horizontal_speed > 0.15:
		_bob_time += delta * horizontal_speed * head_bob_frequency
		var strength = clamp(horizontal_speed / sprint_speed, 0.0, 1.3)
		target_offset.y = sin(_bob_time) * head_bob_amplitude * strength
		target_offset.x = cos(_bob_time * 0.5) * head_bob_side_amplitude * strength
	# else: leave _bob_time as-is and let the offset lerp back toward zero
	# below, so stopping fades the bob out smoothly instead of snapping flat.

	var weight = clamp(delta * head_bob_smoothing, 0.0, 1.0)
	camera.position = camera.position.lerp(_camera_base_local_pos + target_offset, weight)

func _apply_sprint_fov(delta: float, is_sprinting: bool) -> void:
	if not camera:
		return
	var target_fov = _base_fov + (sprint_fov_kick_deg if is_sprinting else 0.0)
	camera.fov = lerp(camera.fov, target_fov, clamp(delta * fov_lerp_speed, 0.0, 1.0))

# Interaction override for Bot
var mock_left_click: bool = false
var mock_right_click: bool = false

# Touch-control overrides (set live by Scripts/UI/TouchControls.gd's virtual
# joystick / Jump button). Same shape as the mock_left/right_click hooks
# above -- a UI source feeding the same code path real input drives, not a
# parallel movement system.
var touch_move_vector: Vector2 = Vector2.ZERO
var _touch_jump_requested: bool = false

func touch_jump() -> void:
	_touch_jump_requested = true

# Hold-to-mine state for manual_interaction_check()/_process_mining() below:
# the single voxel currently targeted for breaking and how long LMB has
# continuously held it. Reset on target change / LMB release / raycast miss,
# so aiming at a new block, letting go, or looking away always cancels
# progress -- there is exactly one of these tracked at a time, so only ever
# one block can be mid-break.
var _mining_block: Vector3i = Vector3i.ZERO
var _mining_progress: float = 0.0
var _mining_blocked: bool = false

func manual_interaction_check(delta: float):
	var left = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or mock_left_click
	var right = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or mock_right_click

	if not left:
		# LMB released (or not held this frame) always cancels any
		# in-progress single-block mining -- see _process_mining() below.
		_mining_progress = 0.0
		_mining_blocked = false

	if not left and not right: return

	if not raycast.is_colliding():
		# Looking away from every block also cancels mining progress.
		_mining_progress = 0.0
		_mining_blocked = false

	if raycast.is_colliding():
		var collider = raycast.get_collider()
		var point = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()
		var voxel_world = get_node_or_null("/root/World/VoxelWorld")

		# Left Click: Destroy (hold-to-mine, single target -- _process_mining()
		# below owns the delay/single-target/under-feet logic; this call site
		# only decides what counts as a mineable vs. damageable collider).
		if left:
			if collider is StaticBody3D and voxel_world:
				_process_mining(delta, voxel_world, point, normal)
			elif collider != self and collider.has_method("take_damage"):
				# `collider != self`: belt-and-suspenders against the ray
				# self-hitting the player (add_exception in _ready/setup_nodes
				# already prevents it) so LMB can never damage the player.
				_mining_progress = 0.0
				_mining_blocked = false
				var item = ItemDatabase.get_item(selected_block_id)
				var dmg = 10.0
				if item: dmg += item.damage_value
				collider.take_damage(dmg)
				await get_tree().create_timer(0.4).timeout

		# Right Click: Place / Interact / Farm
		elif right:
			if not voxel_world: return
			
			var target_pos = point - normal * 0.1
			var x = int(floor(target_pos.x))
			var y = int(floor(target_pos.y))
			var z = int(floor(target_pos.z))
			var block_type = get_block_at(voxel_world, target_pos)
			
			# Handle Consumables (if no block interaction)
			if selected_block_id > 0:
				var item = ItemDatabase.get_item(selected_block_id)
				if item and item.type == 3: # ItemType.CONSUMABLE
					# Eat: restore Hunger via PlayerStats and consume one from the stack.
					if stats and item.nutrition_value > 0:
						stats.eat(item.nutrition_value)
						var eat_inv = get_node_or_null("Inventory")
						if eat_inv: eat_inv.remove_item(selected_block_id, 1)
						show_message("Ate " + item.name + " (+" + str(int(item.nutrition_value)) + " Hunger)")
					await get_tree().create_timer(0.3).timeout
					return

			# Tool Logic
			var item = ItemDatabase.get_item(selected_block_id)
			if item:
				# 1. Hoe Logic
				if selected_block_id == 33: # Hoe
					if block_type == 1 or block_type == 2: # Dirt/Grass
						voxel_world.set_voxel.rpc(target_pos, 14) # Farmland
						show_message("Tilled Soil")
						await get_tree().create_timer(0.3).timeout
						return

				# 2. Seed Logic (Planting)
				if selected_block_id == 20: # Seeds
					if block_type == 14: # Farmland
						var plant_pos = target_pos + Vector3(0, 1, 0)
						if get_block_at(voxel_world, plant_pos) == 0:
							voxel_world.set_voxel.rpc(plant_pos, 17) # Seedling
							show_message("Planted Seeds")
							await get_tree().create_timer(0.3).timeout
							return

			# 3. Block Entity Interaction
			var entity = voxel_world.get_block_entity(Vector3i(x, y, z))
			if entity and entity.has_method("interact"):
				entity.interact(self)
				return
				
			# 4. Normal Block Placement
			if item and item.type == 0: # ItemType.BLOCK
				# Consume from inventory -- previously placement ignored the
				# inventory entirely and just used the cached hotbar id, so
				# blocks were placeable infinitely without ever depleting the
				# stack. If there's no inventory wired up (e.g. a bare Player
				# node in a stripped-down test scene), fall back to the old
				# permissive behavior rather than blocking placement outright.
				if inventory and not inventory.remove_item(selected_block_id, 1):
					show_message("Out of " + item.name)
					return

				var place_pos = point + normal * 0.1
				# Use the item's declared block_id, not the item id itself --
				# most items are 1:1 (Dirt item 1 -> block 1) but a few reuse
				# ids (Sand item 42 -> block 16, Snow item 43 -> block 15);
				# placing by item id alone would silently place the wrong
				# block for those.
				var place_block_id = item.block_id if item.block_id > 0 else selected_block_id
				ActionLog.log_event("Поставлен блок: " + item.name)
				SoundCaptions.caption("[Стук]")
				Telemetry.log_event("block_placed", {"block_id": place_block_id})
				voxel_world.set_voxel.rpc(place_pos, place_block_id)
				await get_tree().create_timer(0.2).timeout

## Hold-to-mine a single block: LMB must stay aimed at the same voxel for
## get_break_speed() worth of continuous time before it actually breaks.
## Previously the block vanished the instant LMB went down, every single
## physics frame it was held (break_speed was only ever used as a cosmetic
## *post*-removal wait, after the block was already gone) -- so holding LMB
## while looking at (and re-aiming down into) the shaft it just opened could
## chain-break many blocks in under a second. Aiming at a different block
## always restarts progress at zero -- see _mining_block above, exactly one
## block is ever tracked/mid-break at a time.
func _process_mining(delta: float, voxel_world, point: Vector3, normal: Vector3) -> void:
	var block_pos = point - normal * 0.1
	var block_coord := Vector3i(int(floor(block_pos.x)), int(floor(block_pos.y)), int(floor(block_pos.z)))
	var block_type = get_block_at(voxel_world, block_pos)

	if block_coord != _mining_block:
		_mining_block = block_coord
		_mining_progress = 0.0
		_mining_blocked = false
		Telemetry.log_event("target_changed", {"block_id": block_type})

	# Digging straight down under yourself is intentional Minecraft-standard
	# play (owner mid=695). It is SAFE now: the death loop was never the fall
	# itself -- it was the interaction ray self-hitting the player
	# (fixed via raycast.add_exception(self)). You drop one block onto the
	# next, respawn lands on ground if you ever fall out, and the hold-to-mine
	# delay + single-target reset (the target changes as you fall) naturally
	# throttle it -- no instant chain into the void. So NO under-feet refusal.
	_mining_blocked = false
	_mining_progress += delta

	var break_speed = get_break_speed(selected_block_id, block_type)
	if _mining_progress < break_speed:
		return # still mid-hold -- not broken yet

	_mining_progress = 0.0

	var harvest_inv = get_node_or_null("Inventory")
	# Harvest: breaking a Berry Bush yields Berries (food), not the bush
	# block itself -- keep this special-cased and mutually exclusive with the
	# generic collectible pickup below (elif), or breaking a bush would grant
	# both.
	if block_type == 55: # Berry Bush (was id 52, reassigned -- see ItemDatabase.gd)
		if harvest_inv: harvest_inv.add_item(70, 1) # Berries
		show_message("Harvested Berries")
		ActionLog.log_event("Подобрано: Berries x1")
	# Generic collectible pickup: the decorative flowers and the wave-2
	# mineral ores are each their own block+item (id == block_id, see
	# ItemDatabase.gd), so breaking one yields itself into the inventory --
	# this is also what feeds Field Journal discovery
	# (Inventory.item_picked_up -> PlayerStats.discover_item, see
	# Player._ready()). Intentionally scoped to just these collectible
	# species rather than every mineable block (Dirt/Stone/Wood/...) to keep
	# this change's blast radius limited to wave 2.
	elif block_type in COLLECTIBLE_BLOCK_IDS:
		if harvest_inv: harvest_inv.add_item(block_type, 1)
		ActionLog.log_event("Подобрано: " + _block_display_name(block_type) + " x1")
	ActionLog.log_event("Сломан блок: " + _block_display_name(block_type))
	SoundCaptions.caption("[Копание]")
	Telemetry.log_event("block_broken", {"block_id": block_type})
	voxel_world.set_voxel.rpc(block_pos, 0)

func toggle_ai():
	ai_enabled = not ai_enabled
	if ai_enabled:
		show_message("AI ENABLED")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # Let AI handle looking, or keep captured? 
		# User req: "AI Enabled... button showing"
	else:
		show_message("AI DISABLED")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Update HUD Button visual
	var hud = get_node_or_null("HUD/PlayerHUD")
	if hud and hud.has_method("update_ai_button"):
		hud.update_ai_button(ai_enabled)

func process_ai(delta):
	ai_timer -= delta
	
	# Simple Wandering / Gathering AI
	# For now, just move forward and jump occasionally to simulate "bot"
	# Or use the logic from AutoTester if we migrate it here.
	
	# Let's perform a simple "Wander & Jump" for visual confirmation
	var direction = head.transform.basis * Vector3(0, 0, -1)
	velocity.x = direction.x * 2.0
	velocity.z = direction.z * 2.0
	
	if is_on_floor() and randf() < 0.01:
		velocity.y = jump_velocity
	
	# Rotate head slowly
	head.rotate_y(delta * 0.5)


# Uncategorized blocks (flowers, leaves, ores without a category, decor, ...)
# always break at the flat default speed, unaffected by whatever is held --
# this matches
# the speed the game shipped with before tools existed. Blocks that DO have a
# mining category (stone/ore -> pickaxe, wood/planks -> axe, dirt/sand ->
# shovel, see ItemDatabase.BLOCK_TOOL_CATEGORY) break fast with the matching
# tool equipped and slow otherwise (bare hands or the wrong tool).
const BREAK_SPEED_DEFAULT = 0.2
const BREAK_SPEED_WITH_TOOL = 0.1
const BREAK_SPEED_WITHOUT_TOOL = 0.5

func get_break_speed(held_item_id: int, block_type: int) -> float:
	var category = ItemDatabase.get_block_category(block_type)
	if category == "":
		return BREAK_SPEED_DEFAULT

	var item = ItemDatabase.get_item(held_item_id)
	if item and item.type == 1 and item.tool_type == category: # ItemType.TOOL
		return BREAK_SPEED_WITH_TOOL
	return BREAK_SPEED_WITHOUT_TOOL

## Human-readable name for a raw block/voxel id, for ActionLog lines. Most
## blocks have a matching ItemDatabase entry (id == block_id, see
## COLLECTIBLE_BLOCK_IDS above and ItemDatabase.gd) but a few purely
## world-generated blocks (farmland, seedlings, bedrock, ...) don't -- fall
## back to a numeric tag rather than failing the log line.
func _block_display_name(block_type: int) -> String:
	var item = ItemDatabase.get_item(block_type)
	if item and item.name != "":
		return item.name
	return "#%d" % block_type

func get_block_at(world, pos: Vector3) -> int:
	var x = int(floor(pos.x))
	var y = int(floor(pos.y))
	var z = int(floor(pos.z))
	var cx = int(floor(float(x) / 16.0))
	var cz = int(floor(float(z) / 16.0))
	var cp = Vector2i(cx, cz)
	if world.chunks.has(cp):
		var chunk = world.chunks[cp]
		var lx = x - cx * 16
		var lz = z - cz * 16
		var lp = Vector3i(lx, y, lz)
		if chunk.voxel_data.has(lp):
			return chunk.voxel_data[lp]
	return 0

func show_message(text: String):
	print("Message: " + text)
	# Check HUD
	var hud = get_node_or_null("HUD/PlayerHUD")
	if hud:
		var label = hud.get_node_or_null("MessageLabel")
		if not label:
			label = Label.new()
			label.name = "MessageLabel"
			label.position = Vector2(20, 20)
			# label.add_theme_font_size_override("font_size", 24) # Optional
			hud.add_child(label)
		
		label.text = text
		
		# Clear after timer
		await get_tree().create_timer(2.0).timeout
		# Clear after timer
		await get_tree().create_timer(2.0).timeout
		if label and label.text == text:
			label.text = ""

func take_damage(amount: float, cause: String = "damage"):
	if stats:
		stats.take_damage(amount, cause)

## Human-readable reason for the death/respawn screen -- the whole point of
## this map is that "why did I just respawn" (mob hit vs. starvation vs.
## falling out of the world) is never left to guesswork. See PlayerStats.
## take_damage()'s cause param and _check_void_fall() above for the callers.
const DEATH_REASONS := {
	"mob": "Killed by a mob",
	"hunger": "Starved",
	"void": "Fell out of the world",
}

func _on_death(cause: String = "damage"):
	var reason: String = DEATH_REASONS.get(cause, "You died")

	var hud = get_node_or_null("HUD/PlayerHUD")
	if hud and hud.has_method("show_death_screen"):
		hud.show_death_screen(reason)
	else:
		# Defensive fallback for contexts without the full HUD (see
		# setup_nodes()) so death is never silent even there.
		show_message(reason + " -- Respawning...")

	ActionLog.log_event("☠ Погиб: " + reason)
	SoundCaptions.caption("[Смерть]")
	Telemetry.log_event("death", {"cause": cause})

	# Simple respawn logic
	position = _compute_respawn_position()
	velocity = Vector3.ZERO
	stats.heal(100)
	stats.eat(100)
	_void_fall_handled = false
	ActionLog.log_event("Возрождение")
