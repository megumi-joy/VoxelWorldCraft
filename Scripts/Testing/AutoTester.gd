extends Node
class_name AutoTester

# This script automates player actions for testing and log generation
# It mimics the sequence: Wander -> Gather -> Craft -> Farm -> Log

var player: CharacterBody3D
var world
var log_data = []

var command_queue = [
	{"action": "wait", "duration": 3.0, "reason": "Wait for world gen"},
	{"action": "look", "target": Vector3(0, -1, -2), "reason": "Look at ground"},
	{"action": "move", "duration": 1.0, "reason": "Walk forward"},
	{"action": "interact_left", "times": 2, "duration": 1.0, "reason": "Gather Dirt"},
	{"action": "select_slot", "slot": 3, "duration": 0.5, "reason": "Select Hoe"}, 
	{"action": "interact_right", "times": 1, "duration": 0.5, "reason": "Till Soil"},
	{"action": "select_slot", "slot": 4, "duration": 0.5, "reason": "Select Seeds"},
	{"action": "interact_right", "times": 1, "duration": 0.5, "reason": "Plant Wheat"},
	{"action": "look", "target": Vector3(1, 0.2, 0), "duration": 1.0, "reason": "Look at sunset"},
	{"action": "wait", "duration": 2.0, "reason": "Final check"}
]

var current_cmd_idx = 0
var cmd_timer = 0.0
var is_mouse_moving = false
var user_active_timer = 0.0
const USER_INACTIVITY_LIMIT = 5.0 # Seconds before bot resumes

func _input(event):
	if event is InputEventMouseMotion:
		is_mouse_moving = true
	
	if event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed():
			# User pressed something, give control
			user_active_timer = USER_INACTIVITY_LIMIT
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			print("--- USER TAKEOVER: Bot Suspended (Key/Mouse pressed) ---")

func _ready():
	# Try to find player in tree if parent is not player
	if get_parent().is_in_group("player"):
		player = get_parent()
	else:
		# Wait a bit or search
		call_deferred("find_player")
	
	world = get_node_or_null("/root/World/VoxelWorld")
	
	# Check for auto-run arg
	if not OS.get_cmdline_args().has("--run-tests"):
		set_process(false) # Disable if not testing
		print("--- AUTO TESTER IDLE (Use --run-tests to activate) ---")
	else:
		print("--- AUTO TESTER ACTIVATED ---")

func find_player():
	var p = get_tree().get_first_node_in_group("player")
	if p:
		player = p
		add_log("System", "Bot linked to Player at " + str(player.global_position))
	else:
		print("AutoTester: Player not found yet, retrying...")
		await get_tree().create_timer(1.0).timeout
		find_player()

var active_action_timer = 0.0

func _process(delta):
	if not player: return
	
	# Check for mouse movement activity
	# In automated test mode, we might get phantom global mouse events or OS cursor moves.
	# Let's invalid this check if we are running with --profile or just ignore subtle moves.
	if is_mouse_moving and OS.has_feature("editor") == false: # Only care in exported/real game? 
		# Or just increase threshold
		pass
	
	if is_mouse_moving:
		# For now, disable this check for the automated run to ensure completion
		# user_active_timer = USER_INACTIVITY_LIMIT
		# is_mouse_moving = false
		pass 
		
	if user_active_timer > 0:
		user_active_timer -= delta
		return
	
	# If bot resumes, it might want to capture mouse for 'look' commands
	# but only if not in a UI menu. For now, let's keep it VISIBLE for user ease.
	
	if current_cmd_idx >= command_queue.size():
		if cmd_timer >= 0:
			finish_test()
			cmd_timer = -1.0
		return
		
	cmd_timer -= delta
	active_action_timer -= delta
	
	if cmd_timer <= 0:
		var cmd = command_queue[current_cmd_idx]
		execute_command(cmd)
		current_cmd_idx += 1
		if current_cmd_idx < command_queue.size():
			cmd_timer = command_queue[current_cmd_idx].get("duration", 0.5)
	
	# Handle sustained actions (like moving)
	update_sustained_actions()

func execute_command(cmd):
	if not player: return
	
	var action = cmd["action"]
	add_log("Action", cmd["reason"])
	
	match action:
		"look":
			player.head.look_at(player.global_position + cmd["target"], Vector3.UP)
		"move":
			var duration = cmd.get("duration", 0.5)
			active_action_timer = duration
			Input.action_press("move_forward")
		"interact_left":
			mock_click(true, cmd.get("times", 1))
		"interact_right":
			mock_click(false, cmd.get("times", 1))
		"select_slot":
			if player.has_method("on_hotbar_select"):
				player.on_hotbar_select(cmd["slot"])
	
	var metrics = {
		"fps": Engine.get_frames_per_second(),
		"pos": str(player.global_position) if player else "N/A",
		"chunks": world.chunks.size() if world else 0,
		"health": player.stats.health if player and player.get("stats") else 0,
		"hunger": player.stats.hunger if player and player.get("stats") else 0,
		"gold": player.stats.gold if player and player.get("stats") else 0
	}
	add_log("Metrics", metrics)

func update_sustained_actions():
	if not player: return
	if active_action_timer <= 0:
		Input.action_release("move_forward")
		player.mock_left_click = false
		player.mock_right_click = false

func mock_click(left: bool, times: int):
	if not player: return
	if left: player.mock_left_click = true
	else: player.mock_right_click = true
	active_action_timer = 0.2 * times 
	
	# Take screenshot on interaction
	take_screenshot("interaction")

func take_screenshot(label: String):
	if OS.has_feature("headless"):
		# In headless mode, we might need to wait for a frame to render if we have a dummy viewport
		# However, Godot's --headless usually doesn't render unless configured.
		# For this project, we'll assume the user wants a visible run or a way to verify.
		pass
	
	var image = get_viewport().get_texture().get_image()
	var docs_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var time = Time.get_datetime_string_from_system().replace(":", "-")
	var path = docs_dir + "/screenshot_%s_%s.png" % [label, time]
	image.save_png(path)
	print("[AUTO_TESTER] Screenshot saved to: " + path)

func add_log(type: String, data):
	var entry = {
		"timestamp": Time.get_ticks_msec(),
		"type": type,
		"data": data
	}
	log_data.append(entry)
	print("[AUTO_LOG] %s: %s" % [type, str(data)])

func finish_test():
	print("--- AUTO TESTER: CONSTRUCTING JSON ---")
	var json_str = JSON.stringify(log_data, "\t")
	
	# Force save to Documents to avoid path issues
	var docs_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var file_path = docs_dir + "/playthrough_log.json"
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		print("--- AUTO TESTER FINISHED: LOG SAVED TO " + file_path)
	else:
		print("ERROR: Could not save log file to " + file_path)
		# Fallback: Print to console
		print("--- AUTO TESTER LOG DUMP ---")
		print(json_str)
		print("--- END LOG DUMP ---")
	
	# Ensure game quits after bot is done
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _exit_tree():
	if log_data.size() > 0:
		# Try to save what we have
		print("AutoTester exiting, saving partial log...")
		var json_str = JSON.stringify(log_data, "\t")
		var docs_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		var file_path = docs_dir + "/playthrough_log.json"
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		if file:
			file.store_string(json_str)
			file.close()
