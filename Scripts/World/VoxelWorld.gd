extends Node3D
class_name VoxelWorld

var chunks = {}
var noise = FastNoiseLite.new()
const ChunkScript = preload("res://Scripts/World/Chunk.gd")

@export var render_distance = 2
@export var player: Node3D

var chunk_material: StandardMaterial3D

func _ready():
	var TextureGenerator = load("res://Scripts/World/TextureGenerator.gd")
	var tex_gen = Node.new()
	tex_gen.set_script(TextureGenerator)
	add_child(tex_gen)
	
	noise.seed = randi()
	noise.frequency = 0.01

func _process(_delta):
	if player:
		# Hardcoded Chunk Size (16, 256, 16) to avoid script loading issues
		var p_pos = player.global_position
		var chunk_pos = Vector2i(int(p_pos.x / 16.0), int(p_pos.z / 16.0))
		
		update_chunks(chunk_pos)

func update_chunks(center_chunk: Vector2i):
	for x in range(-render_distance, render_distance + 1):
		for y in range(-render_distance, render_distance + 1):
			var pos = center_chunk + Vector2i(x, y)
			if not chunks.has(pos):
				create_chunk(pos)

func create_chunk(pos: Vector2i):
	var chunk = Node3D.new()
	chunk.set_script(ChunkScript)
	if chunk.get_script() == null:
		print("ERROR: Failed to attach ChunkScript! ChunkScript resource: ", ChunkScript)
	else:
		if chunk.has_method("setup"):
			chunk.setup(pos, noise, chunk_material)
		else:
			print("ERROR: Chunk script attached but no setup method!")
	
	# Add AutoTester if in headless/profile mode
	if OS.get_cmdline_args().has("--profile") or OS.has_feature("testing"):
		var tester_script = load("res://Scripts/Testing/AutoTester.gd")
		var tester = Node.new()
		tester.name = "AutoTester"
		tester.set_script(tester_script)
		
		# Find player and add to it
		var p = get_node_or_null("Player")
		if p:
			p.add_child(tester)
			print("AutoTester attached to Player")
		else:
			add_child(tester)
			print("AutoTester added to World (Player not found)")

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
	
	if chunks.has(chunk_pos):
		var chunk = chunks[chunk_pos]
		var local_x = x - chunk_x * 16
		var local_z = z - chunk_z * 16
		
		# Validate Y (0-255)
		if y >= 0 and y < 256:
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
