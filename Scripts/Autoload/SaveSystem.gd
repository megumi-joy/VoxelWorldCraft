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

# World-level metadata (currently just the terrain noise seed). Only
# individual chunks are saved -- unedited chunks are cheaply regenerated
# from noise on load rather than written to disk. That only reproduces the
# same terrain if the noise seed is stable across sessions, so it has to be
# persisted once and reused, or a fresh random seed each launch would make
# every unedited chunk regenerate as different terrain while edited chunks
# reload their frozen snapshot -- a visible discontinuity at every
# saved/unsaved chunk boundary.
static func get_meta_path() -> String:
	return SAVE_DIR + "world_meta.dat"

static func save_world_seed(seed_value: int):
	ensure_save_dir()
	var file = FileAccess.open(get_meta_path(), FileAccess.WRITE)
	if file:
		file.store_var({"seed": seed_value})
		file.close()

# Returns the persisted seed, or -1 if none has been saved yet.
static func load_world_seed() -> int:
	var path = get_meta_path()
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var data = file.get_var()
			file.close()
			if data is Dictionary and data.has("seed"):
				return data["seed"]
	return -1
