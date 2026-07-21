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

	# Graphics-settings verification (Scripts/Testing/GraphicsSettingsDriver.gd):
	# see that file's header for the --graphics-settings-set /
	# --graphics-settings-verify / --graphics-settings-shot= flags. Same
	# "attach under the tree root" pattern as the drivers above, for the
	# same reason.
	var wants_gfx_driver := user_args.has("--graphics-settings-set") or user_args.has("--graphics-settings-verify")
	for a in user_args:
		if a.begins_with("--graphics-settings-shot="):
			wants_gfx_driver = true
	if wants_gfx_driver:
		var gfx_driver = load("res://Scripts/Testing/GraphicsSettingsDriver.gd").new()
		gfx_driver.name = "GraphicsSettingsDriver"
		var tree3 := Engine.get_main_loop() as SceneTree
		tree3.root.add_child(gfx_driver)

	# Wave 2 verification/showcase: minerals + Field Journal + discovery,
	# see Scripts/Testing/Wave2DemoDriver.gd for what it exercises.
	if user_args.has("--wave2-demo"):
		var wave2_driver = load("res://Scripts/Testing/Wave2DemoDriver.gd").new()
		wave2_driver.name = "Wave2DemoDriver"
		var tree4 := Engine.get_main_loop() as SceneTree
		tree4.root.add_child(wave2_driver)

	# Touch-controls verification: --touch-demo forces Scripts/UI/
	# TouchControls.gd visible (bypassing its own live auto-detection, which
	# would otherwise flip it back to desktop mode on the first stray mouse
	# event Xvfb/podman generates) and drives the joystick + a button press
	# so the recorded frame/clip shows the layer mid-use, not just idle. See
	# TouchControlsDemoDriver.gd for the --touch-still=<path> single-frame
	# capture mode used by tools/record_movie_maker.sh style invocations.
	# Same "attach under the tree root" reasoning as --movement-demo above.
	var wants_touch_driver := user_args.has("--touch-demo")
	for a in user_args:
		if a.begins_with("--touch-still="):
			wants_touch_driver = true
	if wants_touch_driver:
		var touch_driver = load("res://Scripts/Testing/TouchControlsDemoDriver.gd").new()
		touch_driver.name = "TouchControlsDemoDriver"
		var tree5 := Engine.get_main_loop() as SceneTree
		tree5.root.add_child(touch_driver)

	# Dig/mining verification + gameplay showcase: walks, looks around,
	# attempts (and expects refusal of) mining the block under its own feet,
	# mines a real block with the hold-to-mine delay, places a block, walks
	# more. See Scripts/Testing/DigMiningDemoDriver.gd. Same "attach under
	# the tree root" pattern as --movement-demo above, for the same reason.
	if user_args.has("--dig-demo"):
		var dig_driver = load("res://Scripts/Testing/DigMiningDemoDriver.gd").new()
		dig_driver.name = "DigMiningDemoDriver"
		var tree6 := Engine.get_main_loop() as SceneTree
		tree6.root.add_child(dig_driver)

	# Torch + Sheep verification/showcase: see
	# Scripts/Testing/TorchSheepDemoDriver.gd for what it exercises (content
	# self-check + a scripted timeline that places a Torch and spawns a
	# Sheep in front of the player). Same "attach under the tree root"
	# pattern as the drivers above, for the same reason.
	if user_args.has("--torchsheep-demo"):
		var torchsheep_driver = load("res://Scripts/Testing/TorchSheepDemoDriver.gd").new()
		torchsheep_driver.name = "TorchSheepDemoDriver"
		var tree7 := Engine.get_main_loop() as SceneTree
		tree7.root.add_child(torchsheep_driver)
