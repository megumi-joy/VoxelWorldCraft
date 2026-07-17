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

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var raycast = $Head/Camera3D/RayCast3D

@onready var stats = $PlayerStats # Ensure this matches Scene tree

@onready var hotbar_ui = $HUD/HotbarUI
@onready var inventory = get_node_or_null("Inventory")
var selected_block_id: int = 1 # Default Dirt

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("player")
	
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
		
	# Setup WASD if not defined
	add_input_mapping("move_forward", KEY_W)
	add_input_mapping("move_backward", KEY_S)
	add_input_mapping("move_left", KEY_A)
	add_input_mapping("move_right", KEY_D)
	add_input_mapping("jump", KEY_SPACE)
	add_input_mapping("sprint", KEY_SHIFT)
	add_input_mapping("inventory", KEY_E)

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
		# Light smoothing: blend each raw mouse delta with the previous
		# smoothed delta so small jitter doesn't translate 1:1 into camera
		# shake, while staying responsive (low smoothing weight by default).
		_smoothed_look_delta = _smoothed_look_delta.lerp(event.relative, 1.0 - look_smoothing)
		head.rotate_y(-_smoothed_look_delta.x * mouse_sensitivity)
		camera.rotate_x(-_smoothed_look_delta.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

	if event.is_action_pressed("ui_cancel"): # Escape
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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
		if Input.is_action_just_pressed("jump"):
			_jump_buffer_timer = jump_buffer_time

		# Get the input direction and turn it into a world-space move direction
		# relative to where the player is looking (Head yaw), then run it
		# through acceleration/friction toward a target speed instead of
		# snapping straight to it -- this is what makes movement feel weighty
		# rather than instant/robotic.
		var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		is_sprinting = input_dir != Vector2.ZERO and Input.is_action_pressed("sprint")
		_apply_horizontal_movement(delta, input_dir, is_sprinting)

	# Consume a buffered jump the instant we have floor/coyote grace,
	# regardless of which branch above requested it.
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	_apply_head_bob(delta)
	_apply_sprint_fov(delta, is_sprinting)

	move_and_slide()

	# Fix jitter: If the player is on floor, stop subtle vertical movement
	if is_on_floor() and velocity.y < 0:
		velocity.y = 0

	# Runs in both manual and AI mode: real clicks drive it in manual mode,
	# mock_left_click/mock_right_click (set externally, e.g. by AutoTester or
	# an AI driver) drive it in AI mode -- previously gated to manual-only,
	# which meant a bot/AI could never trigger the mocked tool interaction.
	manual_interaction_check()

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

func manual_interaction_check():
	var left = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or mock_left_click
	var right = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or mock_right_click
	
	if not left and not right: return

	if not raycast.is_colliding():
		print("[DBG_INTERACT] no raycast hit, cam_pitch_deg=", rad_to_deg(camera.rotation.x))

	if raycast.is_colliding():
		var collider = raycast.get_collider()
		var point = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()
		var voxel_world = get_node_or_null("/root/World/VoxelWorld")
		print("[DBG_INTERACT] hit=", collider, " is_static=", collider is StaticBody3D, " voxel_world=", voxel_world)

		# Left Click: Destroy
		if left:
			if collider is StaticBody3D and voxel_world:
				var block_pos = point - normal * 0.1
				var block_type = get_block_at(voxel_world, block_pos)
				var break_speed = get_break_speed(selected_block_id, block_type)
				# Harvest: breaking a Berry Bush yields Berries (food) into the inventory.
				if block_type == 55: # Berry Bush (was id 52, reassigned -- see ItemDatabase.gd)
					var harvest_inv = get_node_or_null("Inventory")
					if harvest_inv: harvest_inv.add_item(70, 1) # Berries
					show_message("Harvested Berries")
				voxel_world.set_voxel.rpc(block_pos, 0)
				await get_tree().create_timer(break_speed).timeout
			elif collider.has_method("take_damage"):
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
				voxel_world.set_voxel.rpc(place_pos, place_block_id)
				await get_tree().create_timer(0.2).timeout

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

func take_damage(amount: float):
	if stats:
		stats.take_damage(amount)

func _on_death():
	show_message("YOU DIED! Respawning...")
	# Simple respawn logic
	position = Vector3(0, 100, 0)
	stats.heal(100)
	stats.eat(100)
