extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var raycast = $Head/Camera3D/RayCast3D

@onready var hotbar_ui = $HUD/HotbarUI
var selected_block_id: int = 1 # Default Dirt

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_to_group("player")
	
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

	var inv = Inventory.new()
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

func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

	# Interaction
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if raycast.is_colliding():
			var collider = raycast.get_collider()
			# Collider is StaticBody3D -> MeshInstance3D -> Chunk -> VoxelWorld
			# Or we can just find VoxelWorld globally if we are lazy, but let's	# Interaction
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if raycast.is_colliding():
			var voxel_world = get_node("/root/World/VoxelWorld")
			if voxel_world:
				var point = raycast.get_collision_point()
				var normal = raycast.get_collision_normal()
				var block_center = point - normal * 0.5
				voxel_world.set_voxel.rpc(block_center, 0) # 0 = Air

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if raycast.is_colliding():
			var voxel_world = get_node("/root/World/VoxelWorld")
			if voxel_world:
				var point = raycast.get_collision_point()
				var normal = raycast.get_collision_normal()
				
				# Check interaction first (Existing block)
				var block_center = point - normal * 0.5
				var x = int(floor(block_center.x))
				var y = int(floor(block_center.y))
				var z = int(floor(block_center.z))
				var pos_i = Vector3i(x, y, z)
				
				var entity = voxel_world.get_block_entity(pos_i)
				if entity and entity.has_method("interact"):
					entity.interact(self)
					return # Don't place block if interacted
				
				# Place Block
				var place_center = point + normal * 0.5
				voxel_world.set_voxel.rpc(place_center, selected_block_id)
