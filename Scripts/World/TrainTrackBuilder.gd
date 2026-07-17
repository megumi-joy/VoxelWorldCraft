extends Node3D
class_name TrainTrackBuilder

## FIRST-CUT rail + train system for VoxelWorldCraft.
##
## Reused from megumi-joy/Low-Poly-City-Delivery's road-generator approach
## (scripts/world/train_track_generator.gd in that repo): a Path3D holds a
## Curve3D route; CSGPolygon3D nodes in MODE_PATH extrude a cross-section
## along that curve to build the rails (and, here, a ballast bed); a
## PathFollow3D carries the locomotive. Sleepers/ties and the locomotive mesh
## are new for this voxel-terrain first cut.
##
## Both the rails (CSGPolygon3D.path_rotation) and the locomotive
## (PathFollow3D.rotation_mode) are deliberately pinned to yaw-only rotation
## (PATH_ROTATION_PATH / ROTATION_Y) rather than each following its own
## independent full-3D orientation frame (the PATH_FOLLOW / ROTATION_ORIENTED
## defaults) -- on this terrain-following, sloped loop those two frames don't
## necessarily agree, which is what made the locomotive appear to float
## above the rails before this was pinned down.
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
##
## RAILBED GRADING (cut/fill), not a curve draped over raw terrain: sampling
## the raw per-column height at only a handful of widely-spaced points (the
## old `num_points`-corner loop) and spline-interpolating between them is
## what let the rails float over dips and cut through bumps -- the smooth
## curve and the blocky ground it was drawn over had no relationship past
## those few sample points. The fix is a real railway cut/fill:
## `_get_dense_route_points()` walks the route at ~1-block spacing;
## `_compute_graded_bed_heights()` smooths that dense height sample and then
## slope-limits it (see `max_grade_per_block`) into a gently graded bed
## profile; `_carve_railbed()` then edits the actual voxel terrain in a
## strip a few blocks wide (`bed_half_width_blocks`) under the route --
## clearing blocks above the bed (cutting through hills) and filling solid
## blocks up to the bed (filling across dips) -- via Chunk.set_block_silent
## + a single Chunk.generate_mesh() per touched chunk. The rail curve is
## then drawn at that same graded bed height, so it sits on a continuous
## strip of solid ground for the whole loop, not just at the sample points.

@export var voxel_world_path: NodePath = NodePath("../VoxelWorld")

## When true, this builder also drops in and activates its own Camera3D
## framing the loop -- used by the standalone recording scenes (TrainDemo*.tscn)
## which have no Player. Leave false when wired into World.tscn so it never
## fights the Player's first-person camera.
@export var auto_frame_camera: bool = false

## When auto_frame_camera is true, choose an elevated 3/4 view (false) or a
## straight-down overhead view (true).
@export var top_down_camera: bool = false

@export var track_center: Vector2 = Vector2.ZERO
@export var radius_x: float = 20.0
@export var radius_z: float = 14.0
@export var rail_gauge: float = 1.5       # half-gauge: centerline -> each rail
@export var rail_clearance: float = 0.3   # rails sit this far above the graded bed surface
@export var sleeper_spacing: float = 2.2  # metres between ties
@export var train_speed: float = 10.0     # m/s along the curve
@export var chunk_margin_blocks: int = 8  # extra blocks force-loaded beyond the loop's bbox
@export var dense_spacing: float = 1.0    # metres between route samples used for grading -- ~1 block, so the bed is carved essentially column-by-column along the whole route, not just at a handful of corners
@export var max_grade_per_block: float = 0.35  # max |Delta bed height| per block of route travel -- keeps the embankment a gentle railway grade instead of a staircase
@export var bed_half_width_blocks: int = 3     # embankment half-width in blocks (total carved strip = 2*this+1 wide); must comfortably cover the ballast cross-section, which spans about +/-(rail_gauge+0.9)

const RAIL_HEAD_HEIGHT := 0.22  # rail cross-section height above the curve (see _add_rail)
const BED_FILL_BLOCK := 3         # Stone -- compacted cut/fill embankment material
const BED_CLEAR_MARGIN := 24      # blocks above the bed surface to clear -- covers hills plus any trees/structures poking into the corridor
const HEIGHT_SMOOTH_RADIUS := 3   # points each side averaged before slope-limiting, so the bed reads as a real graded embankment instead of a jagged staircase that merely happens to obey the slope cap

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

	var pts2d := _get_dense_route_points()
	var route_chunk_positions := _ensure_chunks_loaded(pts2d)
	# The chunks _ensure_chunks_loaded() just force-created need their real
	# terrain data generated (Chunk._ready() -> generate_data()) BEFORE we
	# carve into them -- otherwise our carve edits could land in an empty
	# voxel_data dict, and generate_data()'s "already populated" guard would
	# then skip growing natural terrain there at all. Wait for that instead
	# of assuming add_child() -> _ready() timing.
	await _wait_for_route_chunks_ready(route_chunk_positions)

	var raw_bed_heights := _compute_graded_bed_heights(pts2d)
	var bed_face_heights: Array = []
	for h in raw_bed_heights:
		bed_face_heights.append(int(round(h)))

	_carve_railbed(pts2d, bed_face_heights)

	var path := _build_curve(pts2d, bed_face_heights)
	add_child(path)

	_build_rails(path)
	_build_sleepers(path)
	_spawn_train(path)

	if auto_frame_camera:
		_add_demo_camera(path)

	print("[TrainTrackBuilder] built loop, baked length=", path.curve.get_baked_length())

## Finely samples the loop's ellipse in angle (same track_center/radius_x/
## radius_z shape as the old coarse `num_points` corners), then resamples by
## arc length so consecutive returned points are ~dense_spacing apart
## regardless of the ellipse's eccentricity. Grading and rail-curve height
## both key off this dense set so the carved bed and the drawn curve agree
## everywhere along the route, not just at a handful of widely-spaced corners.
func _get_dense_route_points() -> Array:
	var fine := []
	const FINE_STEPS := 2000
	for i in range(FINE_STEPS):
		var t := (float(i) / float(FINE_STEPS)) * TAU
		fine.append(Vector2(
			track_center.x + cos(t) * radius_x,
			track_center.y + sin(t) * radius_z
		))
	fine.append(fine[0])

	var pts := [fine[0]]
	var acc := 0.0
	for i in range(1, fine.size()):
		acc += fine[i].distance_to(fine[i - 1])
		if acc >= dense_spacing:
			pts.append(fine[i])
			acc = 0.0
	return pts

func _surface_y(wx: float, wz: float) -> float:
	var ix := int(round(wx))
	var iz := int(round(wz))
	var n := _voxel_world.noise.get_noise_2d(ix, iz)
	var visual_height := int((n + 1.0) * 32.0) + 64
	return float(visual_height + 1)  # top face of the topmost solid block

## Computes a gently graded railbed profile along the dense route: raw
## per-column terrain height, smoothed (circular moving average) to avoid
## chasing every single-block noise wiggle, then slope-limited (symmetric
## relaxation, so corrections split between neighbours and the loop's
## closing seam converges cleanly too) so no two consecutive samples differ
## by more than max_grade_per_block per block of travel. This is the target
## surface both _carve_railbed() cuts/fills the terrain to and _build_curve()
## draws the rails at.
func _compute_graded_bed_heights(pts2d: Array) -> Array:
	var n := pts2d.size()
	var raw := []
	for p in pts2d:
		raw.append(_surface_y(p.x, p.y))

	var dists := []
	for i in range(n):
		var j := (i + 1) % n
		dists.append(max(pts2d[i].distance_to(pts2d[j]), 0.001))

	var h := []
	for i in range(n):
		var acc := 0.0
		var count := 0
		for k in range(-HEIGHT_SMOOTH_RADIUS, HEIGHT_SMOOTH_RADIUS + 1):
			acc += raw[(i + k + n) % n]
			count += 1
		h.append(acc / count)

	for pass_i in range(n * 2):
		var changed := false
		for i in range(n):
			var j := (i + 1) % n
			var diff: float = h[j] - h[i]
			var max_diff: float = max_grade_per_block * dists[i]
			if diff > max_diff:
				var excess := (diff - max_diff) * 0.5
				h[i] += excess
				h[j] -= excess
				changed = true
			elif diff < -max_diff:
				var excess := (-diff - max_diff) * 0.5
				h[i] -= excess
				h[j] += excess
				changed = true
		if not changed:
			break
	return h

## Carves the actual voxel terrain into a continuous graded strip under the
## route: for every dense route point, stamps a bed_half_width_blocks-wide
## strip (perpendicular to travel) into a world-column -> bed-surface-height
## map (last writer wins on overlaps between neighbouring points on curves --
## harmless since max_grade_per_block keeps neighbouring bed heights within a
## block of each other anyway), then for each column fills solid ground from
## bedrock+1 up to the bed (fills dips) and clears anything above the bed up
## to BED_CLEAR_MARGIN blocks (cuts hills / removes trees poking into the
## corridor). Edits are batched per chunk via Chunk.set_block_silent and
## flushed with a single Chunk.generate_mesh() per touched chunk at the end.
func _carve_railbed(pts2d: Array, bed_face_heights: Array) -> void:
	var n := pts2d.size()
	var columns := {}  # Vector2i world (x, z) -> int bed_face_y (first air block above the graded fill)
	for i in range(n):
		var p: Vector2 = pts2d[i]
		var prev: Vector2 = pts2d[(i - 1 + n) % n]
		var next: Vector2 = pts2d[(i + 1) % n]
		var fwd := next - prev
		if fwd.length() < 0.001:
			fwd = Vector2(1, 0)
		fwd = fwd.normalized()
		var right := Vector2(-fwd.y, fwd.x)
		var bed_face_y: int = bed_face_heights[i]
		for off in range(-bed_half_width_blocks, bed_half_width_blocks + 1):
			var wp := p + right * float(off)
			var col := Vector2i(int(round(wp.x)), int(round(wp.y)))
			columns[col] = bed_face_y

	var touched_chunks := {}  # Vector2i chunk_pos -> Chunk
	for col in columns.keys():
		var bed_face_y: int = columns[col]
		var top_solid_y := bed_face_y - 1
		if top_solid_y < 1:
			continue  # degenerate/too-low sample -- skip rather than eat bedrock
		# Fill: solid ground from just above bedrock up through the bed surface.
		for y in range(1, top_solid_y + 1):
			_grade_set_voxel(col.x, y, col.y, BED_FILL_BLOCK, touched_chunks)
		# Cut: clear anything poking up into the corridor above the bed.
		for y in range(bed_face_y, bed_face_y + BED_CLEAR_MARGIN):
			_grade_set_voxel(col.x, y, col.y, 0, touched_chunks)

	for cpos in touched_chunks.keys():
		touched_chunks[cpos].generate_mesh()

func _grade_set_voxel(x: int, y: int, z: int, type: int, touched_chunks: Dictionary) -> void:
	if y < 0 or y >= 256:
		return
	var cx := int(floor(float(x) / 16.0))
	var cz := int(floor(float(z) / 16.0))
	var cpos := Vector2i(cx, cz)
	if not _voxel_world.chunks.has(cpos):
		return
	var chunk = _voxel_world.chunks[cpos]
	if chunk == null:
		return
	var local_x := x - cx * 16
	var local_z := z - cz * 16
	chunk.set_block_silent(Vector3i(local_x, y, local_z), type)
	touched_chunks[cpos] = chunk

func _ensure_chunks_loaded(pts2d: Array) -> Array:
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
	var touched := []
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cpos := Vector2i(cx, cz)
			touched.append(cpos)
			if not _voxel_world.chunks.has(cpos):
				_voxel_world.create_chunk(cpos)
	return touched

func _wait_for_route_chunks_ready(chunk_positions: Array) -> void:
	var tries := 0
	while not _all_route_chunks_ready(chunk_positions) and tries < 300:
		await get_tree().process_frame
		tries += 1
	if not _all_route_chunks_ready(chunk_positions):
		push_warning("[TrainTrackBuilder] some railbed chunks never finished generating -- railbed carving may be incomplete.")

func _all_route_chunks_ready(chunk_positions: Array) -> bool:
	for cpos in chunk_positions:
		if not _voxel_world.chunks.has(cpos):
			return false
		var chunk = _voxel_world.chunks[cpos]
		if chunk == null or chunk.mesh_instance == null or chunk.voxel_data.is_empty():
			return false
	return true

func _build_curve(pts2d: Array, bed_face_heights: Array) -> Path3D:
	var path := Path3D.new()
	path.name = "RailPath"

	# Rails sit at the graded bed surface (bed_face_heights, the same
	# heights _carve_railbed() just cut/filled the ground to) plus
	# rail_clearance -- not a re-sample of raw terrain -- so the curve
	# matches the actual ground under it everywhere, not just at sample
	# points.
	var pts3d: Array = []
	for i in range(pts2d.size()):
		var p: Vector2 = pts2d[i]
		var y: float = bed_face_heights[i] + rail_clearance
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
	# 1.0 (was 2.0, tuned for the old 8-corner curve): the curve now has a
	# point roughly every dense_spacing (~1 block), so a coarser extrusion
	# interval would under-sample the (now much more detailed) graded profile.
	bed.path_interval = 1.0
	bed.path_local = false
	# PATH_ROTATION_PATH (not the PATH_FOLLOW default): rotate to follow the
	# curve's yaw only, never bank/tilt with elevation changes. Keeping the
	# ballast/rails level (local up == world up) is what lets the
	# locomotive's own vertical offset (see _build_locomotive, also pinned to
	# world up via ROTATION_Y) land exactly on the rail head instead of
	# drifting apart on the sloped stretches of this terrain-following loop.
	bed.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH
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
	poly.path_interval = 1.0  # see _build_rails comment on the matching Ballast change
	poly.path_local = false
	poly.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH  # see _build_rails comment
	poly.polygon = PackedVector2Array([
		Vector2(offset_x - 0.08, 0.0),
		Vector2(offset_x + 0.08, 0.0),
		Vector2(offset_x + 0.08, RAIL_HEAD_HEIGHT),
		Vector2(offset_x - 0.08, RAIL_HEAD_HEIGHT),
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
	# ROTATION_Y (yaw only, not ROTATION_ORIENTED): keeps the loco's local up
	# pinned to world up so it never banks/tilts on this terrain-following
	# loop's slopes -- see _build_rails for the matching rail-side fix. Yaw
	# still turns the loco to face the direction of travel around the loop.
	pf.rotation_mode = PathFollow3D.ROTATION_Y
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

	# Wheel bottom must land exactly on the rail HEAD (top of the rail
	# cross-section, RAIL_HEAD_HEIGHT above the curve/PathFollow3D's own Y),
	# not on the curve itself -- the curve Y is the rail BASE, and the rails
	# extrude RAIL_HEAD_HEIGHT above that. Missing this offset is what made
	# the loco visibly float above the rails.
	var wheel_r := 0.45
	var wheel_center_y := RAIL_HEAD_HEIGHT + wheel_r
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
			wheel.position = Vector3(side * (rail_gauge - 0.15), wheel_center_y, lengthwise)
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
	body.position = Vector3(0, wheel_center_y + wheel_r + body_size.y * 0.5, 0)
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
	if top_down_camera:
		# Straight down: view direction is parallel to Vector3.UP, so UP
		# can't be used as the look_at reference (degenerate/parallel) --
		# use world FORWARD (-Z) instead so "up" on screen is world -Z.
		cam.global_position = center + Vector3(0, span * 1.1 + 18.0, 0)
		cam.look_at(center, Vector3.FORWARD)
	else:
		cam.global_position = center + Vector3(span * 0.55, span * 0.4 + 9.0, span * 0.55)
		cam.look_at(center, Vector3.UP)
	cam.current = true
