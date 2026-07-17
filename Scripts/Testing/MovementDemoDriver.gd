extends Node
## Headless movement-feel verification driver.
##
## Simulates real input ACTIONS (Input.action_press/action_release) on a
## timeline, not direct velocity writes -- so a recorded clip exercises the
## exact same code path a real player uses in Player.gd's manual-input
## branch: acceleration/friction, sprint, jump (coyote time + buffering),
## head-bob, and the sprint FOV kick. This is deliberately NOT routed through
## Player.process_ai(), which drives velocity directly and would bypass all
## of the above.
##
## Only active with --movement-demo on the command line (see
## Scripts/Tools/LaunchTest.gd, which instantiates this under the scene
## root). Forces player.ai_enabled = false, because Player.gd's _ready()
## auto-enables the (unrelated) wander-AI whenever OS.has_feature("headless")
## is true, which would otherwise hijack movement.

var player: CharacterBody3D = null
var _t: float = 0.0
var _next_idx: int = 0
var _log_timer: float = 0.0

# [time_seconds, action_name, pressed] -- walk, sprint, jump (coyote/buffer
# gets exercised by jumping while already moving), strafe both ways, and a
# second jump while sprinting.
var _timeline = [
	[0.5, "move_forward", true],
	[1.8, "sprint", true],
	[2.3, "jump", true],
	[2.45, "jump", false],
	[4.0, "sprint", false],
	[4.3, "move_forward", false],
	[4.5, "move_left", true],
	[5.8, "move_left", false],
	[5.8, "move_right", true],
	[6.5, "jump", true],
	[6.65, "jump", false],
	[7.3, "move_right", false],
]

func _ready():
	# Args after "--" land in OS.get_cmdline_user_args(), not
	# OS.get_cmdline_args() (which only holds engine-recognized args).
	if not OS.get_cmdline_user_args().has("--movement-demo"):
		queue_free()
		return
	print("[MovementDemo] driver active, waiting for player...")
	_find_player()

func _find_player():
	player = get_tree().get_first_node_in_group("player")
	if not player:
		await get_tree().create_timer(0.2).timeout
		_find_player()
		return
	player.ai_enabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("[MovementDemo] player found, ai_enabled forced to ", player.ai_enabled, ", starting scripted timeline")

func _process(delta):
	if not player:
		return
	_t += delta

	# Gentle, bounded mouse-look pan for the whole clip: exercises the
	# _unhandled_input look-smoothing path (otherwise never touched by this
	# driver, since it only presses movement/jump/sprint actions) and keeps
	# the camera turning during the clip. Small amplitude on purpose -- this
	# is meant to demonstrate smoothing, not steer the player into new
	# terrain (which would cost extra chunk-gen time in this slow renderer).
	var pan_event = InputEventMouseMotion.new()
	pan_event.relative = Vector2(sin(_t * 1.3) * 2.0, 0.0)
	Input.parse_input_event(pan_event)

	while _next_idx < _timeline.size() and _t >= _timeline[_next_idx][0]:
		var ev = _timeline[_next_idx]
		if ev[2]:
			Input.action_press(ev[1])
		else:
			Input.action_release(ev[1])
		print("[MovementDemo] t=", String.num(_t, 2), " ", ev[1], " -> ", ev[2])
		_next_idx += 1

	# Periodic state snapshot so the log alone proves the manual movement
	# path ran (speed reaching sprint_speed, FOV kicking above base, jumps
	# actually firing, head-bob offsetting the camera off its base local
	# position while moving) independent of the rendered clip.
	_log_timer += delta
	if _log_timer >= 0.5:
		_log_timer = 0.0
		var hspeed = Vector2(player.velocity.x, player.velocity.z).length()
		print("[MovementDemo] t=", String.num(_t, 2),
			" hspeed=", String.num(hspeed, 2),
			" vel.y=", String.num(player.velocity.y, 2),
			" fov=", String.num(player.camera.fov, 1),
			" cam_local_pos=", player.camera.position,
			" head_yaw_deg=", String.num(rad_to_deg(player.head.rotation.y), 1),
			" on_floor=", player.is_on_floor(),
			" ai_enabled=", player.ai_enabled)
