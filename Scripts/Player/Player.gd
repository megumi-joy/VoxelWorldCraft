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
	
	# Create basic HUD if missing
	if not has_node("HUD"):
		var hud = Control.new()
		hud.name = "HUD"
		# Load and attach HUD script
		var hud_script = load("res://Scripts/UI/HUD.gd")
		hud.set_script(hud_script)
		add_child(hud)
		
		# Hotbar is usually child of HUD or separate
		# If HotbarUI is separate scene, we can add it
		var hotbar_res = load("res://Scenes/HotbarUI.tscn")
		if hotbar_res:
			var hotbar = hotbar_res.instantiate()
			hud.add_child(hotbar)
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

func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor() and not ai_enabled:
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Vector2.ZERO
	if not ai_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	# AI Override
	if ai_enabled:
		process_ai(delta)
	else:
		var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
	
	move_and_slide()
	
	if not ai_enabled:
		manual_interaction_check()

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
	var hud = get_node_or_null("HUD")
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
		velocity.y = JUMP_VELOCITY
	
	# Rotate head slowly
	head.rotate_y(delta * 0.5)


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
