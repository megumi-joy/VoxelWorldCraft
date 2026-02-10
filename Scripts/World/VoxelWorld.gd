@tool
extends Node3D
class_name VoxelWorld

var chunks = {}
var noise = FastNoiseLite.new()

@export var render_distance = 2
@export var player: Node3D
@export var spawn_on_start: bool = true

@export var generate_preview: bool = false:
	set(value):
		generate_preview = false
		if value:
			generate_editor_preview()

@export var clear_preview: bool = false:
	set(value):
		clear_preview = false
		if value:
			clear_editor_chunks()

var chunk_material: StandardMaterial3D

func _ready():
	# Runtime Only Logic
	if not Engine.is_editor_hint():
		var tex_gen = TextureGenerator.new()
		add_child(tex_gen)
		
		noise.seed = randi()
		noise.frequency = 0.01
		
		# Multiplayer Spawning
		call_deferred("deferred_multiplayer_setup")

func deferred_multiplayer_setup():
	printerr("VoxelWorld Ready (Parent: ", get_parent().name, "). is_server: ", multiplayer.is_server())
	if multiplayer.is_server() and spawn_on_start:
		multiplayer.peer_connected.connect(spawn_player)
		multiplayer.peer_disconnected.connect(remove_player)
		
		# Spawn Host
		call_deferred("spawn_player", 1)

func generate_editor_preview():
	print("Generating Editor Preview...")
	clear_editor_chunks()
	
	if not noise: noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.01
	
	# Generate 3x3 area
	for x in range(-1, 2):
		for z in range(-1, 2):
			create_chunk(Vector2i(x, z))

func clear_editor_chunks():
	print("Clearing Preview...")
	chunks.clear()
	for child in get_children():
		if child is Chunk:
			child.queue_free()

func spawn_player(id: int):
	if id == 1:
		# Check if already spawned?
		if has_node(str(id)): return
		
	var player_scene = load("res://Scenes/Player.tscn")
	var p = player_scene.instantiate()
	p.name = str(id)
	
	# Host Spawn Point
	p.position = Vector3(0, 80, 0) # High up to avoid stuck
	
	# Add directly to Parent (World) to ensure MultiplayerSpawner picks it up
	# Use deferred to avoid "busy parent" error
	get_parent().add_child.call_deferred(p)
	
	if id == multiplayer.get_unique_id():
		player = p

func remove_player(id: int):
	var p = get_parent().get_node_or_null(str(id))
	if p:
		p.queue_free()

func _process(_delta):
	# Runtime Only
	if Engine.is_editor_hint(): return
	
	if player and is_instance_valid(player):
		var p_pos = player.global_position
		var chunk_pos = Vector2i(int(p_pos.x / Chunk.CHUNK_SIZE.x), int(p_pos.z / Chunk.CHUNK_SIZE.z))
		update_chunks(chunk_pos)

func update_chunks(center_chunk: Vector2i):
	for x in range(-render_distance, render_distance + 1):
		for y in range(-render_distance, render_distance + 1):
			var pos = center_chunk + Vector2i(x, y)
			if not chunks.has(pos):
				create_chunk(pos)

func create_chunk(pos: Vector2i):
	var chunk = Chunk.new(pos, noise, chunk_material)
	
	# Load existing data BEFORE add_child so _ready sees it
	# Use SaveSystemClass static methods to work in Editor
	if SaveSystemClass.has_chunk(pos):
		SaveSystemClass.load_chunk(chunk)
	
	add_child(chunk)
	chunk.global_position = Vector3(pos.x * Chunk.CHUNK_SIZE.x, 0, pos.y * Chunk.CHUNK_SIZE.z)
	chunks[pos] = chunk

var block_entities = {} # Vector3i -> Node

@rpc("any_peer", "call_local")
func set_voxel(global_pos: Vector3, type: int):
	var x = int(floor(global_pos.x))
	var y = int(floor(global_pos.y))
	var z = int(floor(global_pos.z))
	var pos_i = Vector3i(x, y, z)
	
	var chunk_x = int(floor(float(x) / Chunk.CHUNK_SIZE.x))
	var chunk_z = int(floor(float(z) / Chunk.CHUNK_SIZE.z))
	var chunk_pos = Vector2i(chunk_x, chunk_z)
	
	# Handle Block Entities
	if block_entities.has(pos_i):
		var entity = block_entities[pos_i]
		if is_instance_valid(entity):
			entity.queue_free()
		block_entities.erase(pos_i)
	
	if type == 8: # Furnace
		spawn_block_entity(pos_i, "res://Scenes/Blocks/FurnaceBlock.tscn")
	elif type == 9: # Crafting Table
		spawn_block_entity(pos_i, "res://Scenes/Blocks/CraftingTableBlock.tscn")
	elif type == 10: # Bed
		spawn_block_entity(pos_i, "res://Scenes/Blocks/BedBlock.tscn")
	elif type == 14: # Crop
		spawn_block_entity(pos_i, "res://Scenes/Blocks/CropBlock.tscn")
	
	if chunks.has(chunk_pos):
		var chunk = chunks[chunk_pos]
		var local_x = x - chunk_x * Chunk.CHUNK_SIZE.x
		var local_z = z - chunk_z * Chunk.CHUNK_SIZE.z
		
		# Validate Y (0-255)
		if y >= 0 and y < Chunk.CHUNK_SIZE.y:
			chunk.set_block(Vector3i(local_x, y, local_z), type)
			if not Engine.is_editor_hint():
				SaveSystemClass.save_chunk(chunk)

func spawn_block_entity(pos: Vector3i, scene_path: String):
	var scene = load(scene_path)
	if scene:
		var entity = scene.instantiate()
		entity.position = Vector3(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5)
		add_child(entity)
		block_entities[pos] = entity

func get_block_entity(pos: Vector3i) -> Node:
	if block_entities.has(pos):
		return block_entities[pos]
	return null
