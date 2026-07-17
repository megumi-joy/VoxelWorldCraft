extends Node

func _ready():
	printerr("LaunchTest: Starting...")
	# Wait a frame to ensure autoloads ready?
	await get_tree().process_frame
	printerr("LaunchTest: Calling host_game...")
	NetworkManager.host_game()
	printerr("LaunchTest: host_game returned.")

	# Movement-feel verification: --movement-demo spawns a driver that
	# simulates a scripted move+sprint+jump input timeline against the real
	# Player.gd manual-input path (see MovementDemoDriver.gd). Attached under
	# the tree root via Engine.get_main_loop() rather than self.get_tree(),
	# because NetworkManager.host_game() above already swapped/detached this
	# node from the tree (change_scene_to_file takes effect synchronously
	# here, not deferred to end of frame -- self.get_tree() is null already).
	# NOTE: args after "--" land in OS.get_cmdline_user_args(), not
	# OS.get_cmdline_args() (which only holds engine-recognized args).
	if OS.get_cmdline_user_args().has("--movement-demo"):
		var driver = load("res://Scripts/Testing/MovementDemoDriver.gd").new()
		driver.name = "MovementDemoDriver"
		var tree := Engine.get_main_loop() as SceneTree
		tree.root.add_child(driver)

	# HUD-size slider verification (Scripts/Testing/HudScaleDriver.gd): see
	# that file's header for the --hud-scale-demo / --hud-scale-still= /
	# --hud-scale-out= flags. Same "attach under the tree root" pattern as
	# --movement-demo above, and for the same reason (this node is already
	# detached from its own get_tree() by host_game()'s change_scene_to_file
	# by this point).
	var user_args := OS.get_cmdline_user_args()
	var wants_hud_driver := user_args.has("--hud-scale-demo")
	for a in user_args:
		if a.begins_with("--hud-scale-still="):
			wants_hud_driver = true
	if wants_hud_driver:
		var hud_driver = load("res://Scripts/Testing/HudScaleDriver.gd").new()
		hud_driver.name = "HudScaleDriver"
		var tree2 := Engine.get_main_loop() as SceneTree
		tree2.root.add_child(hud_driver)
