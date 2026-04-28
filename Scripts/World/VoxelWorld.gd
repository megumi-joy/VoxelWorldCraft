extends Node3D
class_name VoxelWorld

var chunks = {}
var noise = FastNoiseLite.new()
const ChunkScript = preload("res://Scripts/World/Chunk.gd")

@export var render_distance = 2
@export var player: Node3D

var chunk_material: StandardMaterial3D

func _ready():
	var tex_gen_type = load("res://Scripts/World/TextureGenerator.gd")
	var tex_gen = Node.new()
	tex_gen.set_script(tex_gen_type)
	add_child(tex_gen)
	
	noise.seed = randi()
	noise.frequency = 0.01

func _process(_delta):
	# Wait for player and material before generating world
	if not player or not chunk_material:
		return
		
	var p_pos = player.global_position
	var center_chunk = Vector2i(int(floor(p_pos.x / 16.0)), int(floor(p_pos.z / 16.0)))
	
	update_chunks(center_chunk)

func update_chunks(center_chunk: Vector2i):
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var pos = center_chunk + Vector2i(x, z)
			if not chunks.has(pos):
				create_chunk(pos)

func create_chunk(pos: Vector2i):
	# Prevent double creation in the same frame if multiple processes triggered it
	chunks[pos] = null # Placeholder
	
	var chunk = Node3D.new()
	chunk.set_script(ChunkScript)
	
	if chunk.has_method("setup"):
		chunk.setup(pos, noise, chunk_material)
		add_child(chunk)
		chunk.global_position = Vector3(pos.x * 16.0, 0, pos.y * 16.0)
		chunks[pos] = chunk
		print("Chunk successfully created and registered at: ", pos)
	else:
		print("ERROR: Chunk setup failed at: ", pos)
		chunks.erase(pos)

var block_entities = {} # Vector3i -> Node

@rpc("any_peer", "call_local")
func set_voxel(global_pos: Vector3, type: int):
	var x = int(floor(global_pos.x))
	var y = int(floor(global_pos.y))
	var z = int(floor(global_pos.z))
	var pos_i = Vector3i(x, y, z)
	
	var chunk_x = int(floor(float(x) / 16.0))
	var chunk_z = int(floor(float(z) / 16.0))
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
	
	if chunks.has(chunk_pos) and chunks[chunk_pos] != null:
		var chunk = chunks[chunk_pos]
		var local_x = x - chunk_x * 16
		var local_z = z - chunk_z * 16
		
		if y >= 0 and y < 256:
			chunk.set_block(Vector3i(local_x, y, local_z), type)
			# SaveSystem.save_chunk(chunk) # Disable save for profiling to avoid disk I/O noise

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
