extends Node
## World-content generation verification driver (owner ask: "наполнить" the
## world with generated content -- ores/biomes/structures -- so it feels
## alive, not just flat terrain). Unlike the other Demo drivers this one
## doesn't drive player input at all: it waits for the initial chunk fill to
## finish, then SCANS the actually-generated voxel data + StructureGenerator's
## static placement counter and emits objective counts, so "content
## generates" is PROVEN from the real generated world rather than assumed
## from source.
##
## Only active with --world-content-demo (see Scripts/Tools/LaunchTest.gd).
## Inert otherwise, so it can never affect normal play. Shares the
## --showcase-demo pinned seed (424242, see VoxelWorld.gd) so the scan is
## reproducible run to run.

var voxel_world: Node = null
var _world_loaded := false
var _load_wait := 0.0
var _done := false

func _ready():
	if not OS.get_cmdline_user_args().has("--world-content-demo"):
		queue_free()
		return
	print("[WorldContent] driver active, waiting for world...")
	_find_world()

func _find_world():
	voxel_world = get_node_or_null("/root/World/VoxelWorld")
	if not voxel_world:
		await get_tree().create_timer(0.2).timeout
		_find_world()
		return
	if voxel_world.has_signal("initial_load_complete"):
		voxel_world.initial_load_complete.connect(_on_world_loaded)
		# Race guard: headless runs drain the whole chunk queue synchronously
		# (see VoxelWorld.gd's _drain_queue_budgeted), so the load may already
		# be complete before this connects -- read the flag directly too.
		if ("initial_load_done" in voxel_world) and voxel_world.initial_load_done:
			_world_loaded = true
	else:
		_world_loaded = true
	print("[WorldContent] voxel_world found, chunks so far=", voxel_world.chunks.size())

func _on_world_loaded():
	_world_loaded = true
	print("[WorldContent] world load complete signal received")

func _process(delta):
	if _done:
		return
	if not voxel_world:
		return
	_load_wait += delta
	if not _world_loaded and _load_wait < 45.0:
		return
	_done = true
	_scan_and_report()
	get_tree().quit()

func _scan_and_report() -> void:
	var ore_ids := {}
	for ore in Chunk.ORE_TABLE:
		ore_ids[ore.id] = true

	var ore_count := 0
	var biomes_seen := {}
	var chunk_count := 0

	for pos in voxel_world.chunks:
		var chunk = voxel_world.chunks[pos]
		if chunk == null or not is_instance_valid(chunk):
			continue
		chunk_count += 1
		for vpos in chunk.voxel_data:
			var t = chunk.voxel_data[vpos]
			if ore_ids.has(t):
				ore_count += 1
		# Sample biome at this chunk's center, same formula generate_data()
		# uses (world noise for height/temp, this chunk's own moisture_noise
		# for moisture -- both deterministic from world seed + chunk pos).
		var gx = pos.x * 16 + 8
		var gz = pos.y * 16 + 8
		var temp = voxel_world.noise.get_noise_2d(gx * 0.5, gz * 0.5)
		var moisture = chunk.moisture_noise.get_noise_2d(gx, gz)
		var biome = chunk.get_biome(temp, moisture)
		biomes_seen[biome] = true

	var structures_placed: int = StructureGenerator.placed_count

	print("[WorldContent] chunks_scanned=", chunk_count)
	print("[WorldContent] ore_count=", ore_count)
	print("[WorldContent] biomes_seen=", biomes_seen.size(), " (", biomes_seen.keys(), ")")
	print("[WorldContent] structures_placed=", structures_placed)

	if get_node_or_null("/root/Telemetry"):
		Telemetry.log_event("world_content_summary", {
			"chunks_scanned": chunk_count,
			"ore_count": ore_count,
			"biomes_seen": biomes_seen.size(),
			"biomes": biomes_seen.keys(),
			"structures_placed": structures_placed,
		})

	# Hard assertions -- objective pass/fail on the actually-scanned counts,
	# not eyeballed from the print lines above. assert() is active in the
	# debug/editor Godot binary these headless runs use (not an exported
	# release build), so a failure here aborts with a clear message.
	var ore_ok := ore_count > 0
	var biomes_ok := biomes_seen.size() >= 2
	var structures_ok := structures_placed > 0
	print("[WorldContent] ASSERT ore_count>0=", ore_ok,
		" biomes_seen>=2=", biomes_ok,
		" structures_placed>0=", structures_ok)
	assert(ore_ok, "WORLD CONTENT FAIL: ore_count == 0")
	assert(biomes_ok, "WORLD CONTENT FAIL: biomes_seen < 2")
	assert(structures_ok, "WORLD CONTENT FAIL: structures_placed == 0")
	print("[WorldContent] ALL ASSERTIONS PASSED")
