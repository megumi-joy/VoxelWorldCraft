extends Node3D
class_name VoxelWorld

var chunks = {}
var noise = FastNoiseLite.new()

@export var render_distance = 4
@export var player: Node3D

func _ready():
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
	var chunk = Chunk.new(pos, noise)
	add_child(chunk)
	chunk.global_position = Vector3(pos.x * Chunk.CHUNK_SIZE.x, 0, pos.y * Chunk.CHUNK_SIZE.z)
	chunks[pos] = chunk

@rpc("any_peer", "call_local")
func set_voxel(global_pos: Vector3, type: int):
	var x = int(floor(global_pos.x))
	var y = int(floor(global_pos.y))
	var z = int(floor(global_pos.z))
	
	var chunk_x = int(floor(float(x) / Chunk.CHUNK_SIZE.x))
	var chunk_z = int(floor(float(z) / Chunk.CHUNK_SIZE.z))
	var chunk_pos = Vector2i(chunk_x, chunk_z)
	
	if chunks.has(chunk_pos):
		var chunk = chunks[chunk_pos]
		var local_x = x - chunk_x * Chunk.CHUNK_SIZE.x
		var local_z = z - chunk_z * Chunk.CHUNK_SIZE.z
		# y is direct as we only have vertical chunks (256 height)
		if y >= 0 and y < Chunk.CHUNK_SIZE.y:
			chunk.set_block(Vector3i(local_x, y, local_z), type)
