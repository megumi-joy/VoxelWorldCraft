extends SceneTree
## Standalone headless self-test for Scripts/UI/TouchControls.gd's
## input-mode auto-detection watcher (_input() in that file) -- exercises
## the show/hide toggle logic directly via synthesized input events, with
## no Xvfb/rendering needed (unlike the screenshot/clip drivers, which
## prove the layer *looks* right; this proves the *switching logic* is
## right). Run with:
##
##   godot --headless --path . --script res://Scripts/Testing/TouchModeSelfTest.gd
##
## Exits 0 if every check passes, 1 otherwise (so it's CI-friendly).

func _initialize() -> void:
	print("[SelfTest] starting touch-mode auto-detection self-test")
	var tc = load("res://Scenes/TouchControls.tscn").instantiate()
	root.add_child(tc)
	await process_frame
	await process_frame

	var results: Array = []

	# 1. Headless CI reports no touchscreen -> should default hidden.
	results.append(["initial default hidden (no touchscreen in CI)", tc.visible == false])

	# 2. A real touch event shows the layer.
	_send_touch(true)
	await process_frame
	results.append(["screen touch -> layer shown", tc.visible == true])

	# 3. A real keyboard event hides it again.
	_send_key()
	await process_frame
	results.append(["key press -> layer hidden", tc.visible == false])

	# 4. Touch shows it again (sanity: the toggle isn't one-directional).
	_send_touch(true)
	await process_frame
	results.append(["screen touch -> layer shown again", tc.visible == true])

	# 5. Godot's "Emulate Mouse From Touch" fires a synthetic MouseButton
	# right after a real touch -- that must NOT be treated as desktop input
	# and hide the layer (the exact bug this project would ship with on a
	# real phone if the emulation guard were missing/broken).
	_send_mouse_button()
	await process_frame
	results.append(["mouse event inside emulation-guard window ignored", tc.visible == true])

	# 6. Once the guard window has actually elapsed, a mouse event again is
	# real desktop input and DOES hide the layer.
	await create_timer(0.25).timeout
	_send_mouse_button()
	await process_frame
	results.append(["mouse event after guard window -> layer hidden", tc.visible == false])

	# 7. force_touch_mode() (used by TouchControlsDemoDriver.gd for the
	# screenshot/clip) freezes the layer visible and ignores live detection
	# until released.
	tc.force_touch_mode(true)
	_send_key()
	await process_frame
	results.append(["force_touch_mode(true) ignores a key press", tc.visible == true])
	tc.force_touch_mode(false)
	_send_key()
	await process_frame
	results.append(["force_touch_mode(false) restores live detection", tc.visible == false])

	# 8. The BAG button doesn't call InventoryUI directly -- it synthesizes
	# an "inventory" InputEventAction via Input.parse_input_event() (see
	# TouchControls._on_inventory_pressed()), banking on that reaching any
	# node watching event.is_action_pressed("inventory") the same way a
	# real E keypress would (InventoryUI.gd's own _input()). Verify that
	# link actually fires, not just that the code compiles.
	if not InputMap.has_action("inventory"):
		InputMap.add_action("inventory")
	var probe := InventoryActionProbe.new()
	root.add_child(probe)
	await process_frame
	tc._on_inventory_pressed()
	await process_frame
	results.append(["BAG button's synthesized action reaches a real listener", probe.fired])
	probe.queue_free()

	var all_pass := true
	for r in results:
		var ok: bool = r[1]
		if not ok:
			all_pass = false
		print("[SelfTest] ", ("PASS" if ok else "FAIL"), " - ", r[0])

	print("[SelfTest] RESULT: ", ("ALL PASS" if all_pass else "SOME FAILED"))
	quit(0 if all_pass else 1)

func _send_touch(pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = pressed
	ev.position = Vector2(100, 400)
	Input.parse_input_event(ev)

func _send_key() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)

func _send_mouse_button() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(500, 400)
	Input.parse_input_event(ev)

# Minimal stand-in for InventoryUI.gd's own `_input(event): if
# event.is_action_pressed("inventory"): ...` handler -- proves a
# synthesized InputEventAction sent via Input.parse_input_event() actually
# reaches a listener's _input(), the same path the real InventoryUI uses.
class InventoryActionProbe:
	extends Node
	var fired: bool = false
	func _ready() -> void:
		set_process_input(true)
	func _input(event: InputEvent) -> void:
		if event.is_action_pressed("inventory"):
			fired = true
