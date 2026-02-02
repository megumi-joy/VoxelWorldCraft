extends Node

const SAVE_DIR = "user://saves/world1/"

func _ready():
	# Ensure save directory exists
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func get_chunk_path(pos: Vector2i) -> String:
	return SAVE_DIR + "chunk_%d_%d.dat" % [pos.x, pos.y]

func has_chunk(pos: Vector2i) -> bool:
	return FileAccess.file_exists(get_chunk_path(pos))

func save_chunk(chunk):
	var path = get_chunk_path(chunk.chunk_position)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		# Save Voxel Data
		file.store_var(chunk.voxel_data)
		# Future: Save Block Entities if we track them per chunk
		# For now, VoxelWorld tracks entities globally? 
		# If VoxelWorld tracks entities, we should probably save them here too if they belong to this chunk.
		# But VoxelWorld entities map uses Vector3i globally.
		# Let's just save voxel_data for now.
		file.close()
		# print("Saved chunk: ", chunk.chunk_position)

func load_chunk(chunk):
	var path = get_chunk_path(chunk.chunk_position)
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var data = file.get_var()
			if data is Dictionary:
				chunk.voxel_data = data
			file.close()
			# print("Loaded chunk: ", chunk.chunk_position)
			return true
	return false
