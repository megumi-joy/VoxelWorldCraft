extends CanvasLayer
# Escape pause menu -- global autoload (see project.godot [autoload]) so it
# exists in every scene tree without per-scene wiring. Player.gd's Esc
# handling (_unhandled_input, "ui_cancel") calls toggle() below instead of
# directly flipping mouse capture, but ONLY when no other HUD panel
# (Inventory/Crafting/Furnace/...) already owns Escape's older
# release-mouse behavior -- see Player.gd's _is_menu_open() gate at that call
# site. That keeps this feature additive: normal gameplay Escape now opens
# this pause menu, while Escape inside an already-open panel behaves exactly
# as it did before this feature existed.
#
# process_mode = PROCESS_MODE_ALWAYS (root CanvasLayer) so the Продолжить/
# Выход buttons -- and this node's own Escape-to-resume shortcut below --
# keep working while get_tree().paused is true; children default to
# PROCESS_MODE_INHERIT, which resolves to ALWAYS through this parent.

var _panel: Panel
var _paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build_ui()
	visible = false

func _build_ui() -> void:
	_panel = Panel.new()
	_panel.name = "PausePanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop_style := StyleBoxFlat.new()
	backdrop_style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	_panel.add_theme_stylebox_override("panel", backdrop_style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(260, 0)
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)

	var resume_btn := Button.new()
	resume_btn.name = "ResumeButton"
	resume_btn.text = "Продолжить"
	resume_btn.custom_minimum_size = Vector2(220, 44)
	resume_btn.pressed.connect(resume)
	box.add_child(resume_btn)

	var quit_btn := Button.new()
	quit_btn.name = "QuitButton"
	quit_btn.text = "Выход"
	quit_btn.custom_minimum_size = Vector2(220, 44)
	quit_btn.pressed.connect(_on_quit_pressed)
	box.add_child(quit_btn)

## Escape-to-resume while paused. Guarded on _paused so this never fires the
## initial open -- that's owned by Player.gd's ui_cancel branch, which only
## reaches PauseMenu.toggle() when this menu (and no other HUD panel) is
## the thing Escape should affect. While paused, Player.gd itself stops
## receiving _unhandled_input (its process_mode is the default PAUSABLE), so
## there is no double-toggle risk between the two.
func _unhandled_input(event: InputEvent) -> void:
	if _paused and event.is_action_pressed("ui_cancel"):
		resume()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if _paused:
		resume()
	else:
		pause_game()

func pause_game() -> void:
	_paused = true
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func resume() -> void:
	_paused = false
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_quit_pressed() -> void:
	get_tree().quit()
