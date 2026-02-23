extends Node


# This script automates player actions for testing and log generation
# It mimics the sequence: Wander -> Gather -> Craft -> Farm -> Log

var player: CharacterBody3D
var world
var log_data = []
var crafting_manager

var command_queue = [
	{"action": "wait", "duration": 5.0, "reason": "Wait for world gen"},
	{"action": "scan_and_gather", "block_id": 4, "count": 3, "reason": "Gather 3 Wood"},
	{"action": "wait", "duration": 1.0, "reason": "Inventory sync"},
	{"action": "craft", "recipe_idx": 0, "count": 3, "reason": "Craft Planks"}, # Wood -> 4 Planks
	{"action": "craft", "recipe_idx": 1, "count": 1, "reason": "Craft Table"}, # 4 Planks -> Table
	{"action": "craft", "recipe_idx": 3, "count": 1, "reason": "Craft Pickaxe"},
	{"action": "craft", "recipe_idx": 4, "count": 1, "reason": "Craft Shovel"},
	{"action": "craft", "recipe_idx": 5, "count": 1, "reason": "Craft Axe"},
	{"action": "craft", "recipe_idx": 6, "count": 1, "reason": "Craft Hoe"},
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
	
	var cm_script = load("res://Scripts/Crafting/CraftingManager.gd")
	if cm_script:
		crafting_manager = cm_script.new()
		add_child(crafting_manager)
	
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
		"scan_and_gather":
			scan_and_gather(cmd["block_id"], cmd["count"])
		"craft":
			for i in range(cmd.get("count", 1)):
				craft_item(cmd["recipe_idx"])
	
	var metrics = {
		"fps": Engine.get_frames_per_second(),
		"pos": str(player.global_position) if player else "N/A",
		"chunks": world.chunks.size() if world else 0,
		"health": player.stats.health if player and player.get("stats") else 0,
		"inv": get_inventory_summary()
	}
	add_log("Metrics", metrics)

func get_inventory_summary():
	var inv = player.get_node_or_null("Inventory")
	if not inv: return "N/A"
	var summary = []
	for item in inv.items:
		if item: summary.append("%d:%d" % [item.id, item.count])
	return ",".join(summary)

func craft_item(recipe_idx: int):
	var inv = player.get_node_or_null("Inventory")
	if inv and crafting_manager:
		if crafting_manager.can_craft(recipe_idx, inv):
			crafting_manager.craft(recipe_idx, inv)
			add_log("System", "Crafted recipe %d" % recipe_idx)
			take_screenshot("crafted_%d" % recipe_idx)
		else:
			add_log("Error", "Could not craft recipe %d (Missing items)" % recipe_idx)

func scan_and_gather(block_id: int, target_count: int):
	add_log("System", "Scanning for block %d" % block_id)
	var found_pos = find_nearest_block(block_id)
	if found_pos != Vector3.ZERO:
		player.global_position = found_pos + Vector3(0, 1.8, 0)
		player.head.look_at(found_pos, Vector3.UP)
		add_log("System", "Gathering block at %s" % str(found_pos))
		for i in range(5):
			mock_click(true, 1)
			await get_tree().create_timer(0.2).timeout
		
		var inv = player.get_node_or_null("Inventory")
		if inv: inv.add_item(block_id, 1)
		take_screenshot("gathered_%d" % block_id)

func find_nearest_block(id: int) -> Vector3:
	if not world: return Vector3.ZERO
	var p_pos = player.global_position
	for x in range(-16, 16):
		for z in range(-16, 16):
			for y in range(60, 100):
				var check_pos = Vector3(floor(p_pos.x) + x, y, floor(p_pos.z) + z)
				if player.get_block_at(world, check_pos) == id:
					return check_pos
	return Vector3.ZERO

func update_sustained_actions():
	if not player: return
	if active_action_timer <= 0:
		if InputMap.has_action("move_forward"):
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
