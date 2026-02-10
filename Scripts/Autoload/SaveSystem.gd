extends Node
class_name SaveSystemClass

const SAVE_DIR = "user://saves/world1/"

func _ready():
	ensure_save_dir()

static func ensure_save_dir():
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

static func get_chunk_path(pos: Vector2i) -> String:
	return SAVE_DIR + "chunk_%d_%d.dat" % [pos.x, pos.y]

static func has_chunk(pos: Vector2i) -> bool:
	return FileAccess.file_exists(get_chunk_path(pos))

static func save_chunk(chunk):
	ensure_save_dir()
	var path = get_chunk_path(chunk.chunk_position)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_var(chunk.voxel_data)
		file.close()

static func load_chunk(chunk):
	var path = get_chunk_path(chunk.chunk_position)
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var data = file.get_var()
			if data is Dictionary:
				chunk.voxel_data = data
			file.close()
			return true
	return false
