extends Control
# In-game Settings panel: currently just the "HUD Size" slider (live GUI
# scale, see Scripts/Autoload/HudSettings.gd), styled to match HUD.gd's
# bright/chunky hypercasual palette. Reached via a gear button on the main
# HUD overlay (Scenes/HUD.tscn -> SettingsButton), which finds this panel
# through the "settings_panel" group rather than a hardcoded node path,
# since the two are siblings under Player.tscn's "HUD" CanvasLayer and
# neither needs to know the other's exact tree position.

const COL_PANEL_BG := Color(1.0, 0.97, 0.88, 0.97)
const COL_PANEL_BORDER := Color(0.16, 0.09, 0.04, 1.0)
const COL_TEXT := Color(0.16, 0.09, 0.04, 1.0)
const COL_ACCENT := Color(1.0, 0.75, 0.05, 1.0)
const COL_TRACK_BG := Color(0.85, 0.78, 0.6, 1.0)
const COL_CLOSE_BG := Color(0.95, 0.35, 0.28, 1.0)

@onready var dim_background: ColorRect = $DimBackground
@onready var panel_box: PanelContainer = $DimBackground/PanelBox
@onready var title_label: Label = $DimBackground/PanelBox/Margin/VBox/TitleLabel
@onready var hud_size_label: Label = $DimBackground/PanelBox/Margin/VBox/HudSizeRow/HudSizeLabel
@onready var value_label: Label = $DimBackground/PanelBox/Margin/VBox/HudSizeRow/ValueLabel
@onready var slider: HSlider = $DimBackground/PanelBox/Margin/VBox/Slider
@onready var close_button: Button = $DimBackground/PanelBox/Margin/VBox/CloseButton

func _ready() -> void:
	add_to_group("settings_panel")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	slider.min_value = HudSettings.MIN_SCALE
	slider.max_value = HudSettings.MAX_SCALE
	slider.step = 0.05
	slider.value = HudSettings.hud_scale
	_update_value_label(HudSettings.hud_scale)

	slider.value_changed.connect(_on_slider_changed)
	close_button.pressed.connect(_on_close_pressed)

	_style()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	slider.value = HudSettings.hud_scale
	_update_value_label(HudSettings.hud_scale)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _on_slider_changed(value: float) -> void:
	HudSettings.set_hud_scale(value)
	_update_value_label(value)

func _on_close_pressed() -> void:
	close()

func _update_value_label(value: float) -> void:
	value_label.text = "%d%%" % int(round(value * 100.0))

func _style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COL_PANEL_BG
	panel_style.set_corner_radius_all(20)
	panel_style.set_border_width_all(5)
	panel_style.border_color = COL_PANEL_BORDER
	panel_style.shadow_color = Color(0, 0, 0, 0.4)
	panel_style.shadow_size = 8
	panel_style.shadow_offset = Vector2(0, 5)
	panel_box.add_theme_stylebox_override("panel", panel_style)

	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", COL_TEXT)

	hud_size_label.add_theme_font_size_override("font_size", 20)
	hud_size_label.add_theme_color_override("font_color", COL_TEXT)

	value_label.add_theme_font_size_override("font_size", 20)
	value_label.add_theme_color_override("font_color", COL_ACCENT)

	var track_style := StyleBoxFlat.new()
	track_style.bg_color = COL_TRACK_BG
	track_style.set_corner_radius_all(10)
	track_style.set_border_width_all(3)
	track_style.border_color = COL_PANEL_BORDER
	track_style.content_margin_top = 6
	track_style.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", track_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COL_ACCENT
	fill_style.set_corner_radius_all(10)
	fill_style.content_margin_top = 6
	fill_style.content_margin_bottom = 6
	slider.add_theme_stylebox_override("grabber_area", fill_style)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_style)

	var grabber_icon := _make_grabber_icon()
	slider.add_theme_icon_override("grabber", grabber_icon)
	slider.add_theme_icon_override("grabber_highlight", grabber_icon)
	slider.add_theme_constant_override("grabber_offset", 0)

	var close_style := StyleBoxFlat.new()
	close_style.bg_color = COL_CLOSE_BG
	close_style.set_corner_radius_all(16)
	close_style.set_border_width_all(4)
	close_style.border_color = COL_PANEL_BORDER
	close_style.shadow_color = Color(0, 0, 0, 0.3)
	close_style.shadow_size = 5
	close_style.shadow_offset = Vector2(0, 3)
	close_button.add_theme_stylebox_override("normal", close_style)
	close_button.add_theme_stylebox_override("hover", close_style)
	close_button.add_theme_stylebox_override("pressed", close_style)
	close_button.add_theme_stylebox_override("focus", close_style)
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.add_theme_color_override("font_color", Color(1, 1, 1))
	close_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	close_button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))

# Chunky round grabber knob drawn as a small flat-colored ImageTexture (no
# image assets in the project -- same "flat swatch" approach HotbarUI.gd
# uses for item icons) rather than the default theme's thin default grabber.
func _make_grabber_icon() -> ImageTexture:
	var size := 28
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0 - 1.0
	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= radius:
				img.set_pixel(x, y, COL_PANEL_BG)
			elif d <= radius + 1.5:
				img.set_pixel(x, y, COL_PANEL_BORDER)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
