extends Node
# FoliageRenderer -- ambient grass tufts + drifting leaves/petals autoload
# (owner ask, mid=667: "травы... и лепестки и листики" -- grass, petals,
# leaves).
#
# Same isolation rule as WeatherSystem.gd: a concurrent branch is reworking
# chunk streaming in World.gd/Chunk.gd, so this file never touches those
# scripts and never reads Chunk.voxel_data or VoxelWorld.chunks. Instead of
# scanning actual placed blocks for grass/leaf positions, it re-derives
# "what block would be here" from the same cheap noise formula World.gd's
# spawn_player() ALREADY duplicates (see that function's comment) and
# Chunk.gd's own generate_data()/get_biome() use:
#   height  = int((noise.get_noise_2d(gx, gz) + 1) * 32) + 64
#   biome   = get_biome(temp, moisture)  -- Tundra/Desert/Forest/Plains
# This is an O(1)-per-column read of VoxelWorld.noise (public var) with no
# dependency on chunk node lifecycle, mesh generation timing, or streaming
# state -- it works identically whether a chunk there is loaded, unloaded,
# or mid-stream. The known trade-off (documented, not hidden): it does NOT
# know about player edits (dug holes / placed blocks), same limitation
# World.gd's spawn_player() already accepts for the same reason.
#
# Consequences of that design:
#  - Grass tufts sit only where the formula says Forest/Plains biome +
#    surface would be a Grass block, matching Chunk.gd's actual placement
#    rule closely but not exactly (a player-modified column can drift).
#  - "Leaves near trees" / "petals near flowers" are NOT anchored to actual
#    StructureGenerator-placed trees/flowers (those come from a per-chunk
#    seeded RNG sequence that would be fragile to replay exactly). Instead
#    this spawns ambient drift emitters at a density-matched sampling of
#    Forest-biome columns (leaves) and Forest/Plains columns (petals) --
#    i.e. "forest air has falling leaves in it", not "this exact tree drops
#    these exact leaves". Called out explicitly as the stubbed-vs-full
#    distinction for this PR.

const GROUP_VOXEL_WORLD := "voxel_world"

const BLADE_HEIGHT := 0.55
const BLADE_WIDTH := 0.5

const FOLIAGE_RADIUS_CHUNKS_BASE := 2 # ~32 blocks; independent of (and capped by) render_distance
const MAX_GRASS_INSTANCES_BASE := 5000
const GRASS_INCLUDE_PROB := 0.32
const LEAF_ANCHOR_PROB := 0.05   # per-column roll, at most one anchor kept per chunk anyway
const PETAL_ANCHOR_PROB := 0.05
const CANOPY_HEIGHT_OFFSET := 5.0 # leaves drift as if falling from an unseen canopy above
const FLOWER_HEIGHT_OFFSET := 1.4
const SCAN_INTERVAL := 1.75

const LEAF_EMITTER_POOL_SIZE := 8
const PETAL_EMITTER_POOL_SIZE := 6

# Palette matches TextureGenerator.gd's actual block colors (grass top
# ~(0.2,0.8,0.2), tall-grass stalks ~(0.2,0.6-0.7,0.2)) so tufts read as the
# same plant, just a few shade variants for visual variety.
const GRASS_COLORS := [
	Color(0.22, 0.78, 0.22), Color(0.18, 0.66, 0.20), Color(0.30, 0.86, 0.26),
]
# Autumn-leaf palette -- deliberately NOT plain green so falling leaves read
# as a distinct effect against green grass/canopy (bright/chunky per the
# owner's art direction, not a subtle same-color blend).
const LEAF_COLORS := [
	Color(0.85, 0.62, 0.14), Color(0.74, 0.33, 0.10), Color(0.90, 0.80, 0.20), Color(0.35, 0.55, 0.16),
]
# Exact flower colors from TextureGenerator.gd (Red/Yellow/Blue/Pink flower
# blocks) so drifting petals match the flowers already in the world.
const PETAL_COLORS := [
	Color(0.9, 0.0, 0.0), Color(1.0, 1.0, 0.0), Color(0.2, 0.4, 0.95), Color(0.95, 0.4, 0.75),
]

var _grass_mmi: MultiMeshInstance3D
var _leaf_emitters: Array[GPUParticles3D] = []
var _petal_emitters: Array[GPUParticles3D] = []
var _scan_timer: float = 0.0
var _moisture_noise: FastNoiseLite
var _moisture_seed_base: int = -1
var _last_logged_grass_count: int = -1

func _ready() -> void:
	_grass_mmi = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.mesh = _build_blade_mesh()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 0
	_grass_mmi.multimesh = mm
	_grass_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://Shaders/GrassWind.gdshader")
	_grass_mmi.material_override = shader_mat
	add_child(_grass_mmi)

	for i in LEAF_EMITTER_POOL_SIZE:
		var e := _make_drift_particles()
		add_child(e)
		_leaf_emitters.append(e)
	for i in PETAL_EMITTER_POOL_SIZE:
		var e := _make_drift_particles()
		add_child(e)
		_petal_emitters.append(e)

func _process(delta: float) -> void:
	if not _foliage_enabled_setting():
		if _grass_mmi.multimesh.instance_count != 0:
			_grass_mmi.multimesh.instance_count = 0
		_idle_all_emitters()
		return

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_rescan()
		_scan_timer = SCAN_INTERVAL

func _foliage_enabled_setting() -> bool:
	if "foliage_enabled" in GraphicsSettings:
		return GraphicsSettings.foliage_enabled
	return true

func _quality_factor() -> float:
	if "view_distance" in GraphicsSettings:
		return clampf(float(GraphicsSettings.view_distance) / 8.0, 0.35, 1.0)
	return 0.7

func _idle_all_emitters() -> void:
	for e in _leaf_emitters:
		e.visible = false
		e.emitting = false
	for e in _petal_emitters:
		e.visible = false
		e.emitting = false

# ---- Scan + placement ----

func _rescan() -> void:
	var cam := get_viewport().get_camera_3d()
	var voxel_world := get_tree().get_first_node_in_group(GROUP_VOXEL_WORLD)
	if not cam or not voxel_world or not ("noise" in voxel_world) or voxel_world.noise == null:
		_grass_mmi.multimesh.instance_count = 0
		_idle_all_emitters()
		return

	_ensure_moisture_noise(voxel_world.noise)

	var quality := _quality_factor()
	var radius_chunks := clampi(int(round(FOLIAGE_RADIUS_CHUNKS_BASE * quality)) , 1, FOLIAGE_RADIUS_CHUNKS_BASE)
	if "view_distance" in GraphicsSettings:
		radius_chunks = mini(radius_chunks, maxi(1, GraphicsSettings.view_distance))
	var stride := 1 if quality > 0.7 else 2 # coarser column sampling at lower quality tiers
	var max_grass := maxi(200, int(MAX_GRASS_INSTANCES_BASE * quality))

	var cam_chunk := Vector2i(int(floor(cam.global_position.x / 16.0)), int(floor(cam.global_position.z / 16.0)))
	var chunk_coords: Array[Vector2i] = []
	for cx in range(-radius_chunks, radius_chunks + 1):
		for cz in range(-radius_chunks, radius_chunks + 1):
			chunk_coords.append(cam_chunk + Vector2i(cx, cz))
	chunk_coords.sort_custom(func(a, b): return cam_chunk.distance_squared_to(a) < cam_chunk.distance_squared_to(b))

	var grass_transforms: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	var leaf_anchors: Array = [] # Array of [Vector3, Color]
	var petal_anchors: Array = []

	for chunk_pos in chunk_coords:
		if grass_transforms.size() >= max_grass and leaf_anchors.size() >= LEAF_EMITTER_POOL_SIZE and petal_anchors.size() >= PETAL_EMITTER_POOL_SIZE:
			break
		var got_leaf_this_chunk := false
		var got_petal_this_chunk := false
		for lx in range(0, 16, stride):
			for lz in range(0, 16, stride):
				var gx := chunk_pos.x * 16 + lx
				var gz := chunk_pos.y * 16 + lz
				var biome := _guess_biome(voxel_world.noise, gx, gz)
				if biome != "Forest" and biome != "Plains":
					continue

				if grass_transforms.size() < max_grass and _hash01(gx, gz, 17) < GRASS_INCLUDE_PROB:
					var top_y := float(_surface_height(voxel_world.noise, gx, gz) + 1)
					var jx := (_hash01(gx, gz, 3) - 0.5) * 0.8
					var jz := (_hash01(gx, gz, 5) - 0.5) * 0.8
					var pos := Vector3(float(gx) + 0.5 + jx, top_y, float(gz) + 0.5 + jz)
					var yaw := _hash01(gx, gz, 7) * TAU
					var scale := lerpf(0.75, 1.15, _hash01(gx, gz, 11))
					var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
					grass_transforms.append(Transform3D(basis, pos))
					grass_colors.append(GRASS_COLORS[int(_hash01(gx, gz, 13) * GRASS_COLORS.size()) % GRASS_COLORS.size()])

				if biome == "Forest" and not got_leaf_this_chunk and leaf_anchors.size() < LEAF_EMITTER_POOL_SIZE and _hash01(gx, gz, 23) < LEAF_ANCHOR_PROB:
					var h2 := _surface_height(voxel_world.noise, gx, gz)
					var lcol: Color = LEAF_COLORS[int(_hash01(gx, gz, 19) * LEAF_COLORS.size()) % LEAF_COLORS.size()]
					leaf_anchors.append([Vector3(float(gx) + 0.5, float(h2 + 1) + CANOPY_HEIGHT_OFFSET, float(gz) + 0.5), lcol])
					got_leaf_this_chunk = true

				if not got_petal_this_chunk and petal_anchors.size() < PETAL_EMITTER_POOL_SIZE and _hash01(gx, gz, 29) < PETAL_ANCHOR_PROB:
					var h3 := _surface_height(voxel_world.noise, gx, gz)
					var pcol: Color = PETAL_COLORS[int(_hash01(gx, gz, 31) * PETAL_COLORS.size()) % PETAL_COLORS.size()]
					petal_anchors.append([Vector3(float(gx) + 0.5, float(h3 + 1) + FLOWER_HEIGHT_OFFSET, float(gz) + 0.5), pcol])
					got_petal_this_chunk = true

	_apply_grass(grass_transforms, grass_colors)
	_apply_emitters(_leaf_emitters, leaf_anchors)
	_apply_emitters(_petal_emitters, petal_anchors)

	# Cheap visibility into placement results without needing eyes on a
	# render -- useful headless (e.g. this project's podman/Xvfb capture
	# recipe, see tools/verify_headless.sh) to tell "found nothing to place"
	# apart from "placed things but they didn't render".
	if grass_transforms.size() != _last_logged_grass_count:
		print("FoliageRenderer: grass=", grass_transforms.size(), " leaf_anchors=", leaf_anchors.size(), " petal_anchors=", petal_anchors.size(), " radius_chunks=", radius_chunks)
		_last_logged_grass_count = grass_transforms.size()

func _apply_grass(transforms: Array[Transform3D], colors: Array[Color]) -> void:
	var mm := _grass_mmi.multimesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

func _apply_emitters(pool: Array[GPUParticles3D], anchors: Array) -> void:
	for i in pool.size():
		var e := pool[i]
		if i < anchors.size():
			var data: Array = anchors[i]
			e.global_position = data[0]
			# draw_pass_1's static type is the base Mesh class (no .material
			# member) -- cast to PrimitiveMesh (QuadMesh's actual base, set
			# in _make_drift_particles) to get typed access back.
			var mat: StandardMaterial3D = (e.draw_pass_1 as PrimitiveMesh).material
			mat.albedo_color = data[1]
			var was_idle := not e.emitting
			e.visible = true
			e.emitting = true
			if was_idle:
				e.restart()
		else:
			e.visible = false
			e.emitting = false

# ---- Noise/biome (deliberately duplicated -- see file header) ----

func _ensure_moisture_noise(noise: FastNoiseLite) -> void:
	if _moisture_noise and _moisture_seed_base == noise.seed:
		return
	_moisture_noise = FastNoiseLite.new()
	_moisture_noise.seed = noise.seed + 12345 # mirrors Chunk.gd's setup()
	_moisture_noise.frequency = 0.005
	_moisture_seed_base = noise.seed

func _surface_height(noise: FastNoiseLite, gx: int, gz: int) -> int:
	return int((noise.get_noise_2d(gx, gz) + 1) * 32) + 64

func _guess_biome(noise: FastNoiseLite, gx: int, gz: int) -> String:
	# Mirrors Chunk.gd's get_biome() exactly (same thresholds) -- duplicated
	# rather than called so this file has zero dependency on a Chunk
	# instance existing. Purely cosmetic if it ever drifts from Chunk.gd:
	# worst case, a tuft/emitter appears where the "real" biome would
	# actually be Desert/Tundra, which is a placement quirk, not a crash.
	var temp := noise.get_noise_2d(gx * 0.5, gz * 0.5)
	var moisture := _moisture_noise.get_noise_2d(gx, gz)
	if temp < -0.2:
		return "Tundra"
	elif temp > 0.4:
		return "Desert" if moisture < -0.1 else "Forest"
	else:
		return "Forest" if moisture > 0.05 else "Plains"

func _hash01(x: int, z: int, salt: int) -> float:
	# Deterministic scatter hash (classic integer mix) -- same (x,z,salt)
	# always gives the same value, so tufts/anchors don't jitter between
	# rescans as the camera moves in and out of range.
	var n := x * 374761393 + z * 668265263 + salt * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0x7fffffff) / float(0x7fffffff)

# ---- Mesh / particle construction (fully procedural, no external assets) ----

func _build_blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := BLADE_HEIGHT
	var w := BLADE_WIDTH * 0.5
	# Two crossed quads (classic voxel-game grass sprite) so a tuft reads
	# from any horizontal angle without needing to billboard. cull_disabled
	# in GrassWind.gdshader renders both faces, so only one winding per quad
	# is needed here.
	for angle in [0.0, PI * 0.5]:
		var right := Vector3(cos(angle), 0, sin(angle)) * w
		var normal := Vector3(-sin(angle), 0, cos(angle))
		var p0 := -right
		var p1 := right
		var p2 := right + Vector3(0, h, 0)
		var p3 := -right + Vector3(0, h, 0)
		st.set_normal(normal)
		st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
		st.set_normal(normal)
		st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p3)
	return st.commit()

func _make_drift_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.lifetime = 8.0
	p.amount = 12
	p.visible = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-6, -8, -6), Vector3(12, 16, 12))

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.18, 0.18)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.7, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = mat
	p.draw_pass_1 = mesh

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 2.5
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 60.0
	pm.gravity = Vector3(0, -0.35, 0)
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 1.5
	p.process_material = pm
	p.local_coords = false
	return p
