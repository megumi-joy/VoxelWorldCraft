extends Node
## Scripted "movement + mining" driver for two purposes at once:
##
## 1. Repro/verification for the mining fixes in Player.gd (hold-to-mine
##    delay, single-target lock, refusing to mine the block under your own
##    feet): drives the REAL input paths (Input.action_press for movement,
##    player.mock_left_click/mock_right_click for clicking, direct
##    head/camera rotation for aim) rather than calling VoxelWorld directly,
##    so it exercises manual_interaction_check()/_process_mining() exactly
##    like a real player holding LMB would -- including the "dig straight
##    down while standing on the block" case that used to be able to chain-
##    break a shaft and drop the player into the void
##    ("копание вниз убивает").
## 2. The gameplay video (owner ask: show real locomotion + actions, not a
##    static camera): walk, look around, attempt-then-refuse mining your own
##    feet, mine a real block with the new delay, place a block, walk more.
##    Run with --write-movie <path>.avi --fixed-fps 30 for a recording.
##
## Only active with --dig-demo on the command line (see Scripts/Tools/
## LaunchTest.gd, which instantiates this under the scene root). Mirrors
## MovementDemoDriver.gd's opt-in-flag convention -- inert with the flag
## absent, so this can never affect normal play.

var player: CharacterBody3D = null
var _t: float = 0.0
var _done_steps: Dictionary = {} # step name -> true, so each step fires once
var _log_timer: float = 0.0

func _ready():
	# Args after "--" land in OS.get_cmdline_user_args(), not
	# OS.get_cmdline_args() (which only holds engine-recognized args).
	if not OS.get_cmdline_user_args().has("--dig-demo"):
		queue_free()
		return
	print("[DigDemo] driver active, waiting for player...")
	_find_player()

func _find_player():
	player = get_tree().get_first_node_in_group("player")
	if not player:
		await get_tree().create_timer(0.2).timeout
		_find_player()
		return
	player.ai_enabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("[DigDemo] player found at ", player.global_position, ", starting scripted timeline")

func _process(delta):
	if not player:
		return
	_t += delta

	# --- Scripted timeline -------------------------------------------------
	if _t >= 0.2 and not _done_steps.has("walk1_start"):
		_done_steps["walk1_start"] = true
		print("[DigDemo] t=", String.num(_t, 2), " walk forward")
		Input.action_press("move_forward")

	if _t >= 2.2 and not _done_steps.has("walk1_stop"):
		_done_steps["walk1_stop"] = true
		Input.action_release("move_forward")

	if _t >= 2.3 and not _done_steps.has("look_around"):
		_done_steps["look_around"] = true
		print("[DigDemo] t=", String.num(_t, 2), " looking around")

	# Visible side-to-side look during the 2.3-3.3s window above (owner ask:
	# the video needs to show real looking-around, not just a static
	# camera). Applied as a head-yaw delta every frame in this window rather
	# than a one-shot rotation so it reads as an actual look motion on camera.
	if _t >= 2.3 and _t < 3.3 and player.head:
		player.head.rotate_y(sin((_t - 2.3) * 6.0) * 0.03)

	if _t >= 3.3 and not _done_steps.has("aim_down"):
		_done_steps["aim_down"] = true
		if player.head: player.head.rotation.y = 0.0
		if player.camera: player.camera.rotation.x = deg_to_rad(-89.0)
		print("[DigDemo] t=", String.num(_t, 2), " aiming straight down at own feet, on_floor=", player.is_on_floor())

	# Hold LMB on the block under the player's own feet -- with the fix this
	# should print/refuse and never actually remove that block or kill the
	# player; on unfixed code this is exactly the "dig straight down" repro.
	if _t >= 3.5 and _t < 6.0:
		player.mock_left_click = true
	elif _t >= 6.0 and not _done_steps.has("release_underfoot_mine"):
		_done_steps["release_underfoot_mine"] = true
		player.mock_left_click = false
		print("[DigDemo] t=", String.num(_t, 2), " released under-feet mining attempt, health=",
			player.stats.health if player.stats else -1, " pos=", player.global_position)

	if _t >= 6.3 and not _done_steps.has("aim_forward_down"):
		_done_steps["aim_forward_down"] = true
		if player.camera: player.camera.rotation.x = deg_to_rad(-35.0)
		print("[DigDemo] t=", String.num(_t, 2), " aiming forward-down at a real block to mine (hold-to-mine delay)")

	# Mine a real block ahead (not under feet) -- long enough to clear even
	# the slowest break_speed (BREAK_SPEED_WITHOUT_TOOL = 0.5s).
	if _t >= 6.5 and _t < 8.2:
		player.mock_left_click = true
	elif _t >= 8.2 and not _done_steps.has("release_forward_mine"):
		_done_steps["release_forward_mine"] = true
		player.mock_left_click = false
		print("[DigDemo] t=", String.num(_t, 2), " released forward mining")

	if _t >= 8.5 and not _done_steps.has("walk2_start"):
		_done_steps["walk2_start"] = true
		if player.camera: player.camera.rotation.x = deg_to_rad(-10.0)
		print("[DigDemo] t=", String.num(_t, 2), " walk forward again + jump")
		Input.action_press("move_forward")

	if _t >= 9.5 and not _done_steps.has("jump1"):
		_done_steps["jump1"] = true
		Input.action_press("jump")

	if _t >= 9.65 and not _done_steps.has("jump1_release"):
		_done_steps["jump1_release"] = true
		Input.action_release("jump")

	if _t >= 11.0 and not _done_steps.has("walk2_stop"):
		_done_steps["walk2_stop"] = true
		Input.action_release("move_forward")

	if _t >= 11.3 and not _done_steps.has("aim_place"):
		_done_steps["aim_place"] = true
		if player.camera: player.camera.rotation.x = deg_to_rad(-30.0)
		print("[DigDemo] t=", String.num(_t, 2), " placing a block")

	if _t >= 11.5 and _t < 11.8:
		player.mock_right_click = true
	elif _t >= 11.8 and not _done_steps.has("release_place"):
		_done_steps["release_place"] = true
		player.mock_right_click = false

	if _t >= 12.2 and not _done_steps.has("walk3_start"):
		_done_steps["walk3_start"] = true
		if player.camera: player.camera.rotation.x = deg_to_rad(0.0)
		print("[DigDemo] t=", String.num(_t, 2), " walk + sprint + look around to close out")
		Input.action_press("move_forward")
		Input.action_press("sprint")

	if _t >= 15.5 and not _done_steps.has("walk3_stop"):
		_done_steps["walk3_stop"] = true
		Input.action_release("move_forward")
		Input.action_release("sprint")

	# Gentle continuous look-pan for the whole clip after the scripted aims
	# above finish, purely for visual interest in the recorded video (same
	# idea as MovementDemoDriver's pan) -- small amplitude so it doesn't
	# fight the aimed shots above.
	if _t >= 12.2 and player.head:
		player.head.rotate_y(sin(_t * 0.8) * 0.01)

	# Periodic state snapshot -- proves out_of no death/void/damage occurred
	# and shows real movement, independent of the rendered clip.
	_log_timer += delta
	if _log_timer >= 0.5:
		_log_timer = 0.0
		print("[DigDemo] t=", String.num(_t, 2),
			" pos=", player.global_position,
			" vel.y=", String.num(player.velocity.y, 2),
			" on_floor=", player.is_on_floor(),
			" health=", player.stats.health if player.stats else -1)

	# Safety self-terminate, well beyond this driver's ~18s scripted clip --
	# only matters for a plain log-only verification run (no --write-movie),
	# so it never needs an external `timeout` wrapper. When recording,
	# --write-movie's own --quit-after frame count is what actually
	# terminates the process; keep this comfortably above that.
	if _t >= 40.0 and not _done_steps.has("quit"):
		_done_steps["quit"] = true
		print("[DigDemo] t=", String.num(_t, 2), " safety timeout, quitting")
		get_tree().quit()
