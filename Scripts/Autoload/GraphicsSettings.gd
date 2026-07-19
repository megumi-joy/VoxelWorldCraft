extends Node
# GraphicsSettings -- persists + live-applies the "GRAPHICS QUALITY" section
# of Scenes/SettingsPanel.tscn (Scripts/UI/SettingsPanel.gd). Sibling
# autoload to HudSettings.gd, sharing the same user://settings.cfg document
# (own "graphics" section, load-merge-save so neither autoload clobbers the
# other's keys -- see _load_from_disk/_save_to_disk below) rather than being
# folded into HudSettings.gd itself: that file's single HUD-scale concern
# stays untouched, which keeps the merge surface small for other in-flight
# settings-panel branches (see PR body / #12,#14,#15 note).
#
# ---- Honesty note on "ray tracing" (read before touching labels) ----
# Godot 4.3 has NO hardware ray-tracing API -- no RTX/DXR/Vulkan-RT path
# anywhere in the engine. Nothing in this file or SettingsPanel.gd may be
# labelled "Ray Tracing". What Forward+ (this project's declared rendering
# method -- see project.godot's config/features) DOES offer that is
# ray-trace-ADJACENT:
#   - SDFGI (Signed Distance Field Global Illumination): a real-time,
#     screen-independent dynamic GI solution. It's the closest thing to
#     "ray-traced GI" this engine has, but it's a voxel/SDF cone-trace
#     approximation computed on the GPU compute pipeline, NOT hardware ray
#     tracing. UI label: "Global Illumination (SDFGI)".
#   - SSR (screen-space reflections) and SSAO/SSIL (screen-space ambient
#     occlusion / indirect light) are screen-space approximations, not
#     ray-traced, and cannot see anything outside the camera's frame.
# SDFGI and SSIL are Forward+-only in Godot 4.3; SSR/SSAO work in Forward+
# and Mobile. NONE of them render under the Compatibility (GLES3) fallback
# renderer -- which is what this dev box's llvmpipe software rasterizer
# falls back to (no Vulkan device inside the podman container: see
# godot.log, "OpenGL API ... Compatibility ... llvmpipe"). Setting these
# Environment properties never errors regardless of the active renderer --
# a renderer that can't use a property just ignores it -- so this script's
# job (apply settings, persist them, never crash) is fully verifiable
# headless on this box; the VISUAL payoff needs a real Vulkan/Forward+
# capable GPU (box 182's RTX 4070, verified separately).
signal settings_applied

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "graphics"

# Scene-tree groups this autoload looks nodes up through -- declared on the
# nodes directly in World.tscn / MainMenuWorld.tscn (groups=[...] on the
# node line; no script needed on WorldEnvironment/DirectionalLight3D for
# this). Same lookup pattern already used project-wide for "player" /
# "settings_panel" (see Scripts/UI/HUD.gd, Scripts/Player/Player.gd).
const GROUP_WORLD_ENVIRONMENT := "world_environment"
const GROUP_VOXEL_WORLD := "voxel_world"
const GROUP_DIRECTIONAL_LIGHT := "directional_light"

enum Preset { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }
enum ShadowQuality { OFF, LOW, HIGH }
enum AAMode { OFF, FXAA, MSAA_2X, MSAA_4X }
enum SDFGIQuality { LOW, MEDIUM, HIGH, ULTRA }

const PRESET_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]
const SHADOW_QUALITY_NAMES := ["Off", "Low", "High"]
const AA_MODE_NAMES := ["Off", "FXAA", "MSAA 2x", "MSAA 4x"]
const SDFGI_QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]

const VIEW_DISTANCE_MIN := 2
const VIEW_DISTANCE_MAX := 8

# Bundled toggle groups the "Quality Preset" dropdown applies in one shot.
# Keys match the individual settings fields below.
const PRESETS := {
	Preset.LOW: {
		"sdfgi_enabled": false, "sdfgi_quality": SDFGIQuality.LOW,
		"ssr_enabled": false, "ssao_enabled": false, "ssil_enabled": false,
		"glow_enabled": false,
		"shadow_quality": ShadowQuality.OFF,
		"aa_mode": AAMode.OFF,
		"view_distance": 2,
	},
	Preset.MEDIUM: {
		"sdfgi_enabled": false, "sdfgi_quality": SDFGIQuality.LOW,
		"ssr_enabled": false, "ssao_enabled": true, "ssil_enabled": false,
		"glow_enabled": true,
		"shadow_quality": ShadowQuality.LOW,
		"aa_mode": AAMode.FXAA,
		"view_distance": 4,
	},
	Preset.HIGH: {
		"sdfgi_enabled": true, "sdfgi_quality": SDFGIQuality.MEDIUM,
		"ssr_enabled": true, "ssao_enabled": true, "ssil_enabled": true,
		"glow_enabled": true,
		"shadow_quality": ShadowQuality.HIGH,
		"aa_mode": AAMode.MSAA_2X,
		"view_distance": 6,
	},
	Preset.ULTRA: {
		"sdfgi_enabled": true, "sdfgi_quality": SDFGIQuality.ULTRA,
		"ssr_enabled": true, "ssao_enabled": true, "ssil_enabled": true,
		"glow_enabled": true,
		"shadow_quality": ShadowQuality.HIGH,
		"aa_mode": AAMode.MSAA_4X,
		"view_distance": 8,
	},
}

var preset: int = Preset.MEDIUM
var sdfgi_enabled: bool = false
var sdfgi_quality: int = SDFGIQuality.LOW
var ssr_enabled: bool = false
var ssao_enabled: bool = true
var ssil_enabled: bool = false
var glow_enabled: bool = true
var shadow_quality: int = ShadowQuality.LOW
var aa_mode: int = AAMode.FXAA
var view_distance: int = 4

# ---- Weather/Foliage VFX (WeatherSystem.gd / FoliageRenderer.gd) ----
# Deliberately NOT part of the Preset/PRESETS bundle above -- these are
# ambient-VFX toggles, orthogonal to the SDFGI/SSR/shadow/AA render-quality
# axis, so apply_preset() never touches them and they never flip `preset`
# to Custom. WeatherSystem.gd/FoliageRenderer.gd PULL these fields directly
# (`GraphicsSettings.weather_enabled` etc.) every frame/scan tick rather
# than this file pushing into them, so there's no autoload-init-order
# dependency in either direction (see WeatherSystem.gd's header comment).
var weather_enabled: bool = true
var weather_intensity: float = 0.6
var foliage_enabled: bool = true

func set_weather_enabled(v: bool) -> void:
	weather_enabled = v
	_save_to_disk()

func set_weather_intensity(v: float) -> void:
	weather_intensity = clampf(v, 0.0, 1.0)
	_save_to_disk()

func set_foliage_enabled(v: bool) -> void:
	foliage_enabled = v
	_save_to_disk()

# Guard so apply_preset()'s own field writes don't re-flag themselves back
# to Preset.CUSTOM via the individual setters' _mark_custom() calls.
var _applying_preset := false

func _ready() -> void:
	_load_from_disk()
	_apply_global()
	# No-op if no World/MainMenuWorld is in the tree yet -- normal at
	# autoload boot, since autoloads _ready() before run/main_scene. World.gd
	# and MainMenuWorld.gd both re-invoke apply_scene_settings() from their
	# own _ready() once their WorldEnvironment/light/VoxelWorld children
	# exist (children _ready() before parent in Godot's tree order, so the
	# groups are already populated by the time those calls happen).
	apply_scene_settings()

# ---- Individual setters: update field, mark preset Custom, apply, persist ----

func set_sdfgi_enabled(v: bool) -> void:
	sdfgi_enabled = v
	_mark_custom()
	_apply_environment_props()
	_save_to_disk()

func set_sdfgi_quality(v: int) -> void:
	sdfgi_quality = clampi(v, 0, SDFGI_QUALITY_NAMES.size() - 1)
	_mark_custom()
	_apply_environment_props()
	_save_to_disk()

func set_ssr_enabled(v: bool) -> void:
	ssr_enabled = v
	_mark_custom()
	_apply_environment_props()
	_save_to_disk()

func set_ssao_enabled(v: bool) -> void:
	ssao_enabled = v
	_mark_custom()
	_apply_environment_props()
	_save_to_disk()

func set_ssil_enabled(v: bool) -> void:
	ssil_enabled = v
	_mark_custom()
	_apply_environment_props()
	_save_to_disk()

func set_glow_enabled(v: bool) -> void:
	glow_enabled = v
	_mark_custom()
	_apply_environment_props()
	_save_to_disk()

func set_shadow_quality(v: int) -> void:
	shadow_quality = clampi(v, 0, SHADOW_QUALITY_NAMES.size() - 1)
	_mark_custom()
	_apply_global_shadow()
	_apply_scene_shadow()
	_save_to_disk()

func set_aa_mode(v: int) -> void:
	aa_mode = clampi(v, 0, AA_MODE_NAMES.size() - 1)
	_mark_custom()
	_apply_global_aa()
	_save_to_disk()

func set_view_distance(v: int) -> void:
	view_distance = clampi(v, VIEW_DISTANCE_MIN, VIEW_DISTANCE_MAX)
	_mark_custom()
	_apply_view_distance()
	_save_to_disk()

func apply_preset(p: int) -> void:
	if not PRESETS.has(p):
		return
	_applying_preset = true
	preset = p
	var values: Dictionary = PRESETS[p]
	sdfgi_enabled = values["sdfgi_enabled"]
	sdfgi_quality = values["sdfgi_quality"]
	ssr_enabled = values["ssr_enabled"]
	ssao_enabled = values["ssao_enabled"]
	ssil_enabled = values["ssil_enabled"]
	glow_enabled = values["glow_enabled"]
	shadow_quality = values["shadow_quality"]
	aa_mode = values["aa_mode"]
	view_distance = values["view_distance"]
	_apply_all()
	_save_to_disk()
	_applying_preset = false

func _mark_custom() -> void:
	if not _applying_preset:
		preset = Preset.CUSTOM

# ---- Apply, split into two tiers ----
# "Global": root Viewport / RenderingServer state. Survives scene changes on
# its own (nothing recreates the root Window), so _ready() applying it once
# is enough.
# "Per-scene": Environment resource properties, the directional light's
# shadow_enabled, VoxelWorld.render_distance. These live on nodes that are
# destroyed and recreated every time World.tscn/MainMenuWorld.tscn (re)loads,
# so callers must re-invoke apply_scene_settings() once the new scene's
# nodes exist -- World.gd and MainMenuWorld.gd do this from their own
# _ready().

func _apply_all() -> void:
	_apply_global()
	apply_scene_settings()

func _apply_global() -> void:
	_apply_global_aa()
	_apply_global_shadow()

func _apply_global_aa() -> void:
	var root := get_tree().root
	match aa_mode:
		AAMode.OFF:
			root.msaa_3d = Viewport.MSAA_DISABLED
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		AAMode.FXAA:
			root.msaa_3d = Viewport.MSAA_DISABLED
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		AAMode.MSAA_2X:
			root.msaa_3d = Viewport.MSAA_2X
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		AAMode.MSAA_4X:
			root.msaa_3d = Viewport.MSAA_4X
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

func _apply_global_shadow() -> void:
	# Directional shadow atlas resolution + soft-shadow filter quality are
	# RenderingServer-global (not per-Environment/per-light), so they
	# persist across scene reloads on their own. Only the light's own
	# shadow_enabled on/off (the Off tier) is per-scene -- see
	# _apply_scene_shadow().
	match shadow_quality:
		ShadowQuality.HIGH:
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
		_: # OFF, LOW
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)

func apply_scene_settings() -> void:
	_apply_environment_props()
	_apply_scene_shadow()
	_apply_view_distance()
	settings_applied.emit()

func _apply_environment_props() -> void:
	var env := _get_environment()
	if env == null:
		return
	env.sdfgi_enabled = sdfgi_enabled
	if sdfgi_enabled:
		var q := clampi(sdfgi_quality, 0, 3)
		env.sdfgi_cascades = [4, 6, 6, 8][q]
		env.sdfgi_min_cell_size = [0.4, 0.2, 0.1, 0.05][q]
		env.sdfgi_use_occlusion = sdfgi_quality >= SDFGIQuality.HIGH
	env.ssr_enabled = ssr_enabled
	env.ssao_enabled = ssao_enabled
	env.ssil_enabled = ssil_enabled
	env.glow_enabled = glow_enabled

func _apply_scene_shadow() -> void:
	for light in get_tree().get_nodes_in_group(GROUP_DIRECTIONAL_LIGHT):
		if light is DirectionalLight3D:
			light.shadow_enabled = shadow_quality != ShadowQuality.OFF

func _apply_view_distance() -> void:
	# Only World.tscn's VoxelWorld is in this group (a deliberate choice --
	# MainMenuWorld.tscn's VoxelWorld is NOT, so its small authored
	# render_distance=1 decorative background stays fixed and isn't blown up
	# to the gameplay View Distance value, which would cost perf on the menu
	# screen for no visible benefit).
	var vw := get_tree().get_first_node_in_group(GROUP_VOXEL_WORLD)
	if vw and "render_distance" in vw:
		vw.render_distance = view_distance

func _get_environment() -> Environment:
	var we := get_tree().get_first_node_in_group(GROUP_WORLD_ENVIRONMENT)
	if we and we is WorldEnvironment and we.environment:
		return we.environment
	return null

# ---- Persistence ----
# Same user://settings.cfg document HudSettings.gd uses (own "graphics"
# section). load-merge-save on every save, exactly like HudSettings.gd's
# _save_to_disk(): loads the full file first so any section this script
# doesn't touch (HudSettings.gd's "ui" section, anything added later) is
# preserved verbatim.

func _load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	preset = clampi(int(cfg.get_value(SECTION, "preset", preset)), 0, Preset.CUSTOM)
	sdfgi_enabled = bool(cfg.get_value(SECTION, "sdfgi_enabled", sdfgi_enabled))
	sdfgi_quality = clampi(int(cfg.get_value(SECTION, "sdfgi_quality", sdfgi_quality)), 0, 3)
	ssr_enabled = bool(cfg.get_value(SECTION, "ssr_enabled", ssr_enabled))
	ssao_enabled = bool(cfg.get_value(SECTION, "ssao_enabled", ssao_enabled))
	ssil_enabled = bool(cfg.get_value(SECTION, "ssil_enabled", ssil_enabled))
	glow_enabled = bool(cfg.get_value(SECTION, "glow_enabled", glow_enabled))
	shadow_quality = clampi(int(cfg.get_value(SECTION, "shadow_quality", shadow_quality)), 0, 2)
	aa_mode = clampi(int(cfg.get_value(SECTION, "aa_mode", aa_mode)), 0, 3)
	view_distance = clampi(int(cfg.get_value(SECTION, "view_distance", view_distance)), VIEW_DISTANCE_MIN, VIEW_DISTANCE_MAX)
	weather_enabled = bool(cfg.get_value(SECTION, "weather_enabled", weather_enabled))
	weather_intensity = clampf(float(cfg.get_value(SECTION, "weather_intensity", weather_intensity)), 0.0, 1.0)
	foliage_enabled = bool(cfg.get_value(SECTION, "foliage_enabled", foliage_enabled))

func _save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # best-effort merge -- keep HudSettings.gd's "ui" section (and any other future section) intact
	cfg.set_value(SECTION, "preset", preset)
	cfg.set_value(SECTION, "sdfgi_enabled", sdfgi_enabled)
	cfg.set_value(SECTION, "sdfgi_quality", sdfgi_quality)
	cfg.set_value(SECTION, "ssr_enabled", ssr_enabled)
	cfg.set_value(SECTION, "ssao_enabled", ssao_enabled)
	cfg.set_value(SECTION, "ssil_enabled", ssil_enabled)
	cfg.set_value(SECTION, "glow_enabled", glow_enabled)
	cfg.set_value(SECTION, "shadow_quality", shadow_quality)
	cfg.set_value(SECTION, "aa_mode", aa_mode)
	cfg.set_value(SECTION, "view_distance", view_distance)
	cfg.set_value(SECTION, "weather_enabled", weather_enabled)
	cfg.set_value(SECTION, "weather_intensity", weather_intensity)
	cfg.set_value(SECTION, "foliage_enabled", foliage_enabled)
	cfg.save(SETTINGS_PATH)
