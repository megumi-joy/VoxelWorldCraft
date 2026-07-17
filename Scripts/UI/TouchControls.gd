extends CanvasLayer
## Touch controls overlay for phones/tablets: a virtual movement joystick
## (bottom-left), a look/drag area (right half of the screen), and action
## buttons (Jump / Mine / Place / Inventory). Wired directly onto the same
## Player.gd entry points keyboard+mouse use -- touch_move_vector,
## apply_look_delta(), touch_jump(), mock_left_click/mock_right_click, and a
## synthesized "inventory" action press -- so behavior is identical
## regardless of input method (see Scripts/Player/Player.gd).
##
## Ported from the private megumi-joy/MagicBallsAdventure repo ("Tiles"),
## per owner direction to reuse its touch implementation as a reference
## rather than inventing from scratch:
##   - scripts/virtual_joystick.gd: per-finger touch-index tracking + a
##     clamped [-1,1] output vector from touch-position-minus-center. Ported
##     near-verbatim (see _handle_touch/_update_move below).
##   - scripts/game_ui.gd's _input(): an event-type-sniffing auto-detection
##     watcher (InputEventKey/MouseButton -> desktop, InputEventScreenTouch/
##     Drag -> touch) that flips a mode and show()/hide()s the touch layer.
##     Ported as the _set_touch_mode/_input pattern below, with one addition
##     Tiles didn't need: an "emulate mouse from touch" debounce (see
##     EMULATION_GUARD_MS).
## This is a from-scratch dual-stick FPS-mobile layout, not a port of Tiles'
## own control scheme (a fixed-camera rolling-ball driving game, which uses
## a single joystick plus a second finger held anywhere for camera turn --
## a first-person voxel game needs an independent look-drag area instead).
## The joystick is a fixed bottom-left dock (grabbable from anywhere in
## MoveArea), not Tiles' "appears where you touch" dynamic positioning --
## a deliberate scope cut for this first pass, easy to add later if wanted.
##
## Auto-detection default: DisplayServer.is_touchscreen_available() decides
## the layer's visibility before any input has been seen. From then on:
## any InputEventKey / real InputEventMouseButton / InputEventMouseMotion
## switches to desktop mode (layer hidden, keyboard+mouse control the
## player); any InputEventScreenTouch / InputEventScreenDrag switches to
## touch mode (layer shown). Godot's "Emulate Mouse From Touch" project
## setting (default ON) fires a synthetic mouse event right after every
## real touch -- naively that would flip straight back to desktop mode one
## event later, on every tap, on a real phone. Mouse events arriving within
## EMULATION_GUARD_MS of the last real touch event are treated as that
## synthetic echo and ignored rather than as real desktop input.

const EMULATION_GUARD_MS := 150

# Matches Scripts/UI/HUD.gd's "bright hypercasual" palette (duplicated here
# rather than shared -- HUD.gd's constants aren't exposed via an autoload/
# resource. Keep in sync if that palette changes).
const COL_PANEL_BORDER := Color(0.16, 0.09, 0.04, 1.0)
const COL_JUMP := Color(0.30, 0.80, 0.40)      # matches HUD's AI-ON green
const COL_MINE := Color(0.95, 0.18, 0.28)      # matches HUD's health red
const COL_PLACE := Color(1.0, 0.62, 0.06)      # matches HUD's hunger amber
const COL_INVENTORY := Color(0.30, 0.55, 0.95) # matches HUD's AI-OFF blue

@export var touch_look_multiplier: float = 2.4

@onready var root: Control = $Root
@onready var move_area: Control = $Root/MoveArea
@onready var look_area: Control = $Root/LookArea
@onready var joystick: Control = $Root/Joystick
@onready var jump_button: Button = $Root/JumpButton
@onready var mine_button: Button = $Root/MineButton
@onready var place_button: Button = $Root/PlaceButton
@onready var inventory_button: Button = $Root/InventoryButton

var player: Node = null

var _touch_mode: bool = false
var _forced: bool = false
var _last_touch_ms: int = -999999

var _move_touch_index: int = -1
var _look_touch_index: int = -1

func _ready() -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	look_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_style_action_button(jump_button, "JUMP", COL_JUMP)
	_style_action_button(mine_button, "MINE", COL_MINE)
	_style_action_button(place_button, "PLACE", COL_PLACE)
	_style_action_button(inventory_button, "BAG", COL_INVENTORY)

	jump_button.button_down.connect(_on_jump_down)
	mine_button.button_down.connect(_on_mine_down)
	mine_button.button_up.connect(_on_mine_up)
	place_button.button_down.connect(_on_place_down)
	place_button.button_up.connect(_on_place_up)
	inventory_button.pressed.connect(_on_inventory_pressed)

	# Sensible default before any real input event has been seen: show on
	# devices that report a touchscreen, hidden otherwise (desktop-first).
	_touch_mode = DisplayServer.is_touchscreen_available()
	_apply_visibility()

	# --force-touch-ui (see Scripts/Testing/TouchControlsDemoDriver.gd and
	# Scripts/Tools/LaunchTest.gd): force the layer visible for headless
	# rendering/verification regardless of stray input events under Xvfb.
	if OS.get_cmdline_user_args().has("--force-touch-ui"):
		force_touch_mode(true)

	_find_player()

func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if not player:
		await get_tree().create_timer(0.1).timeout
		_find_player()

## Public override for the headless render driver (and available later for
## an in-game "Touch Controls" settings toggle): forces the layer visible
## and freezes it there, ignoring the live auto-detection watcher below
## until called again with false.
func force_touch_mode(enabled: bool) -> void:
	_forced = enabled
	if enabled:
		_touch_mode = true
	_apply_visibility()

func _apply_visibility() -> void:
	visible = _forced or _touch_mode
	if not visible:
		_reset_move_touch()
		_reset_look_touch()

func _set_touch_mode(is_touch: bool) -> void:
	if _forced or _touch_mode == is_touch:
		return
	_touch_mode = is_touch
	_apply_visibility()

# ---- Input-mode auto-detection: runs on every event (including ones a
# Button's GUI handling consumes first -- a button tap is still "touch"). ----
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_last_touch_ms = Time.get_ticks_msec()
		_set_touch_mode(true)
	elif event is InputEventKey:
		if event.pressed:
			_set_touch_mode(false)
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		if Time.get_ticks_msec() - _last_touch_ms < EMULATION_GUARD_MS:
			return # synthetic "emulate mouse from touch" echo, not real desktop input
		_set_touch_mode(false)

# ---- Joystick + look-drag. Handled in _unhandled_input (not _input) so a
# tap that lands on one of the action buttons below is consumed by that
# Button's own GUI input first and never also starts a joystick/look drag
# (Buttons default to MOUSE_FILTER_STOP; MoveArea/LookArea/Joystick above
# are MOUSE_FILTER_IGNORE so they never intercept it either -- taps reach
# here only where there is no button under the finger). Gated on `visible`
# so a stray event can't drive the player while the layer is hidden. ----
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Each control claims exactly one finger by event.index on first
		# touch and only reacts to drags matching that same index below --
		# otherwise dragging the joystick would also rotate the camera.
		if _move_touch_index == -1 and move_area.get_global_rect().has_point(event.position):
			_move_touch_index = event.index
			_update_move(event.position)
		elif _look_touch_index == -1 and look_area.get_global_rect().has_point(event.position):
			_look_touch_index = event.index
	else:
		if event.index == _move_touch_index:
			_reset_move_touch()
		elif event.index == _look_touch_index:
			_reset_look_touch()

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _move_touch_index:
		_update_move(event.position)
	elif event.index == _look_touch_index:
		if player and player.has_method("apply_look_delta"):
			player.apply_look_delta(event.relative * touch_look_multiplier)

func _update_move(pos: Vector2) -> void:
	var center: Vector2 = joystick.get_global_rect().get_center()
	var radius: float = joystick.size.x / 2.0
	var vec: Vector2 = pos - center
	if vec.length() > radius:
		vec = vec.normalized() * radius
	var output: Vector2 = vec / radius if radius > 0.0 else Vector2.ZERO
	joystick.set_knob_offset(output, true)
	if player:
		# Player.gd's input_dir is (x=strafe, y=forward/back) via
		# Input.get_vector(left, right, forward, backward) -- the
		# joystick's clamped output already matches that axis convention.
		player.touch_move_vector = output

func _reset_move_touch() -> void:
	_move_touch_index = -1
	if joystick:
		joystick.set_knob_offset(Vector2.ZERO, false)
	if player:
		player.touch_move_vector = Vector2.ZERO

func _reset_look_touch() -> void:
	_look_touch_index = -1

# ---- Action buttons: wired to the exact same Player.gd entry points
# keyboard/mouse use -- mock_left_click/mock_right_click (mining/placing;
# these already existed for AI/bot testing), touch_jump() (mirrors a real
# "jump" action press, coyote-time/jump-buffer intact), and a synthesized
# "inventory" InputEventAction (mirrors a real E keypress, including
# InventoryUI.gd's own _input() handler that toggles it open/closed). ----
func _on_jump_down() -> void:
	if player and player.has_method("touch_jump"):
		player.touch_jump()

func _on_mine_down() -> void:
	if player:
		player.mock_left_click = true

func _on_mine_up() -> void:
	if player:
		player.mock_left_click = false

func _on_place_down() -> void:
	if player:
		player.mock_right_click = true

func _on_place_up() -> void:
	if player:
		player.mock_right_click = false

func _on_inventory_pressed() -> void:
	var ev := InputEventAction.new()
	ev.action = "inventory"
	ev.pressed = true
	Input.parse_input_event(ev)

func _style_action_button(btn: Button, label_text: String, bg: Color) -> void:
	btn.text = label_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal", _make_button_style(bg, 1.0))
	btn.add_theme_stylebox_override("hover", _make_button_style(bg, 1.0))
	btn.add_theme_stylebox_override("pressed", _make_button_style(bg, 0.72))
	btn.add_theme_stylebox_override("focus", _make_button_style(bg, 1.0))
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1))

func _make_button_style(bg: Color, brightness: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(bg.r * brightness, bg.g * brightness, bg.b * brightness, bg.a)
	sb.set_corner_radius_all(999) # square Button + huge radius -> chunky circle
	sb.set_border_width_all(5)
	sb.border_color = COL_PANEL_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	return sb
