extends Node
## Verification driver for the "GRAPHICS QUALITY" settings section
## (Scripts/UI/SettingsPanel.gd / Scripts/Autoload/GraphicsSettings.gd).
##
## Two-phase, cross-process (see tools/verify_graphics_settings.sh): proves
## (1) the real UI controls -> GraphicsSettings -> Environment/Viewport/
## DirectionalLight3D/VoxelWorld wiring applies LIVE with no runtime errors,
## and (2) settings PERSIST across a process restart and re-apply
## automatically to a freshly loaded World scene (the "re-apply on startup"
## requirement -- GraphicsSettings.gd's autoload _ready() loads
## user://settings.cfg, World.gd's _ready() re-applies it to that scene's
## fresh WorldEnvironment/light/VoxelWorld nodes).
##
##   --graphics-settings-set     Drives the real SettingsPanel callbacks
##                                (the exact functions an OptionButton.
##                                item_selected / CheckBox.toggled /
##                                HSlider.value_changed signal would call on
##                                a real click/drag) to a preset plus two
##                                deliberate individual overrides, prints the
##                                resulting field values, and quits.
##   --graphics-settings-verify  A SEPARATE process (run after --set, with
##                                the same user:// data dir bind-mounted so
##                                settings.cfg carries over): waits for a
##                                World to load, then reads back the ACTUAL
##                                Environment / root Viewport /
##                                DirectionalLight3D / VoxelWorld state and
##                                asserts it matches what --set wrote,
##                                printing PASS/FAIL lines the verify script
##                                greps for.
##   --graphics-settings-shot=<path>  Opens the Settings panel (and leaves it
##                                open, unlike HudScaleDriver's still-mode)
##                                and saves one screenshot to <path> -- for
##                                confirming the GRAPHICS QUALITY section
##                                renders/lays out correctly. This is a
##                                software (llvmpipe) render on this dev box:
##                                it proves the UI, not the rendering
##                                effects themselves (see GraphicsSettings.gd
##                                header for why).

var player: Node = null
var panel: Node = null

var _mode_set := false
var _mode_verify := false
var _shot_path := ""
var _settle_frames := 0
const SETTLE_FRAMES_NEEDED := 8

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_mode_set = args.has("--graphics-settings-set")
	_mode_verify = args.has("--graphics-settings-verify")
	for a in args:
		if a.begins_with("--graphics-settings-shot="):
			_shot_path = a.split("=")[1]
	if not _mode_set and not _mode_verify and _shot_path == "":
		queue_free()
		return
	print("[GraphicsSettingsDriver] active, mode_set=", _mode_set, " mode_verify=", _mode_verify, " shot_path=", _shot_path)
	_find_targets()

func _find_targets() -> void:
	player = get_tree().get_first_node_in_group("player")
	panel = get_tree().get_first_node_in_group("settings_panel")
	if not player or not panel:
		await get_tree().create_timer(0.2).timeout
		_find_targets()
		return

	if "ai_enabled" in player:
		player.ai_enabled = false

	if _mode_set:
		_run_set()
	elif _mode_verify:
		_run_verify()
	elif _shot_path != "":
		panel.open()
		set_process(true)

func _process(_delta: float) -> void:
	if _shot_path == "":
		return
	_settle_frames += 1
	if _settle_frames == SETTLE_FRAMES_NEEDED:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(_shot_path)
		print("[GraphicsSettingsDriver] saved ", _shot_path, " err=", err)
		get_tree().quit()

func _run_set() -> void:
	panel.open()
	# Drive the real UI callbacks rather than poking GraphicsSettings
	# directly -- this proves the panel wiring itself, not just the
	# autoload's own API.
	panel._on_preset_selected(GraphicsSettings.Preset.HIGH)
	# Two deliberate overrides on top of the preset, to prove individual
	# controls work AND the preset -> "Custom" UI sync fires.
	panel._on_sdfgi_quality_selected(GraphicsSettings.SDFGIQuality.ULTRA)
	panel._on_view_distance_changed(7)
	await get_tree().process_frame
	await get_tree().process_frame

	print("[GraphicsSettingsDriver] SET preset=", GraphicsSettings.preset,
		" sdfgi_enabled=", GraphicsSettings.sdfgi_enabled,
		" sdfgi_quality=", GraphicsSettings.sdfgi_quality,
		" ssr=", GraphicsSettings.ssr_enabled,
		" ssao=", GraphicsSettings.ssao_enabled,
		" ssil=", GraphicsSettings.ssil_enabled,
		" glow=", GraphicsSettings.glow_enabled,
		" shadow_quality=", GraphicsSettings.shadow_quality,
		" aa_mode=", GraphicsSettings.aa_mode,
		" view_distance=", GraphicsSettings.view_distance)
	print("[GraphicsSettingsDriver] preset_dropdown.selected=", panel._preset_dropdown.selected,
		" expect_custom=", GraphicsSettings.Preset.CUSTOM)
	get_tree().quit()

func _run_verify() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var env := _get_environment()
	var root := get_tree().root
	var vw := get_tree().get_first_node_in_group("voxel_world")
	var light := get_tree().get_first_node_in_group("directional_light")

	var checks := []
	checks.append(["env not null", env != null])
	if env:
		checks.append(["sdfgi_enabled == true", env.sdfgi_enabled == true])
		checks.append(["sdfgi_cascades == 8 (Ultra override)", env.sdfgi_cascades == 8])
		checks.append(["ssr_enabled == true", env.ssr_enabled == true])
		checks.append(["ssao_enabled == true", env.ssao_enabled == true])
		checks.append(["ssil_enabled == true", env.ssil_enabled == true])
		checks.append(["glow_enabled == true", env.glow_enabled == true])
	checks.append(["root.msaa_3d == MSAA_2X (High preset)", root.msaa_3d == Viewport.MSAA_2X])
	checks.append(["vw not null", vw != null])
	if vw:
		checks.append(["render_distance == 7 (override)", vw.render_distance == 7])
	checks.append(["light not null", light != null])
	if light:
		checks.append(["light.shadow_enabled == true", light.shadow_enabled == true])
	checks.append(["GraphicsSettings.preset == CUSTOM (post-override)", GraphicsSettings.preset == GraphicsSettings.Preset.CUSTOM])

	var all_pass := true
	for c in checks:
		var ok = c[1]
		all_pass = all_pass and ok
		print("[GraphicsSettingsDriver] ", ("PASS" if ok else "FAIL"), " -- ", c[0])
	print("[GraphicsSettingsDriver] RESULT=", ("PASS" if all_pass else "FAIL"))
	get_tree().quit()

func _get_environment() -> Environment:
	var we := get_tree().get_first_node_in_group("world_environment")
	if we and we.environment:
		return we.environment
	return null
