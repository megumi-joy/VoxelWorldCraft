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
# Настройки/Выход buttons -- and this node's own Escape-to-resume shortcut
# below -- keep working while get_tree().paused is true; children default to
# PROCESS_MODE_INHERIT, which resolves to ALWAYS through this parent.

var _panel: Panel
var _box: PanelContainer
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
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Dims/hides the 3D world behind the menu -- deliberately dark enough that
	# the world reads as "obscured", not the half-see-through look the owner
	# flagged on the other HUD panels. The button box below has its own fully
	# opaque background on top of this.
	var backdrop_style := StyleBoxFlat.new()
	backdrop_style.bg_color = Color(0.02, 0.02, 0.03, 0.85)
	_panel.add_theme_stylebox_override("panel", backdrop_style)
	add_child(_panel)

	_box = PanelContainer.new()
	_box.name = "Box"
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.custom_minimum_size = Vector2(300, 0)
	var box_style := StyleBoxFlat.new()
	# Fully opaque dark panel with a light border -- Minecraft-style solid
	# menu chrome (owner ask: no see-through panels).
	box_style.bg_color = Color(0.09, 0.09, 0.1, 1.0)
	box_style.border_color = Color(0.85, 0.72, 0.35, 1.0)
	box_style.set_border_width_all(3)
	box_style.set_corner_radius_all(6)
	box_style.set_content_margin_all(20)
	_box.add_theme_stylebox_override("panel", box_style)
	_panel.add_child(_box)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 16)
	_box.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.name = "ResumeButton"
	resume_btn.text = "Продолжить"
	resume_btn.custom_minimum_size = Vector2(240, 48)
	resume_btn.add_theme_font_size_override("font_size", 20)
	resume_btn.pressed.connect(resume)
	vbox.add_child(resume_btn)

	var settings_btn := Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = "Настройки"
	settings_btn.custom_minimum_size = Vector2(240, 48)
	settings_btn.add_theme_font_size_override("font_size", 20)
	settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_btn)

	var quit_btn := Button.new()
	quit_btn.name = "QuitButton"
	quit_btn.text = "Выход"
	quit_btn.custom_minimum_size = Vector2(240, 48)
	quit_btn.add_theme_font_size_override("font_size", 20)
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)

## Escape-to-resume while paused (and Escape-to-close-Settings-first if the
## Settings panel is the thing currently on top -- see _on_settings_pressed()
## below). Guarded on _paused so this never fires the initial open -- that's
## owned by Player.gd's ui_cancel branch, which only reaches PauseMenu.toggle()
## when this menu (and no other HUD panel) is the thing Escape should affect.
## While paused, Player.gd itself stops receiving _unhandled_input (its
## process_mode is the default PAUSABLE), so there is no double-toggle risk
## between the two.
func _unhandled_input(event: InputEvent) -> void:
	if _paused and event.is_action_pressed("ui_cancel"):
		var settings = get_tree().get_first_node_in_group("settings_panel")
		if settings and settings.visible:
			# Let SettingsPanel's own Escape-to-close handler (it also listens
			# for ui_cancel) close it first -- resuming the whole game out
			# from under an open Settings panel would leave it stranded open
			# on top of a running (unpaused) world.
			return
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

## Настройки from the pause menu: reuses the same SettingsPanel every other
## entry point (HUD gear button / MainMenu) uses, found via its
## "settings_panel" group rather than a hardcoded path (SettingsPanel.gd adds
## itself to that group in its own _ready()). Hides this menu's own panel
## behind it (game stays paused the whole time) and restores it once
## Settings closes.
func _on_settings_pressed() -> void:
	var settings = get_tree().get_first_node_in_group("settings_panel")
	if not settings:
		return
	# Control nodes default to PROCESS_MODE_INHERIT, which would resolve
	# through the Player/HUD tree (PAUSABLE) and freeze every slider/button
	# the instant get_tree().paused is true -- same reasoning as this
	# CanvasLayer's own PROCESS_MODE_ALWAYS above. Explicit on the panel
	# itself, so it works regardless of its actual parent's mode.
	settings.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
	settings.open()
	if not settings.visibility_changed.is_connected(_on_settings_closed):
		settings.visibility_changed.connect(_on_settings_closed, CONNECT_ONE_SHOT)

func _on_settings_closed() -> void:
	if not _paused:
		return
	_panel.visible = true
	# SettingsPanel.close() re-captures the mouse whenever a Player exists in
	# the scene (correct behavior for normal play) -- wrong here since the
	# pause menu is still up underneath it, so reassert VISIBLE.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
