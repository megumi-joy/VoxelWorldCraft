extends Node
class_name AutoTester

# This script automates player actions for testing and log generation
# It mimics the sequence: Wander -> Gather -> Craft -> Farm -> Log

var player: CharacterBody3D
var world: VoxelWorld
var log_data = []

var command_queue = [
	{"action": "wait", "duration": 2.0, "reason": "Wait for world gen"},
	{"action": "look", "target": Vector3(0, -0.5, -1), "reason": "Look at ground"},
	{"action": "move", "direction": Vector2(0, 1), "duration": 1.0, "reason": "Walk forward"},
	{"action": "interact_left", "times": 3, "reason": "Gather Dirt"},
	{"action": "select_slot", "slot": 3, "reason": "Select Hoe"}, # Slot 3 for Hoe
	{"action": "interact_right", "times": 1, "reason": "Till Soil"},
	{"action": "select_slot", "slot": 4, "reason": "Select Seeds"},
	{"action": "interact_right", "times": 1, "reason": "Plant Wheat"},
	{"action": "look", "target": Vector3(1, 0, 0), "reason": "Look at sunset"},
	{"action": "wait", "duration": 1.0, "reason": "Final check"}
]

var current_cmd_idx = 0
var cmd_timer = 0.0

func _ready():
	player = get_parent() # Assuming attached to Player
	world = get_node_or_null("/root/World/VoxelWorld")
	print("--- AUTO TESTER STARTED ---")
	add_log("System", "Bot Initialized at " + str(player.global_position))

var active_action_timer = 0.0

func _process(delta):
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
	var action = cmd["action"]
	add_log("Action", cmd["reason"])
	
	match action:
		"look":
			player.head.look_at(player.global_position + cmd["target"], Vector3.UP)
		"move":
			# Use Input simulation
			var duration = cmd.get("duration", 0.5)
			active_action_timer = duration
			Input.action_press("move_forward") # Simplified, can expand to check direction
		"interact_left":
			mock_click(true, cmd.get("times", 1))
		"interact_right":
			mock_click(false, cmd.get("times", 1))
		"select_slot":
			player.on_hotbar_select(cmd["slot"]) # Using Item Id for now as per Player.gd
	
	var metrics = {
		"fps": Engine.get_frames_per_second(),
		"pos": str(player.global_position),
		"chunks": world.chunks.size() if world else 0
	}
	add_log("Metrics", metrics)

func update_sustained_actions():
	if active_action_timer <= 0:
		Input.action_release("move_forward")
		player.mock_left_click = false
		player.mock_right_click = false

func mock_click(left: bool, times: int):
	if left: player.mock_left_click = true
	else: player.mock_right_click = true
	active_action_timer = 0.2 * times # Duration for click to registration

func add_log(type: String, data):
	var entry = {
		"timestamp": Time.get_ticks_msec(),
		"type": type,
		"data": data
	}
	log_data.append(entry)
	print("[AUTO_LOG] %s: %s" % [type, str(data)])

func finish_test():
	var json_str = JSON.stringify(log_data, "\t")
	var file = FileAccess.open("user://playthrough_log.json", FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		print("--- AUTO TESTER FINISHED: LOG SAVED TO user://playthrough_log.json ---")
	
	# Quit if headless/profiling
	if OS.get_cmdline_args().has("--profile"):
		get_tree().quit()
