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

	# Touch-controls verification: --touch-demo forces Scripts/UI/
	# TouchControls.gd visible (bypassing its own live auto-detection, which
	# would otherwise flip it back to desktop mode on the first stray mouse
	# event Xvfb/podman generates) and drives the joystick + a button press
	# so the recorded frame/clip shows the layer mid-use, not just idle. See
	# TouchControlsDemoDriver.gd for the --touch-still=<path> single-frame
	# capture mode used by tools/record_movie_maker.sh style invocations.
	# Same "attach under the tree root" reasoning as --movement-demo above.
	var user_args := OS.get_cmdline_user_args()
	var wants_touch_driver := user_args.has("--touch-demo")
	for a in user_args:
		if a.begins_with("--touch-still="):
			wants_touch_driver = true
	if wants_touch_driver:
		var touch_driver = load("res://Scripts/Testing/TouchControlsDemoDriver.gd").new()
		touch_driver.name = "TouchControlsDemoDriver"
		var tree3 := Engine.get_main_loop() as SceneTree
		tree3.root.add_child(touch_driver)
