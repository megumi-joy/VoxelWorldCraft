extends Node3D
class_name VoxelWorld

var chunks = {}
var noise = FastNoiseLite.new()

@export var render_distance = 4
@export var player: Node3D

var chunk_material: StandardMaterial3D

func _ready():
	var tex_gen = TextureGenerator.new()
	add_child(tex_gen)
	
	noise.seed = randi()
	noise.frequency = 0.01

func _process(_delta):
	if player:
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
	if SaveSystem.has_chunk(pos):
		SaveSystem.load_chunk(chunk)
	
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
	
	if chunks.has(chunk_pos):
		var chunk = chunks[chunk_pos]
		var local_x = x - chunk_x * Chunk.CHUNK_SIZE.x
		var local_z = z - chunk_z * Chunk.CHUNK_SIZE.z
		
		# Validate Y (0-255)
		if y >= 0 and y < Chunk.CHUNK_SIZE.y:
			chunk.set_block(Vector3i(local_x, y, local_z), type)
			SaveSystem.save_chunk(chunk)

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
