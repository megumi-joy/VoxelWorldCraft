extends RefCounted
class_name MinecraftImporter

# Reads the JSON produced by tools/mc_import/parse_and_map.py (already
# parsed from the real .mca and already mapped to VoxelWorldCraft block
# ids -- this class does no Minecraft-specific decoding itself, Python does
# that inside podman since Python is blocked on the host) and turns it into
# per-chunk voxel_data Dictionaries ready for Chunk.setup_import().
#
# Expected JSON shape (see parse_and_map.py's `out_json`):
# {
#   "chunk_size": 16,
#   "source": {...},
#   "y_range": [min_y, max_y],
#   "chunks": { "cx,cz": [[local_x, world_y, local_z, block_id], ...], ... }
# }

# Returns a Dictionary:
#   "ok": bool
#   "error": String (only if not ok)
#   "chunks": { Vector2i(cx,cz) : Dictionary(Vector3i -> int block_id) }
#   "chunk_count": int
#   "block_count": int
#   "y_range": Array[int]
#   "source": Dictionary (passthrough, for logging)
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "file not found: %s" % path}

	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "could not open: %s (err=%d)" % [path, FileAccess.get_open_error()]}

	var text = f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid JSON in %s" % path}

	if not parsed.has("chunks"):
		return {"ok": false, "error": "JSON missing 'chunks' key"}

	var chunks := {}
	var block_count := 0

	for key in parsed["chunks"].keys():
		var parts = key.split(",")
		if parts.size() != 2:
			continue
		var cx = int(parts[0])
		var cz = int(parts[1])
		var chunk_pos = Vector2i(cx, cz)

		var voxel_data := {}
		for row in parsed["chunks"][key]:
			# row = [local_x, world_y, local_z, block_id]
			var lx = int(row[0])
			var wy = int(row[1])
			var lz = int(row[2])
			var block_id = int(row[3])
			voxel_data[Vector3i(lx, wy, lz)] = block_id
			block_count += 1

		chunks[chunk_pos] = voxel_data

	return {
		"ok": true,
		"chunks": chunks,
		"chunk_count": chunks.size(),
		"block_count": block_count,
		"y_range": parsed.get("y_range", []),
		"source": parsed.get("source", {}),
	}
