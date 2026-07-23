extends Node3D
class_name VoxelWorld

# ---- Loading-screen / paced chunk streaming ----
# Owner feedback (mid=644): "мир долго грузится" -- the WHOLE reason the
# world "loads for a long time" with a frozen screen is that update_chunks()
# used to build every chunk in render_distance synchronously inside a single
# _process() call: create_chunk() -> add_child() -> Chunk._ready() runs
# generate_data()+generate_mesh() (up to a few hundred thousand loop
# iterations per chunk) *before* add_child() returns, so nothing gets
# rendered until the whole batch is done. At the default render_distance=4
# in World.tscn that's 81 chunks in one frame.
#
# Fix: route chunk (re)builds through a queue that's drained at a small
# fixed budget per frame (see _drain_queue_budgeted), so the engine actually
# renders/presents a frame between chunk builds. Scripts/UI/LoadingScreen.gd
# polls initial_load_progress/initial_load_complete below to show a real
# (not-fake-timer) progress bar for the FIRST fill.
#
# Same machinery also fixes the unrelated-looking but same-root-cause report
# (mid=650): "лаг на изменении дальности прорисовки" -- GraphicsSettings.
# set_view_distance() bumps render_distance directly, and the old
# update_chunks() would then synchronously build every newly-in-range chunk
# in one frame too. Now that growth is queued+budgeted exactly like the
# initial load, so raising View Distance mid-game no longer hitches; only
# extra chunks progressively pop in over the next several frames instead.
signal initial_load_progress(loaded: int, total: int)
signal initial_load_complete()

# Chunks fully generated (data+mesh) per _process() tick once real gameplay
# is running (see _drain_queue_budgeted). Tunable: lower = smoother frame
# pacing but slower wall-clock fill; higher = faster fill but each frame
# costs more. Headless runs (automated tests/demo drivers -- see
# LaunchTest.gd) always drain the whole queue in one call instead, so
# existing --run-tests/--movement-demo/etc timing is unchanged; the loading
# screen never renders headless anyway.
#
# This is a flat cap on chunk BUILDS (create_chunk -> generate_data() +
# generate_mesh(), the expensive part), not scaled to render_distance/queue
# size (owner mid=654 wants View Distance selectable up to 100 -- see
# GraphicsSettings.VIEW_DISTANCE_MAX). The queue just gets longer at high
# view distance, never the per-frame BUILD cost.
#
# That doesn't mean per-frame cost is flat overall, though -- be precise:
# _sync_queue's double loop and _free_out_of_range_chunks's chunks.keys()
# scan both run every frame and are O(render_distance^2) (~40k at
# view_distance=100), and _sync_queue's sort_custom re-sorts the whole
# pending queue whenever anything new was queued. That's cheap bookkeeping
# (no chunk generation, just Vector2i math/dict lookups) at sane distances,
# but it's real work that DOES grow with render_distance, unlike the capped
# builds -- worth knowing if a future profiling pass finds per-frame cost
# higher than expected at very large distances. The honest tradeoff for
# builds specifically is wall-clock fill time, not frame hitches -- see
# GraphicsSettings.VIEW_DISTANCE_MAX's comment for why very large distances
# are still impractical today without LOD.
#
# Future-LOD note: create_chunk() below is the one place that would need to
# consult distance-from-player to pick a detail level (simplified mesh/no
# collision for far chunks). Nothing in the queue/budget mechanism assumes a
# fixed detail level, so that could plug in there without touching the
# pacing logic in this file.
const CHUNKS_PER_FRAME := 2

var initial_load_done := false
var initial_chunks_total := 0
var initial_chunks_loaded := 0

var _pending_queue: Array = [] # Array[Vector2i], nearest-to-player first
var _queued_set := {} # Vector2i -> true, membership guard vs double-queueing

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

	# Reuse the seed from a previous session if one was saved, so unedited
	# chunks regenerate identical terrain instead of a fresh random world
	# clashing with any previously-saved chunk snapshots (see SaveSystem's
	# save_world_seed/load_world_seed).
	# Reproducibility for the gameplay showcase/verification: --showcase-demo
	# pins a fixed seed so the terrain the driver is tuned against (and verified
	# on headless) is byte-identical to what gets rendered on 182 -- FastNoiseLite
	# is deterministic across platforms. Inert flag, same convention as the demo
	# drivers; never affects normal play.
	# --world-content-demo (Scripts/Testing/WorldContentDemoDriver.gd) shares
	# the same pinned seed as --showcase-demo: reproducible terrain so ore/
	# biome/structure counts can be tuned against a known-fixed world instead
	# of a fresh-random one every run.
	if OS.get_cmdline_user_args().has("--showcase-demo") or OS.get_cmdline_user_args().has("--world-content-demo"):
		noise.seed = 424242
	else:
		var saved_seed = SaveSystem.load_world_seed()
		if saved_seed != -1:
			noise.seed = saved_seed
		else:
			noise.seed = randi()
			SaveSystem.save_world_seed(noise.seed)
	noise.frequency = 0.01

func _process(_delta):
	# Wait for player and material before generating world
	if not player or not chunk_material:
		return

	var p_pos = player.global_position
	var center_chunk = Vector2i(int(floor(p_pos.x / 16.0)), int(floor(p_pos.z / 16.0)))

	# Free chunks the player/render-distance has left behind. Only once the
	# initial fill is done -- during the initial fill center_chunk shouldn't
	# move (player sits under the opaque loading screen), and culling a
	# still-queued position mid-fill would strand initial_chunks_loaded short
	# of initial_chunks_total, leaving the loading screen stuck.
	if initial_load_done:
		_free_out_of_range_chunks(center_chunk)

	_sync_queue(center_chunk)
	_drain_queue_budgeted()

# Reconciles "what should be loaded" (every chunk position within
# render_distance of center_chunk) against "what's already loaded or already
# queued", appending anything missing to _pending_queue. Runs every frame, so
# it transparently covers the initial fill (first call, queue starts empty),
# the player walking (new positions enter range), and render_distance
# changing at runtime (GraphicsSettings' View Distance slider) -- no special
# casing needed for any of those, and rapid slider drags are naturally
# coalesced since each frame just reconciles against whatever the current
# value is.
func _sync_queue(center_chunk: Vector2i) -> void:
	var queued_anything := false
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var pos = center_chunk + Vector2i(x, z)
			if not chunks.has(pos) and not _queued_set.has(pos):
				_pending_queue.append(pos)
				_queued_set[pos] = true
				queued_anything = true

	if queued_anything and _pending_queue.size() > 1:
		# Nearest-first: the ground under the player (or the chunk a slider
		# bump just brought into range nearest the camera) finishes first.
		_pending_queue.sort_custom(func(a, b):
			return (a - center_chunk).length_squared() < (b - center_chunk).length_squared()
		)

	# Latch the initial-load total exactly once, the first time anything is
	# queued from an empty world -- this is what LoadingScreen.gd's progress
	# bar is driven off of. Never reopens on later render-distance growth.
	if not initial_load_done and initial_chunks_total == 0 and _pending_queue.size() > 0:
		initial_chunks_total = _pending_queue.size()
		initial_load_progress.emit(0, initial_chunks_total)

func _drain_queue_budgeted() -> void:
	if _pending_queue.is_empty():
		return

	# Automated/headless runs (AutoTester, --movement-demo, --wave2-demo,
	# etc. via LaunchTest.gd) keep the old exact behavior: the whole queue
	# drains synchronously the moment it's populated, so nothing that already
	# assumes "the world exists a frame or two after host_game()" breaks. The
	# loading screen doesn't render in headless mode anyway.
	#
	# NOTE: OS.has_feature("headless") reads false even under `godot
	# --headless` in this project's build/runner -- see AutoTester.gd's
	# take_screenshot() for the same finding, verified there against
	# DisplayServer.get_name()/RenderingServer.get_rendering_device(). Use
	# the same reliable signal it settled on.
	var is_headless_run := DisplayServer.get_name() == "headless"
	var budget = _pending_queue.size() if is_headless_run else CHUNKS_PER_FRAME

	var n = 0
	while n < budget and not _pending_queue.is_empty():
		var pos = _pending_queue.pop_front()
		_queued_set.erase(pos)
		if not chunks.has(pos):
			create_chunk(pos)
		n += 1
		if not initial_load_done:
			initial_chunks_loaded += 1

	if not initial_load_done:
		initial_load_progress.emit(initial_chunks_loaded, initial_chunks_total)
		if _pending_queue.is_empty():
			initial_load_done = true
			initial_load_complete.emit()

# Cheap cull: drop any loaded chunk now outside the current render_distance
# box around center_chunk (e.g. View Distance slider moved down, or the
# player walked away). Chunk.gd's generation is fully deterministic from
# (chunk_position, noise seed) with no external random state, and any player
# edit was already persisted immediately in set_voxel() via
# SaveSystem.save_chunk(), so freeing an unedited or edited chunk here is
# always safe to regenerate/reload later -- nothing is lost.
func _free_out_of_range_chunks(center_chunk: Vector2i) -> void:
	for pos in chunks.keys():
		if absi(pos.x - center_chunk.x) > render_distance or absi(pos.y - center_chunk.y) > render_distance:
			var chunk = chunks[pos]
			if is_instance_valid(chunk):
				chunk.queue_free()
			chunks.erase(pos)
			if _queued_set.has(pos):
				_queued_set.erase(pos)
				_pending_queue.erase(pos)

# Kept as its own public method (unchanged behavior: builds everything
# missing in range synchronously, immediately) because MainMenuWorld.gd
# calls it directly via call_deferred() for the small decorative menu
# background world, bypassing the player-gated _process() above entirely.
# Real gameplay (World.tscn) no longer calls this from _process(); it uses
# the queued/budgeted path so the loading screen and settings-slider fix
# above apply.
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
		chunk.setup(pos, noise, chunk_material, self)
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
	elif type == 56: # Torch (light source; see TorchBlock.gd)
		spawn_block_entity(pos_i, "res://Scenes/Blocks/TorchBlock.tscn")
	elif type == 73: # Storage Chest (see ChestBlock.gd)
		spawn_block_entity(pos_i, "res://Scenes/Blocks/ChestBlock.tscn")

	if chunks.has(chunk_pos) and chunks[chunk_pos] != null:
		var chunk = chunks[chunk_pos]
		var local_x = x - chunk_x * 16
		var local_z = z - chunk_z * 16

		# Torch (56) is deliberately excluded here: unlike Furnace/Bed/
		# CraftingTable it has no solid voxel cube (see TorchBlock.gd) --
		# writing it into voxel_data would (a) double-render a textured
		# cube around the torch mesh above and (b) wrongly cull neighbor
		# faces as if the torch were solid. Placing/removing the torch is
		# entirely block_entities-driven (see the cleanup at the top of
		# this function, which already handles freeing/replacing it).
		if y >= 0 and y < 256 and type != 56:
			chunk.set_block(Vector3i(local_x, y, local_z), type)
			SaveSystem.save_chunk(chunk)
			# Chunk.set_block() only remeshes the chunk that owns the voxel.
			# When the edited voxel sits on a chunk border (local x/z == 0 or
			# 15) the neighbouring chunk's mesh was baked assuming this voxel's
			# OLD state, so its border faces go stale -- a face that should now
			# be exposed stays culled, or one that should be culled lingers.
			# That is the reported "блоки нету граней иногда" (esp. logs, which
			# trees scatter right up to chunk edges): the seam never regenerated
			# on edit. Remesh each affected neighbour so the seam stays correct.
			if local_x == 0: _remesh_neighbor(Vector2i(chunk_x - 1, chunk_z))
			elif local_x == 15: _remesh_neighbor(Vector2i(chunk_x + 1, chunk_z))
			if local_z == 0: _remesh_neighbor(Vector2i(chunk_x, chunk_z - 1))
			elif local_z == 15: _remesh_neighbor(Vector2i(chunk_x, chunk_z + 1))

# Re-bake a neighbouring chunk's mesh after a border edit (see set_voxel above).
# No-op if the neighbour isn't loaded / is still a placeholder / is mid-generation.
func _remesh_neighbor(cpos: Vector2i) -> void:
	if chunks.has(cpos):
		var c = chunks[cpos]
		if c != null and not c.is_generating:
			c.generate_mesh()

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
