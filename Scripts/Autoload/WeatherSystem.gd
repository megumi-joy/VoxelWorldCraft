extends Node
# WeatherSystem -- ambient weather VFX autoload (owner ask, mid=667: "...пыль
# и песок и снег и дожди и молнии" -- dust/sand, snow, rain, lightning).
#
# Deliberately built as a SELF-CONTAINED autoload rather than a node wired
# into World.tscn/World.gd: a concurrent branch is reworking chunk streaming
# in World.gd, so this file never touches World.gd/VoxelWorld.gd/Chunk.gd.
# It only reads two things from the world, both already public, stable,
# low-level surfaces:
#   - the "voxel_world" group node (same group GraphicsSettings.gd already
#     keys off -- see that file's GROUP_VOXEL_WORLD comment) purely to know
#     whether an actual World scene is loaded (so weather stays off on the
#     main menu, matching MainMenuWorld.tscn deliberately NOT tagging its
#     VoxelWorld with that group)
#   - GraphicsSettings.view_distance / .weather_enabled / .weather_intensity,
#     for quality scaling and the on/off toggle
# It never reads Chunk.voxel_data or VoxelWorld.chunks, so it has zero
# surface area to collide with the chunk-streaming rework.
#
# Particles follow the active camera (get_viewport().get_camera_3d(), NOT
# the "player" group -- decouples this from Player.gd entirely) so rain/snow/
# dust fill the visible area cheaply regardless of world size, instead of
# being seeded across the whole voxel world.

signal weather_changed(new_state: int)

enum State { CLEAR, RAIN, SNOW, DUST }
const STATE_NAMES := ["Clear", "Rain", "Snow", "Dust"]

const GROUP_VOXEL_WORLD := "voxel_world"

# Base (quality-factor == 1.0) particle counts. Scaled down by
# _quality_factor() at low GraphicsSettings.view_distance and by
# GraphicsSettings.weather_intensity. Kept modest on purpose -- this is a
# voxel/hypercasual game, not a AAA rain sim; readability over density.
const BASE_RAIN_AMOUNT := 500
const BASE_SNOW_AMOUNT := 350
const BASE_DUST_AMOUNT := 260

# How far around the camera weather fills, in world units (box half-extents
# get derived from this). Independent of VoxelWorld.render_distance (chunks)
# since particles are a screen-space-ish effect, not terrain.
const FILL_RADIUS_XZ := 26.0
const FILL_HEIGHT_ABOVE := 14.0

const MIN_CYCLE_SECS := 45.0
const MAX_CYCLE_SECS := 110.0
# The very first cycle is shorter so a fresh play session actually sees
# weather change within the first stretch of play instead of possibly
# sitting on Clear (see advisor note: "on by default" must not mean "starts
# invisible"). Foliage (grass/leaves/petals) is the other half of that --
# it renders unconditionally regardless of weather state.
const FIRST_CYCLE_SECS := 16.0

const LIGHTNING_MIN_GAP := 4.0
const LIGHTNING_MAX_GAP := 11.0
const LIGHTNING_TEST_GAP := 2.0 # used only with --lightning-test

var enabled: bool = true
var state: int = State.CLEAR
var _locked: bool = false # true once the debug key or --weather= forces a state
var _cycle_timer: float = 0.0
var _lightning_timer: float = 0.0
var _force_lightning_testing: bool = false

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _dust: GPUParticles3D
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash_tween: Tween

func _ready() -> void:
	_cycle_timer = FIRST_CYCLE_SECS
	_rain = _make_precip_particles(Color(0.65, 0.75, 1.0, 0.55), Vector3(0.025, 0.55, 0.025), -16.0, -20.0, 0.05)
	_snow = _make_precip_particles(Color(0.95, 0.97, 1.0, 0.85), Vector3(0.06, 0.06, 0.06), -1.6, -2.6, 0.9)
	_dust = _make_dust_particles()
	add_child(_rain)
	add_child(_snow)
	add_child(_dust)
	_set_active_particles(State.CLEAR)

	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 22 # above SoundCaptions (21) and ActionLog (20)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_layer.add_child(_flash_rect)
	add_child(_flash_layer)

	_parse_cmdline_args()

func _parse_cmdline_args() -> void:
	# Deterministic capture/testing hook -- e.g.
	#   godot --weather=rain --lightning-test
	# forces a state (and locks out the auto-cycle) instead of relying on
	# the random cycle landing on the state you want to screenshot/record.
	# Same OS.get_cmdline_args() convention AutoTester.gd already uses for
	# --run-tests.
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--weather="):
			var wanted := arg.substr("--weather=".length()).to_lower()
			var s := _state_from_string(wanted)
			if s != -1:
				state = s
				_locked = true
				_set_active_particles(state)
				print("WeatherSystem: cmdline forced state=", STATE_NAMES[state])
			else:
				push_warning("WeatherSystem: --weather=" + wanted + " not recognized (expected clear/rain/snow/dust)")
		elif arg == "--lightning-test":
			_force_lightning_testing = true
			print("WeatherSystem: --lightning-test active")

func _state_from_string(s: String) -> int:
	for i in STATE_NAMES.size():
		if STATE_NAMES[i].to_lower() == s:
			return i
	return -1

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Debug keys (no free InputMap actions collide -- see Player.gd's
	# add_input_mapping calls for W/A/S/D/Space/Shift/E/J; L/K are unused).
	if event.physical_keycode == KEY_L:
		force_next_state()
	elif event.physical_keycode == KEY_K:
		resume_auto_cycle()

## Debug/testing: force the next weather state and stop auto-cycling.
func force_next_state() -> void:
	set_state((state + 1) % State.size(), true)

## Debug/testing: hand control back to the automatic cycle.
func resume_auto_cycle() -> void:
	_locked = false
	_cycle_timer = MIN_CYCLE_SECS

func set_state(new_state: int, lock: bool = false) -> void:
	if new_state == state:
		return
	state = new_state
	_locked = lock
	_set_active_particles(state)
	weather_changed.emit(state)
	print("WeatherSystem: state=", STATE_NAMES[state], " locked=", _locked)

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var in_world := get_tree().get_first_node_in_group(GROUP_VOXEL_WORLD) != null
	var active := enabled and _weather_enabled_setting() and cam != null and in_world

	_rain.visible = active and state == State.RAIN
	_snow.visible = active and state == State.SNOW
	_dust.visible = active and state == State.DUST
	_rain.emitting = _rain.visible
	_snow.emitting = _snow.visible
	_dust.emitting = _dust.visible

	if not active:
		return

	var follow_pos: Vector3 = cam.global_position + Vector3(0, FILL_HEIGHT_ABOVE * 0.5, 0)
	_rain.global_position = follow_pos
	_snow.global_position = follow_pos
	_dust.global_position = cam.global_position + Vector3(0, 1.0, 0)

	if not _locked:
		_cycle_timer -= delta
		if _cycle_timer <= 0.0:
			_pick_next_state()
			_cycle_timer = randf_range(MIN_CYCLE_SECS, MAX_CYCLE_SECS)

	if state == State.RAIN:
		var gap := LIGHTNING_TEST_GAP if _force_lightning_testing else randf_range(LIGHTNING_MIN_GAP, LIGHTNING_MAX_GAP)
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_strike_lightning(cam)
			_lightning_timer = gap

func _weather_enabled_setting() -> bool:
	# Pulled from GraphicsSettings rather than pushed into it -- see this
	# file's header comment. GraphicsSettings is an earlier autoload in
	# project.godot's [autoload] list (this one is appended after it), so by
	# the time this runs every frame the singleton is guaranteed to exist;
	# `in` guards it anyway in case that ordering ever changes.
	if "weather_enabled" in GraphicsSettings:
		return GraphicsSettings.weather_enabled
	return true

func _weather_intensity_setting() -> float:
	if "weather_intensity" in GraphicsSettings:
		return clampf(GraphicsSettings.weather_intensity, 0.0, 1.0)
	return 0.6

func _quality_factor() -> float:
	# Cheap, additive read of the existing quality knob -- no PRESETS dict
	# edits needed. view_distance ranges VIEW_DISTANCE_MIN(2)..MAX(8).
	if "view_distance" in GraphicsSettings:
		return clampf(float(GraphicsSettings.view_distance) / 8.0, 0.35, 1.0)
	return 0.7

func _pick_next_state() -> void:
	# Weighted so Clear doesn't dominate (a "weather system" that mostly
	# shows nothing reads as broken, not subtle) while still being the most
	# common state, like real weather.
	var weights := {State.CLEAR: 0.40, State.RAIN: 0.24, State.SNOW: 0.20, State.DUST: 0.16}
	var roll := randf()
	var acc := 0.0
	var next := State.CLEAR
	for s in weights.keys():
		acc += weights[s]
		if roll <= acc:
			next = s
			break
	if next == state:
		return
	set_state(next, false)

func _set_active_particles(s: int) -> void:
	var q := _quality_factor() * _weather_intensity_setting()
	_rain.amount = maxi(20, int(BASE_RAIN_AMOUNT * q))
	_snow.amount = maxi(20, int(BASE_SNOW_AMOUNT * q))
	_dust.amount = maxi(20, int(BASE_DUST_AMOUNT * q))
	_rain.emitting = s == State.RAIN
	_snow.emitting = s == State.SNOW
	_dust.emitting = s == State.DUST

# ---- Particle construction (fully procedural -- no external assets, same
# convention TextureGenerator.gd uses for block textures) ----

func _fade_ramp() -> GradientTexture1D:
	# Fade in near spawn (avoids popping at the top of the box) and fade out
	# by end-of-life (approximates precipitation "settling"/dissipating near
	# the ground without real ground collision, which would be expensive at
	# this particle count).
	var g := Gradient.new()
	g.set_offset(0, 0.0); g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.12, Color(1, 1, 1, 1.0))
	g.add_point(0.8, Color(1, 1, 1, 1.0))
	g.set_offset(g.get_point_count() - 1, 1.0); g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex

func _make_precip_particles(color: Color, box_size: Vector3, vel_min: float, vel_max: float, drift: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.lifetime = 2.4
	p.amount = 200
	p.visibility_aabb = AABB(Vector3(-FILL_RADIUS_XZ, -FILL_HEIGHT_ABOVE - 4.0, -FILL_RADIUS_XZ), Vector3(FILL_RADIUS_XZ * 2, FILL_HEIGHT_ABOVE * 2 + 8.0, FILL_RADIUS_XZ * 2))

	var mesh := BoxMesh.new()
	mesh.size = box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = false
	mesh.material = mat
	p.draw_pass_1 = mesh

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Box is centered on the emitter node, which _process() places
	# FILL_HEIGHT_ABOVE*0.5 above the camera every frame -- sizing the box's
	# own half-height to match makes it span from below to above the camera.
	pm.emission_box_extents = Vector3(FILL_RADIUS_XZ, FILL_HEIGHT_ABOVE * 0.5, FILL_RADIUS_XZ)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 6.0
	pm.gravity = Vector3(0, 0, 0) # constant velocity reads cleaner than accel for thin streak/flake sprites
	pm.initial_velocity_min = abs(vel_min)
	pm.initial_velocity_max = abs(vel_max)
	pm.turbulence_enabled = drift > 0.15
	if pm.turbulence_enabled:
		pm.turbulence_noise_strength = drift
		pm.turbulence_noise_scale = 2.0
	pm.color_ramp = _fade_ramp()
	p.process_material = pm

	# NOT local_coords -- already-spawned drops/flakes keep falling in world
	# space instead of dragging sideways whenever the box re-centers on
	# camera movement each frame.
	p.local_coords = false
	return p

func _make_dust_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.lifetime = 3.5
	p.amount = 150
	p.visibility_aabb = AABB(Vector3(-FILL_RADIUS_XZ, -6, -FILL_RADIUS_XZ), Vector3(FILL_RADIUS_XZ * 2, 12, FILL_RADIUS_XZ * 2))

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.22, 0.22, 0.22)
	var mat := StandardMaterial3D.new()
	# Brighter/more opaque than the first pass -- alpha 0.4 at this box size
	# read as barely-there specks against terrain in the podman/Xvfb capture
	# (tools/verify_headless.sh), too subtle for the owner's "reads clearly"
	# bar. 0.7 alpha + a warmer/lighter tint keeps it readable as a sand
	# haze without going fully opaque (would look like solid flying blocks).
	mat.albedo_color = Color(0.85, 0.68, 0.38, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.draw_pass_1 = mesh

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(FILL_RADIUS_XZ, 2.5, FILL_RADIUS_XZ)
	pm.direction = Vector3(1, 0, 0.2)
	pm.spread = 35.0
	pm.gravity = Vector3(0, 0, 0)
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 3.0
	pm.turbulence_noise_scale = 1.2
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	p.local_coords = false
	return p

# ---- Lightning ----

func _strike_lightning(cam: Camera3D) -> void:
	_screen_flash()
	_spawn_bolt(cam)
	if SoundCaptions and SoundCaptions.has_method("caption"):
		SoundCaptions.caption("[Гром]")

func _screen_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color.a = 0.6
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD)

func _spawn_bolt(cam: Camera3D) -> void:
	var bolt := MeshInstance3D.new()
	bolt.mesh = _build_bolt_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.92, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.85, 1.0)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bolt.material_override = mat

	var cam_fwd := -cam.global_transform.basis.z
	var dist := randf_range(18.0, 32.0)
	var side := cam.global_transform.basis.x * randf_range(-14.0, 14.0)
	var origin := cam.global_position + cam_fwd * dist + side
	origin.y = cam.global_position.y + randf_range(10.0, 22.0)
	# add_child() BEFORE look_at() -- look_at() requires the node to already
	# be inside the tree (it errors "Node not inside tree. Use
	# look_at_from_position() instead." otherwise; caught via the podman
	# spike test while building this file).
	add_child(bolt)
	bolt.global_position = origin
	bolt.look_at(cam.global_position, Vector3.UP)

	var tween := create_tween()
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.25).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(bolt.queue_free)

func _build_bolt_mesh() -> ArrayMesh:
	# Simple jagged vertical zigzag ribbon -- procedural, no texture, reads
	# clearly as a lightning bolt from a distance (bright/chunky > subtle,
	# per the owner's stated art direction).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var segments := 7
	var width := 0.4
	var height := 20.0
	var x_off := 0.0
	for i in segments + 1:
		var t := float(i) / float(segments)
		x_off += randf_range(-1.2, 1.2) * (1.0 - t * 0.3)
		var y := -height * 0.5 + height * t
		st.set_color(Color(1, 1, 1, 1.0 - t * 0.15))
		st.add_vertex(Vector3(x_off - width * 0.5, y, 0))
		st.add_vertex(Vector3(x_off + width * 0.5, y, 0))
	var mesh := st.commit()
	return mesh
