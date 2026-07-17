extends Node
## Verification driver for the HUD-size slider (Scripts/UI/SettingsPanel.gd /
## Scripts/Autoload/HudSettings.gd) -- proves the slider is orientation- and
## resolution-consistent (same on-screen % of the short screen side at a
## given slider value, regardless of window size/orientation).
##
## Only active with one of the flags below on the command line (see
## Scripts/Tools/LaunchTest.gd); a normal run never loads this.
##
##   --hud-scale-demo             Opens the Settings panel and sweeps the
##                                 HUD Size slider small -> large -> mid on a
##                                 timeline, for a recorded Movie Maker clip
##                                 (see tools/record_movie_maker.sh).
##   --hud-scale-still=<value>    Opens the panel, drives the slider to
##                                 <value> (0.5-2.0) via the same
##                                 slider.value assignment a real drag would
##                                 produce (so it exercises the real
##                                 value_changed -> HudSettings.set_hud_scale
##                                 path), waits for layout to settle, closes
##                                 the panel (so its cream background does
##                                 not overlap the StatsPanel HUD element
##                                 being measured), saves one screenshot to
##                                 --hud-scale-out=<path>, then quits.
##
## --resolution WxH (a Godot engine flag, set on the same command line) is
## what actually varies orientation/resolution between runs -- this driver
## just drives the slider and captures the result at whatever window size
## the engine booted with.

var player: Node = null
var panel: Node = null

var _mode_demo := false
var _still_value := -1.0
var _out_path := ""

var _t := 0.0
var _next_idx := 0
# small -> large -> mid, matching the slider's [0.5, 2.0] range.
var _timeline = [
	[0.4, 0.5],
	[2.2, 2.0],
	[4.0, 1.0],
]

var _settle_frames := 0
const SETTLE_FRAMES_NEEDED := 8

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_mode_demo = args.has("--hud-scale-demo")
	for a in args:
		if a.begins_with("--hud-scale-still="):
			_still_value = float(a.split("=")[1])
		elif a.begins_with("--hud-scale-out="):
			_out_path = a.split("=")[1]

	if not _mode_demo and _still_value < 0.0:
		queue_free()
		return

	print("[HudScaleDriver] active, waiting for player+panel...")
	print("[HudScaleDriver] DisplayServer.window_get_size()=", DisplayServer.window_get_size(),
		" root.size=", get_tree().root.size,
		" content_scale_size=", get_tree().root.content_scale_size,
		" content_scale_mode=", get_tree().root.content_scale_mode,
		" content_scale_aspect=", get_tree().root.content_scale_aspect)
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
	panel.open()

	if _mode_demo:
		print("[HudScaleDriver] player+panel found, demo sweep starting")
	else:
		print("[HudScaleDriver] player+panel found, still mode: slider -> ", _still_value)
		panel.slider.value = _still_value

func _process(delta: float) -> void:
	if not player or not panel:
		return

	if _mode_demo:
		_t += delta
		if _next_idx < _timeline.size() and _t >= _timeline[_next_idx][0]:
			var v = _timeline[_next_idx][1]
			panel.slider.value = v
			print("[HudScaleDriver] t=", _t, " slider -> ", v)
			_next_idx += 1
		return

	# Still mode: let a few frames pass so the CANVAS_ITEMS re-layout from
	# the content_scale_factor change (triggered by the slider.value
	# assignment above) fully settles before capturing.
	_settle_frames += 1
	if _settle_frames == SETTLE_FRAMES_NEEDED:
		panel.close()
	elif _settle_frames == SETTLE_FRAMES_NEEDED + 4:
		_capture_and_quit()

func _capture_and_quit() -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_path)
	print("[HudScaleDriver] saved ", _out_path, " err=", err)
	get_tree().quit()
