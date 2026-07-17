extends Node3D
class_name TrainTrackBuilder

## FIRST-CUT rail + train system for VoxelWorldCraft.
##
## Reused from megumi-joy/Low-Poly-City-Delivery's road-generator approach
## (scripts/world/train_track_generator.gd in that repo): a Path3D holds a
## Curve3D route; CSGPolygon3D nodes in MODE_PATH extrude a cross-section
## along that curve to build the rails (and, here, a ballast bed); a
## PathFollow3D with ROTATION_ORIENTED carries the locomotive. Sleepers/ties
## and the locomotive mesh are new for this voxel-terrain first cut.
##
## Runtime-only (deliberately NOT @tool): it builds procedurally in
## _ready(), the same pattern VoxelWorld/Chunk already use for terrain, so
## it plays nicely with `--headless --import` (no editor-only code paths to
## misfire during import) and with the podman Movie Maker recording flow.
##
## Terrain-height matching: VoxelWorld/Chunk.gd computes each column's
## topmost solid block as
##   visual_height = int((noise.get_noise_2d(x, z) + 1) * 32) + 64
## and that block's walkable top face sits at world Y = visual_height + 1
## (Chunk.gd fills y in range(visual_height + 1), and the UP face of a unit
## cube at integer Y sits at local y=1, i.e. world Y = block_y + 1). This
## script samples the SAME `noise` instance the sibling VoxelWorld already
## seeded (not a fresh one), so the rails track the actual generated terrain
## rather than a guessed constant height.

@export var voxel_world_path: NodePath = NodePath("../VoxelWorld")

## When true, this builder also drops in and activates its own Camera3D
## framing the loop -- used by the standalone recording scene (TrainDemo.tscn)
## which has no Player. Leave false when wired into World.tscn so it never
## fights the Player's first-person camera.
@export var auto_frame_camera: bool = false

@export var track_center: Vector2 = Vector2.ZERO
@export var radius_x: float = 20.0
@export var radius_z: float = 14.0
@export var num_points: int = 8
@export var rail_gauge: float = 1.5       # half-gauge: centerline -> each rail
@export var rail_clearance: float = 0.3   # rails sit this far above the sampled surface
@export var sleeper_spacing: float = 2.2  # metres between ties
@export var train_speed: float = 10.0     # m/s along the curve
@export var chunk_margin_blocks: int = 8  # extra blocks force-loaded beyond the loop's bbox

var _voxel_world: VoxelWorld
var _built := false

func _ready() -> void:
	_voxel_world = get_node_or_null(voxel_world_path) as VoxelWorld
	if not _voxel_world:
		push_warning("[TrainTrackBuilder] voxel_world not found at %s -- track not built." % [voxel_world_path])
		return
	_build()

func _build() -> void:
	if _built:
		return
	_built = true

	# TextureGenerator (a child VoxelWorld adds itself in its own _ready())
	# sets chunk_material independently of any Player -- but wait a few
	# frames just in case, so forced chunks don't render unlit/white.
	var tries := 0
	while _voxel_world.chunk_material == null and tries < 300:
		await get_tree().process_frame
		tries += 1
	if _voxel_world.chunk_material == null:
		push_warning("[TrainTrackBuilder] chunk_material still null after waiting -- terrain under the track may render unlit.")

	var pts2d := _get_loop_points()
	_ensure_chunks_loaded(pts2d)

	var path := _build_curve(pts2d)
	add_child(path)

	_build_rails(path)
	_build_sleepers(path)
	_spawn_train(path)

	if auto_frame_camera:
		_add_demo_camera(path)

	print("[TrainTrackBuilder] built loop, baked length=", path.curve.get_baked_length())

func _get_loop_points() -> Array:
	var pts := []
	for i in range(num_points):
		var t := (float(i) / float(num_points)) * TAU
		pts.append(Vector2(
			track_center.x + cos(t) * radius_x,
			track_center.y + sin(t) * radius_z
		))
	return pts

func _surface_y(wx: float, wz: float) -> float:
	var ix := int(round(wx))
	var iz := int(round(wz))
	var n := _voxel_world.noise.get_noise_2d(ix, iz)
	var visual_height := int((n + 1.0) * 32.0) + 64
	return float(visual_height + 1)  # top face of the topmost solid block

func _ensure_chunks_loaded(pts2d: Array) -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p in pts2d:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_z = min(min_z, p.y)
		max_z = max(max_z, p.y)
	min_x -= chunk_margin_blocks
	max_x += chunk_margin_blocks
	min_z -= chunk_margin_blocks
	max_z += chunk_margin_blocks

	var c0 := Vector2i(int(floor(min_x / 16.0)), int(floor(min_z / 16.0)))
	var c1 := Vector2i(int(floor(max_x / 16.0)), int(floor(max_z / 16.0)))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cpos := Vector2i(cx, cz)
			if not _voxel_world.chunks.has(cpos):
				_voxel_world.create_chunk(cpos)

func _build_curve(pts2d: Array) -> Path3D:
	var path := Path3D.new()
	path.name = "RailPath"

	# Sample world-space 3D points (with real terrain height) first, then
	# derive tangents from neighbours in 3D so the curve's slope follows the
	# ground instead of staying artificially flat.
	var pts3d: Array = []
	for p in pts2d:
		var y := _surface_y(p.x, p.y) + rail_clearance
		pts3d.append(Vector3(p.x, y, p.y))
	# Close the loop explicitly (duplicate the first point at the end) so
	# PathFollow3D's `loop = true` wraps seamlessly with no visible teleport.
	pts3d.append(pts3d[0])

	var n := pts3d.size()
	var curve := Curve3D.new()
	const TANGENT_SCALE := 0.25
	for i in range(n):
		var prev: Vector3 = pts3d[(i - 1 + n) % n]
		var next: Vector3 = pts3d[(i + 1) % n]
		var tangent := (next - prev) * TANGENT_SCALE
		# Last point mirrors the first point's tangent for a clean close.
		if i == n - 1:
			var first_prev: Vector3 = pts3d[n - 2]
			var first_next: Vector3 = pts3d[1]
			tangent = (first_next - first_prev) * TANGENT_SCALE
		curve.add_point(pts3d[i], -tangent, tangent)

	path.curve = curve
	return path

func _build_rails(path: Path3D) -> void:
	var bed := CSGPolygon3D.new()
	bed.name = "Ballast"
	bed.mode = CSGPolygon3D.MODE_PATH
	bed.path_interval_type = CSGPolygon3D.PATH_INTERVAL_SUBDIVIDE
	bed.path_interval = 2.0
	bed.path_local = false
	bed.polygon = PackedVector2Array([
		Vector2(-rail_gauge - 0.9, -0.25),
		Vector2(-rail_gauge - 0.4,  0.0),
		Vector2( rail_gauge + 0.4,  0.0),
		Vector2( rail_gauge + 0.9, -0.25),
	])
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = Color(0.32, 0.28, 0.22)
	bed.material = bed_mat
	path.add_child(bed)
	bed.path_node = NodePath("..")

	_add_rail(path, -rail_gauge, "LeftRail")
	_add_rail(path, rail_gauge, "RightRail")

func _add_rail(path: Path3D, offset_x: float, r_name: String) -> void:
	var poly := CSGPolygon3D.new()
	poly.name = r_name
	poly.mode = CSGPolygon3D.MODE_PATH
	poly.path_interval_type = CSGPolygon3D.PATH_INTERVAL_SUBDIVIDE
	poly.path_interval = 2.0
	poly.path_local = false
	poly.polygon = PackedVector2Array([
		Vector2(offset_x - 0.08, 0.0),
		Vector2(offset_x + 0.08, 0.0),
		Vector2(offset_x + 0.08, 0.22),
		Vector2(offset_x - 0.08, 0.22),
	])
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.55, 0.55, 0.6)
	rail_mat.metallic = 0.8
	rail_mat.roughness = 0.35
	poly.material = rail_mat
	path.add_child(poly)
	poly.path_node = NodePath("..")

func _build_sleepers(path: Path3D) -> void:
	var curve := path.curve
	var total_len := curve.get_baked_length()
	if total_len <= 0.0:
		return

	var sleepers := Node3D.new()
	sleepers.name = "Sleepers"
	path.add_child(sleepers)

	var tie_mesh := BoxMesh.new()
	tie_mesh.size = Vector3(rail_gauge * 2.0 + 0.6, 0.12, 0.35)
	var tie_mat := StandardMaterial3D.new()
	tie_mat.albedo_color = Color(0.32, 0.2, 0.12)

	var d := 0.0
	while d < total_len:
		var pos := curve.sample_baked(d)
		var ahead_d: float = min(d + 0.5, total_len)
		var behind_d: float = max(d - 0.5, 0.0)
		var forward: Vector3 = (curve.sample_baked(ahead_d) - curve.sample_baked(behind_d))
		if forward.length() < 0.001:
			forward = Vector3.FORWARD
		forward = forward.normalized()

		var tie := MeshInstance3D.new()
		tie.mesh = tie_mesh
		tie.material_override = tie_mat
		sleepers.add_child(tie)
		tie.global_position = pos + Vector3.UP * -0.06
		# Orient tie's local X (its long axis) across the rails, i.e.
		# perpendicular to the direction of travel.
		var right := forward.cross(Vector3.UP)
		if right.length() < 0.001:
			right = Vector3.RIGHT
		right = right.normalized()
		var up := right.cross(forward).normalized()
		tie.global_transform.basis = Basis(right, up, forward)

		d += sleeper_spacing

func _spawn_train(path: Path3D) -> PathFollow3D:
	var pf := PathFollow3D.new()
	pf.name = "TrainHead"
	pf.loop = true
	pf.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path.add_child(pf)

	var mover := preload("res://Scripts/World/TrainMover.gd").new()
	mover.name = "TrainMover"
	mover.speed = train_speed
	pf.add_child(mover)

	_build_locomotive(pf)
	return pf

func _build_locomotive(parent: Node3D) -> void:
	var loco := Node3D.new()
	loco.name = "Locomotive"
	parent.add_child(loco)

	var wheel_r := 0.45
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = wheel_r
	wheel_mesh.bottom_radius = wheel_r
	wheel_mesh.height = 0.22
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.08, 0.08, 0.09)
	for side in [-1.0, 1.0]:
		for lengthwise in [-1.9, 1.9]:
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh
			wheel.material_override = wheel_mat
			wheel.rotation_degrees = Vector3(0, 0, 90)
			wheel.position = Vector3(side * (rail_gauge - 0.15), wheel_r, lengthwise)
			loco.add_child(wheel)

	# Boxy body -- bottom rests on top of the wheels.
	var body_size := Vector3(2.6, 1.6, 5.5)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = body_size
	body.mesh = body_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.55, 0.1, 0.08)
	body.material_override = body_mat
	body.position = Vector3(0, wheel_r * 2.0 + body_size.y * 0.5, 0)
	loco.add_child(body)
	var body_top: float = body.position.y + body_size.y * 0.5

	# Cab -- rear (+Z; PathFollow3D forward is -Z).
	var cab_size := Vector3(2.4, 1.7, 2.0)
	var cab := MeshInstance3D.new()
	var cab_mesh := BoxMesh.new()
	cab_mesh.size = cab_size
	cab.mesh = cab_mesh
	var cab_mat := StandardMaterial3D.new()
	cab_mat.albedo_color = Color(0.12, 0.12, 0.15)
	cab.material_override = cab_mat
	cab.position = Vector3(0, body_top + cab_size.y * 0.5, 1.6)
	loco.add_child(cab)

	# Funnel/chimney -- front (-Z).
	var funnel := MeshInstance3D.new()
	var funnel_mesh := CylinderMesh.new()
	funnel_mesh.top_radius = 0.28
	funnel_mesh.bottom_radius = 0.4
	funnel_mesh.height = 1.3
	funnel.mesh = funnel_mesh
	var funnel_mat := StandardMaterial3D.new()
	funnel_mat.albedo_color = Color(0.1, 0.1, 0.11)
	funnel.material_override = funnel_mat
	funnel.position = Vector3(0, body_top + funnel_mesh.height * 0.5, -1.8)
	loco.add_child(funnel)

func _add_demo_camera(path: Path3D) -> void:
	var pts := path.curve.get_baked_points()
	if pts.is_empty():
		return
	var aabb := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		aabb = aabb.expand(p)
	var center := aabb.get_center()
	var span: float = max(aabb.size.x, aabb.size.z)

	var cam := Camera3D.new()
	cam.name = "DemoCamera"
	add_child(cam)
	cam.global_position = center + Vector3(span * 0.42, span * 0.3 + 6.0, span * 0.42)
	cam.look_at(center, Vector3.UP)
	cam.current = true
