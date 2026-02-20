extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var raycast = $Head/Camera3D/RayCast3D

@onready var stats = $PlayerStats # Ensure this matches Scene tree

@onready var hotbar_ui = $HUD/HotbarUI
var selected_block_id: int = 1 # Default Dirt

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("player")
	
	if stats:
		stats.died.connect(_on_death)
		
		# Connect HUD Bars
		var hud = get_node_or_null("HUD")
		if hud:
			var health_bar = hud.get_node_or_null("HealthBar")
			if health_bar:
				stats.health_changed.connect(func(val, max_val): health_bar.value = (val / max_val) * 100)
			
			var hunger_bar = hud.get_node_or_null("HungerBar")
			if hunger_bar:
				stats.hunger_changed.connect(func(val, max_val): hunger_bar.value = (val / max_val) * 100)
		
	# Setup WASD if not defined
	add_input_mapping("move_forward", KEY_W)
	add_input_mapping("move_backward", KEY_S)
	add_input_mapping("move_left", KEY_A)
	add_input_mapping("move_right", KEY_D)
	add_input_mapping("jump", KEY_SPACE)
	add_input_mapping("inventory", KEY_E)

	# Ensure nodes exist
	if not head:
		setup_nodes()
		
	# Connect Hotbar
	if hotbar_ui:
		hotbar_ui.slot_selected.connect(on_hotbar_select)

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

	var inv = load("res://Scripts/UI/Inventory.gd").new()
	inv.name = "Inventory"
	add_child(inv)
	
	# Add InventoryUI canvas layer or similar?
	# UI usually separate. World handles UI?
	# Let's let the player have a HUD.
	# For now, let's assume UI is in World or added to Player.
	pass

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

	if event.is_action_pressed("ui_cancel"): # Escape
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Simple respawn logic
	position = Vector3(0, 100, 0)
	stats.heal(100)
	stats.eat(100)

# AI Control
@export var ai_enabled: bool = false # Default to Manual
var ai_target: Node3D = null
var ai_timer: float = 0.0

func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# AI Override
	if ai_enabled:
		process_ai(delta)
	else:
		handle_movement(delta)

	move_and_slide()
	
	if not ai_enabled and not has_node("AutoTester"):
		manual_interaction_check()

func handle_movement(delta):
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

# Interaction override for Bot
var mock_left_click: bool = false
var mock_right_click: bool = false

func manual_interaction_check():
	var left = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or mock_left_click
	var right = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or mock_right_click
	
	if not left and not right: return
	
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		var point = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()
		var voxel_world = get_node_or_null("/root/World/VoxelWorld")
		
		# Left Click: Destroy
		if left:
			if collider is StaticBody3D and voxel_world:
				var block_pos = point - normal * 0.1
				voxel_world.set_voxel.rpc(block_pos, 0)
				await get_tree().create_timer(0.2).timeout
			elif collider.has_method("take_damage"):
				collider.take_damage(10.0)
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
					# Consume item logic here
					# For now, just print and return
					print("Consumed item: ", item.name)
					# stats.consume_item(item) # Example
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
				var place_pos = point + normal * 0.1
				voxel_world.set_voxel.rpc(place_pos, selected_block_id)
				await get_tree().create_timer(0.2).timeout

func process_ai(delta):
	ai_timer -= delta
	
	# Find Target
	if not is_instance_valid(ai_target):
		var mobs = get_tree().get_nodes_in_group("mobs") # Assuming mobs are in group
		# Search mobs
		var closest_dist = 999.0
		for mob in get_tree().root.find_children("*", "Mob", true, false): # Quick hack if group missing
			var d = global_position.distance_to(mob.global_position)
			if d < closest_dist:
				closest_dist = d
				ai_target = mob
	
	if is_instance_valid(ai_target):
		# Look at
		head.look_at(ai_target.global_position, Vector3.UP, true) # Simplified look
		
		var dist = global_position.distance_to(ai_target.global_position)
		if dist > 2.0:
			# Move towards
			var dir = (ai_target.global_position - global_position).normalized()
			velocity.x = dir.x * SPEED
			velocity.z = dir.z * SPEED
		else:
			# Attack
			velocity.x = 0
			velocity.z = 0
			if ai_timer <= 0:
				if ai_target.has_method("take_damage"):
					print("AI Player attacking Mob!")
					ai_target.take_damage(10.0) # Sword damage
					ai_timer = 1.0
	else:
		# Wander
		velocity.x = 0
		velocity.z = 0

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
	var hud = get_node_or_null("HUD")
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
