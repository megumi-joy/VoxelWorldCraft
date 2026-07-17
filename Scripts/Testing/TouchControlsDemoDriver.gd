extends Node
## Verification driver for Scripts/UI/TouchControls.gd -- proves the touch
## layer renders correctly over real gameplay and exercises it through the
## same public entry points a finger would (force_touch_mode(),
## joystick.set_knob_offset(), player.touch_move_vector, touch_jump()),
## not by faking a screenshot.
##
## Only active with one of the flags below on the command line (see
## Scripts/Tools/LaunchTest.gd, which instantiates this under the scene
## root); a normal run never loads this.
##
##   --touch-demo               Forces touch mode on, then sweeps the
##                               joystick + look-drag + a Jump press on a
##                               timeline, for a recorded Movie Maker clip
##                               (see tools/record_movie_maker.sh).
##   --touch-still=<path>       Forces touch mode on, pushes the joystick to
##                               a fixed offset and taps Jump once so the
##                               screenshot shows controls mid-use (not just
##                               idle), waits for a few frames to settle,
##                               saves one screenshot to <path>, then quits.

var player: Node = null
var touch_controls: Node = null

var _mode_demo := false
var _out_path := ""

var _t := 0.0
var _settle_frames := 0
const SETTLE_FRAMES_NEEDED := 10

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_mode_demo = args.has("--touch-demo")
	for a in args:
		if a.begins_with("--touch-still="):
			_out_path = a.split("=")[1]

	if not _mode_demo and _out_path == "":
		queue_free()
		return

	print("[TouchDemo] active, waiting for player+TouchControls...")
	_find_targets()

func _find_targets() -> void:
	player = get_tree().get_first_node_in_group("player")
	touch_controls = player.get_node_or_null("TouchControls") if player else null
	if not player or not touch_controls:
		await get_tree().create_timer(0.2).timeout
		_find_targets()
		return

	# Deterministic pose for the screenshot/clip: no wander-AI fighting the
	# scripted joystick/look input below. Player.gd auto-enables ai_enabled
	# under OS.has_feature("headless"), which this Xvfb-under-podman render
	# path does NOT set (it's a real, if virtual, display) -- forced anyway
	# to be explicit and safe if that ever changes.
	if "ai_enabled" in player:
		player.ai_enabled = false

	touch_controls.force_touch_mode(true)
	print("[TouchDemo] player+TouchControls found, ai_enabled forced to false, touch mode forced on")

	if not _mode_demo:
		# Still mode: push the joystick to a fixed forward-right offset and
		# tap Jump once, exactly like a real drag+tap would, via the same
		# public entry points a finger uses (not by faking pixels).
		var joystick = touch_controls.get_node_or_null("Root/Joystick")
		if joystick:
			joystick.set_knob_offset(Vector2(0.5, -0.6), true)
		player.touch_move_vector = Vector2(0.5, -0.6)
		player.apply_look_delta(Vector2(40, -10))
		player.touch_jump()

func _process(delta: float) -> void:
	if not player or not touch_controls:
		return

	if _mode_demo:
		_t += delta
		var joystick = touch_controls.get_node_or_null("Root/Joystick")
		# Slow circular sweep of the movement joystick + a gentle look pan,
		# with a Jump tap every ~2s -- keeps the clip visibly "in use"
		# rather than a static overlay sitting over gameplay.
		var sweep = Vector2(sin(_t * 0.8), cos(_t * 0.8)) * 0.7
		if joystick:
			joystick.set_knob_offset(sweep, true)
		player.touch_move_vector = sweep
		player.apply_look_delta(Vector2(sin(_t * 1.1) * 3.0, 0.0))
		if fmod(_t, 2.0) < delta:
			player.touch_jump()
		return

	# Still mode: let a few frames pass so the joystick knob redraw / camera
	# look delta / physics settle before capturing.
	_settle_frames += 1
	if _settle_frames == SETTLE_FRAMES_NEEDED:
		_capture_and_quit()

func _capture_and_quit() -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_path)
	print("[TouchDemo] saved ", _out_path, " err=", err)
	get_tree().quit()
