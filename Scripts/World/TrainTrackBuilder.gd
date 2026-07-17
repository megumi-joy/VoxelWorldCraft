extends Node3D
class_name TrainTrackBuilder

## MINECRAFT-STYLE BLOCK-GRID rails for VoxelWorldCraft.
##
## Reused from megumi-joy/Low-Poly-City-Delivery's road-generator approach
## for the locomotive + PathFollow3D plumbing; the rail geometry itself is
## now a block-grid tile chain, not a road-style curve extrusion.
##
## WHY BLOCK-GRID (not a curve draped over -- or carved into -- terrain):
## a smooth Curve3D spline sampled at a handful of points floats over dips
## and cuts through bumps, because the smooth line and the blocky ground
## it's drawn over have no relationship past those sample points. An earlier
## attempt fixed that by grading + CARVING a corridor into the actual voxel
## terrain -- but that leaves an abrupt, ugly scar where the carved strip
## meets natural ground, and it's destructive (edits world blocks).
##
## The Minecraft-native fix is a block-grid rail: walk the route one block
## column at a time, sample that column's REAL terrain top (never write to
## it), and place a rail tile that sits exactly on that block's top face --
## a flat plate when the next column is the same height, a ~45 degree ramp
## tile when it's one block up/down. The rails therefore hug whatever
## terrain is already there by construction: they can't float (every tile
## is anchored to an actual sampled block top) and they can't carve/scar
## (voxel_data is never written).
##
## TWO SEPARATE geometry constructs share the same sampled route, and this
## split matters -- collapsing them back into one is what reintroduces
## floating:
##  1. The VISIBLE rail tiles (_build_track_tiles): discrete, blocky,
##     exactly one flat-or-sloped segment per route edge. This is what
##     "block-grid" means -- it must stay crisp, not smoothed, so it always
##     reads as sitting on the block grid.
##  2. The LOCOMOTIVE's path (_build_loco_curve): a *separate*, much denser
##     point sequence along the SAME route/heights, fed into a Curve3D so
##     PathFollow3D/TrainMover glides continuously instead of hopping tile
##     to tile. Critically this denser sampling linearly interpolates Y
##     within each edge before any Bezier smoothing is applied, so the
##     smoothing only rounds off the (small) sub-segments at slope
##     transitions -- if the loco path were built from the same *coarse*
##     points as the visible tiles, Bezier smoothing across a full 1-block
##     rise would bulge ~0.1 unit off the actual ramp surface, which is
##     visible against a 0.22-unit-tall rail head. Denser sampling shrinks
##     that bulge proportionally to the sub-segment height, not the tile
##     height, keeping the loco's wheels visually seated on the rail tiles
##     through slopes, not just on flat stretches.
##
## Terrain-height matching: VoxelWorld/Chunk.gd computes each column's
## topmost solid block as
##   visual_height = int((noise.get_noise_2d(x, z) + 1) * 32) + 64
## and that block's walkable top face sits at world Y = visual_height + 1
## (Chunk.gd fills y in range(visual_height + 1), and the UP face of a unit
## cube at integer Y sits at local y=1, i.e. world Y = block_y + 1). This
## script samples the SAME `noise` instance the sibling VoxelWorld already
## seeded (not a fresh one, and not by reading Chunk.voxel_data -- the
## formula alone is enough, so tile placement has no dependency on chunk
## load/generate timing).
##
## Runtime-only (deliberately NOT @tool): it builds procedurally in
## _ready(), the same pattern VoxelWorld/Chunk already use for terrain, so
## it plays nicely with `--headless --import` (no editor-only code paths to
## misfire during import) and with the podman Movie Maker recording flow.

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
@export var rail_clearance: float = 0.04  # rails sit this far above the sampled block's top face -- just enough to avoid z-fighting with the terrain quad, not a visible gap
@export var train_speed: float = 10.0     # m/s along the curve
@export var chunk_margin_blocks: int = 8  # extra blocks force-loaded beyond the loop's bbox so terrain renders under the whole track

const RAIL_HEAD_HEIGHT := 0.22   # rail cross-section height above a tile's base
const RAIL_WIDTH := 0.16         # rail cross-section width
const TIE_HEIGHT := 0.12
const TIE_THICKNESS := 0.35      # tie extent along the direction of travel
const LOCO_PATH_SUBDIV := 4      # sub-points per route edge used ONLY for the loco's Curve3D -- see header note on why this must be denser than the visible tiles
const TANGENT_SCALE := 0.22      # Catmull-Rom-ish tangent scale for the loco curve

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

	var route_cols := _get_route_columns()
	_ensure_chunks_loaded(route_cols)

	var heights: Array = []
	for col in route_cols:
		heights.append(_terrain_top_block_y(col.x, col.y))

	var tiles := Node3D.new()
	tiles.name = "RailTiles"
	add_child(tiles)
	_build_track_tiles(tiles, route_cols, heights)

	var path := _build_loco_curve(route_cols, heights)
	add_child(path)
	_spawn_train(path)

	if auto_frame_camera:
		_add_demo_camera(route_cols, heights)

	print("[TrainTrackBuilder] built block-grid loop, ", route_cols.size(), " tiles, baked loco path length=", path.curve.get_baked_length())

## Walks the loop's ellipse (same track_center/radius_x/radius_z shape as
## before) at fine angular resolution, then keeps only the DISTINCT integer
## block columns it passes through, in order, deduping consecutive repeats.
## At this fine a sampling (2000 steps around a ~100-unit-circumference
## loop, i.e. ~0.05 units of arc per step) consecutive kept columns are for
## all practical purposes always lattice-adjacent -- the route is therefore
## a connected chain of real block columns, not an arbitrary set of points,
## which is what lets _build_track_tiles() treat every edge as "this column
## to the next block over" rather than an arbitrary-length hop.
func _get_route_columns() -> Array:
	const FINE_STEPS := 2000
	var cols: Array = []
	for i in range(FINE_STEPS):
		var t := (float(i) / float(FINE_STEPS)) * TAU
		var wx := track_center.x + cos(t) * radius_x
		var wz := track_center.y + sin(t) * radius_z
		var col := Vector2i(int(round(wx)), int(round(wz)))
		if cols.is_empty() or cols[-1] != col:
			cols.append(col)
	# Loop closure: drop a duplicate-of-first tail (fine sampling can land
	# back on the start column before i wraps) so the last->first edge isn't
	# zero-length.
	if cols.size() > 1 and cols[-1] == cols[0]:
		cols.remove_at(cols.size() - 1)
	return cols

## Same formula Chunk.gd uses to pick each column's topmost solid block --
## queried directly from the noise instance, not by reading voxel_data, so
## tile placement never depends on whether that column's chunk has finished
## generating.
func _terrain_top_block_y(gx: int, gz: int) -> int:
	var n := _voxel_world.noise.get_noise_2d(gx, gz)
	return int((n + 1.0) * 32.0) + 64

func _ensure_chunks_loaded(route_cols: Array) -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for col in route_cols:
		min_x = min(min_x, col.x)
		max_x = max(max_x, col.x)
		min_z = min(min_z, col.y)
		max_z = max(max_z, col.y)
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

## Builds the VISIBLE block-grid rail tiles: one oriented rail-pair-plus-tie
## segment per route edge (column i -> column i+1), sized to the actual gap
## between the two sampled block tops. When |height delta| is exactly one
## block this is a single ~45 degree ramp tile, as spec'd. When natural
## terrain occasionally steps more than one block between adjacent sampled
## columns (real fbm noise isn't perfectly graded), the edge is split into
## |delta| consecutive 1-block-rise sub-segments instead of one oversteep
## ramp -- still block-anchored at every sub-step, still zero terrain
## writes, just a steeper little staircase for that rare edge. On the
## overwhelmingly common flat/one-block-step edges this fallback is a no-op
## (steps == 1, i.e. exactly the tile described in the spec).
func _build_track_tiles(parent: Node3D, route_cols: Array, heights: Array) -> void:
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3.ONE
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.55, 0.55, 0.6)
	rail_mat.metallic = 0.8
	rail_mat.roughness = 0.35

	var tie_mesh := BoxMesh.new()
	tie_mesh.size = Vector3.ONE
	var tie_mat := StandardMaterial3D.new()
	tie_mat.albedo_color = Color(0.32, 0.2, 0.12)

	var rail_xforms: Array = []
	var tie_xforms: Array = []

	var n := route_cols.size()
	for i in range(n):
		var j := (i + 1) % n
		var col_a: Vector2i = route_cols[i]
		var col_b: Vector2i = route_cols[j]
		var h_a: int = heights[i]
		var h_b: int = heights[j]
		var delta := h_b - h_a
		var steps: int = maxi(1, absi(delta))
		var sign_h := 0 if delta == 0 else (1 if delta > 0 else -1)

		for s in range(steps):
			var t0 := float(s) / float(steps)
			var t1 := float(s + 1) / float(steps)
			var xz0 := Vector2(col_a).lerp(Vector2(col_b), t0)
			var xz1 := Vector2(col_a).lerp(Vector2(col_b), t1)
			var y0 := float(h_a + sign_h * s) + 1.0 + rail_clearance
			var y1 := float(h_a + sign_h * (s + 1)) + 1.0 + rail_clearance
			var p0 := Vector3(xz0.x, y0, xz0.y)
			var p1 := Vector3(xz1.x, y1, xz1.y)
			_append_segment_transforms(p0, p1, rail_xforms, tie_xforms)

	_spawn_multimesh(parent, "Rails", rail_mesh, rail_mat, rail_xforms)
	_spawn_multimesh(parent, "Sleepers", tie_mesh, tie_mat, tie_xforms)

## Appends the oriented-box transforms (left rail, right rail, one tie) for
## a single flat-or-sloped segment from p0 to p1.
func _append_segment_transforms(p0: Vector3, p1: Vector3, rail_xforms: Array, tie_xforms: Array) -> void:
	var seg := p1 - p0
	var seg_len := seg.length()
	if seg_len < 0.001:
		return
	var forward := seg / seg_len
	var right := forward.cross(Vector3.UP)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(forward).normalized()
	var mid := (p0 + p1) * 0.5

	for offset: float in [-rail_gauge, rail_gauge]:
		var rail_center: Vector3 = mid + right * offset + up * (RAIL_HEAD_HEIGHT * 0.5)
		var basis := Basis(right * RAIL_WIDTH, up * RAIL_HEAD_HEIGHT, forward * seg_len)
		rail_xforms.append(Transform3D(basis, rail_center))

	# Fixed TIE_THICKNESS along the direction of travel (NOT scaled to
	# seg_len, which is ~1 unit -- scaling to seg_len was stretching each
	# tie to the full length of its segment, so consecutive ties butted
	# up against each other into a continuous deck instead of reading as
	# discrete sleepers with rail visible between them).
	var tie_width := rail_gauge * 2.0 + 0.6
	var tie_center := mid - up * (TIE_HEIGHT * 0.5)
	var tie_basis := Basis(right * tie_width, up * TIE_HEIGHT, forward * TIE_THICKNESS)
	tie_xforms.append(Transform3D(tie_basis, tie_center))

func _spawn_multimesh(parent: Node3D, node_name: String, mesh: Mesh, mat: Material, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)

## Builds a DENSE point sequence along the same route/heights (see class
## header for why this must be denser than the visible tiles), then a
## Curve3D through those points with Catmull-Rom-ish tangents so
## PathFollow3D/TrainMover glide continuously instead of hopping tile to
## tile. Within one route edge the sub-points are exactly collinear (Y is
## linearly interpolated), so Bezier smoothing there is a no-op; smoothing
## only rounds off the corners at edge boundaries, where the sub-segment
## height (1/LOCO_PATH_SUBDIV of a block) is small enough that the rounding
## doesn't visibly lift the loco off the actual rail tiles.
func _build_loco_curve(route_cols: Array, heights: Array) -> Path3D:
	var pts: Array = []
	var n := route_cols.size()
	for i in range(n):
		var j := (i + 1) % n
		var col_a: Vector2i = route_cols[i]
		var col_b: Vector2i = route_cols[j]
		var h_a: float = heights[i]
		var h_b: float = heights[j]
		for s in range(LOCO_PATH_SUBDIV):
			var t := float(s) / float(LOCO_PATH_SUBDIV)
			var xz := Vector2(col_a).lerp(Vector2(col_b), t)
			var y: float = lerpf(h_a, h_b, t) + 1.0 + rail_clearance
			pts.append(Vector3(xz.x, y, xz.y))
	pts.append(pts[0])  # close the loop explicitly for a seamless PathFollow3D wrap

	var path := Path3D.new()
	path.name = "RailPath"
	var curve := Curve3D.new()
	var m := pts.size()
	for i in range(m):
		var prev: Vector3 = pts[(i - 1 + m) % m]
		var next: Vector3 = pts[(i + 1) % m]
		var tangent := (next - prev) * TANGENT_SCALE
		if i == m - 1:
			var first_prev: Vector3 = pts[m - 2]
			var first_next: Vector3 = pts[1]
			tangent = (first_next - first_prev) * TANGENT_SCALE
		curve.add_point(pts[i], -tangent, tangent)
	path.curve = curve
	return path

func _spawn_train(path: Path3D) -> PathFollow3D:
	var pf := PathFollow3D.new()
	pf.name = "TrainHead"
	pf.loop = true
	# ROTATION_Y (yaw only, not ROTATION_ORIENTED): keeps the loco's local up
	# pinned to world up so it never banks/tilts on this terrain-following
	# loop's slopes.
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
	# extrude RAIL_HEAD_HEIGHT above that.
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

func _add_demo_camera(route_cols: Array, heights: Array) -> void:
	var aabb := AABB(Vector3(route_cols[0].x, heights[0], route_cols[0].y), Vector3.ZERO)
	for i in range(route_cols.size()):
		var col: Vector2i = route_cols[i]
		aabb = aabb.expand(Vector3(col.x, heights[i], col.y))
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
