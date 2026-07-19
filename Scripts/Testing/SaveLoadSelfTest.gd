extends SceneTree
## Standalone headless self-test for the world persistence wiring that
## fixes "SaveSystem.save_chunk/load_chunk exist but are never called, so
## world edits aren't persisted at all": see
##   - Scripts/Autoload/SaveSystem.gd  (save_world_seed/load_world_seed)
##   - Scripts/World/Chunk.gd          (generate_data() load-before-gen)
##   - Scripts/World/VoxelWorld.gd     (_ready() seed reuse, set_voxel()
##                                       re-enabled SaveSystem.save_chunk)
##
## Drives the REAL gameplay call path -- VoxelWorld.create_chunk() and
## VoxelWorld.set_voxel(), the same functions dig/place input goes through
## -- rather than calling SaveSystem directly, since the bug was
## never-called wiring, not broken SaveSystem read/write logic itself.
##
## Run with:
##   godot --headless --path . --script res://Scripts/Testing/SaveLoadSelfTest.gd
##
## Exits 0 if every check passes, 1 otherwise (CI-friendly).

# A chunk coordinate far outside anywhere a real playthrough or the CI
# import-check would generate, so this test's save file can never collide
# with a real save. Cleaned up before AND after the run.
const TEST_CHUNK_POS := Vector2i(31337, 31337)

func _initialize() -> void:
	print("[SelfTest] starting save/load self-test")
	_cleanup_test_files()

	var results: Array = []

	# --- Session 1: fresh world, nothing saved yet -> procedural gen runs ---
	var world = Node3D.new()
	world.set_script(load("res://Scripts/World/VoxelWorld.gd"))
	root.add_child(world)
	await process_frame
	await process_frame
	await process_frame # let TextureGenerator's own _ready() set chunk_material

	results.append(["chunk_material assigned by TextureGenerator", world.chunk_material != null])

	world.create_chunk(TEST_CHUNK_POS)
	await process_frame
	await process_frame

	var chunk_a = world.chunks.get(TEST_CHUNK_POS)
	results.append(["chunk A created", chunk_a != null])
	results.append(["chunk A proc-gen populated voxel_data", chunk_a != null and not chunk_a.voxel_data.is_empty()])

	# Bedrock at y=0 is always Stone(3) from proc-gen for every (x,z) in a
	# fresh chunk (see Chunk.gd generate_data() "Bedrock" pass) -- a
	# deterministic pre-edit fact we can dig away and check for.
	var dig_local := Vector3i(4, 0, 4)
	var dig_global_x = TEST_CHUNK_POS.x * 16 + dig_local.x
	var dig_global_z = TEST_CHUNK_POS.y * 16 + dig_local.z
	results.append(["pre-edit: bedrock present at dig target", chunk_a.voxel_data.get(dig_local) == 3])

	# y=200 is far above all terrain/structure generation (~64-96) --
	# guaranteed empty pre-edit, safe as a "place" target.
	var place_local := Vector3i(7, 200, 7)
	var place_global_x = TEST_CHUNK_POS.x * 16 + place_local.x
	var place_global_z = TEST_CHUNK_POS.y * 16 + place_local.z
	results.append(["pre-edit: place target empty", not chunk_a.voxel_data.has(place_local)])

	# --- Edit via the real production call path: VoxelWorld.set_voxel()
	# (the same entry point dig/place input calls). Exercises
	# chunk.set_block() AND the now-re-enabled SaveSystem.save_chunk() call
	# in the same statement (VoxelWorld.gd set_voxel()). ---
	world.set_voxel(Vector3(dig_global_x, 0, dig_global_z), 0)        # dig away bedrock
	world.set_voxel(Vector3(place_global_x, 200, place_global_z), 77) # place a block

	results.append(["post-edit: dig removed the block", not chunk_a.voxel_data.has(dig_local)])
	results.append(["post-edit: place added the block", chunk_a.voxel_data.get(place_local) == 77])

	var save_path = "user://saves/world1/chunk_%d_%d.dat" % [TEST_CHUNK_POS.x, TEST_CHUNK_POS.y]
	results.append(["save file written to disk after edit", FileAccess.file_exists(save_path)])

	# --- Session 2 (same process, same world/seed): recreate the chunk at
	# the same coordinate through the same production entry point
	# (VoxelWorld.create_chunk() -> Chunk._ready() -> generate_data()).
	# This is the "reload between sessions" moment. ---
	world.create_chunk(TEST_CHUNK_POS)
	await process_frame
	await process_frame

	var chunk_b = world.chunks.get(TEST_CHUNK_POS)
	results.append(["reload: chunk B created", chunk_b != null])
	results.append(["reload: loaded from save (not empty)", chunk_b != null and not chunk_b.voxel_data.is_empty()])
	results.append(["reload: dug block stayed gone", chunk_b != null and not chunk_b.voxel_data.has(dig_local)])
	results.append(["reload: placed block persisted", chunk_b != null and chunk_b.voxel_data.get(place_local) == 77])

	var all_pass := true
	for r in results:
		var ok: bool = r[1]
		if not ok:
			all_pass = false
		print("[SelfTest] ", ("PASS" if ok else "FAIL"), " - ", r[0])

	print("[SelfTest] RESULT: ", ("ALL PASS" if all_pass else "SOME FAILED"))

	world.queue_free()
	await process_frame
	_cleanup_test_files()
	quit(0 if all_pass else 1)

func _cleanup_test_files() -> void:
	var chunk_path = "user://saves/world1/chunk_%d_%d.dat" % [TEST_CHUNK_POS.x, TEST_CHUNK_POS.y]
	if FileAccess.file_exists(chunk_path):
		DirAccess.remove_absolute(chunk_path)
