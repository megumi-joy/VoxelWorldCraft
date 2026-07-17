extends Control
# In-game Settings panel: "HUD Size" slider (live GUI scale, see
# Scripts/Autoload/HudSettings.gd) plus a "GRAPHICS QUALITY" section (live
# rendering toggles, see Scripts/Autoload/GraphicsSettings.gd), styled to
# match HUD.gd's bright/chunky hypercasual palette. Reached via a gear
# button on the main HUD overlay (Scenes/HUD.tscn -> SettingsButton), which
# finds this panel through the "settings_panel" group rather than a
# hardcoded node path, since the two are siblings under Player.tscn's "HUD"
# CanvasLayer and neither needs to know the other's exact tree position.
#
# The graphics rows (preset dropdown, SDFGI/SSR/SSAO/SSIL/glow toggles,
# shadow quality, antialiasing, view distance) are built in code inside
# GraphicsSection (an empty VBoxContainer authored in the .tscn) rather than
# hand-authored as ~10 extra .tscn nodes -- fewer .tscn nodes = smaller
# merge surface with other in-flight settings-panel work on this shared
# scene/script pair.

const COL_PANEL_BG := Color(1.0, 0.97, 0.88, 0.97)
const COL_PANEL_BORDER := Color(0.16, 0.09, 0.04, 1.0)
const COL_TEXT := Color(0.16, 0.09, 0.04, 1.0)
const COL_ACCENT := Color(1.0, 0.75, 0.05, 1.0)
const COL_TRACK_BG := Color(0.85, 0.78, 0.6, 1.0)
const COL_CLOSE_BG := Color(0.95, 0.35, 0.28, 1.0)

@onready var dim_background: ColorRect = $DimBackground
@onready var panel_box: PanelContainer = $DimBackground/PanelBox
@onready var title_label: Label = $DimBackground/PanelBox/Margin/VBox/TitleLabel
@onready var content_vbox: VBoxContainer = $DimBackground/PanelBox/Margin/VBox/ScrollContainer/ContentVBox
@onready var hud_size_label: Label = $DimBackground/PanelBox/Margin/VBox/ScrollContainer/ContentVBox/HudSizeRow/HudSizeLabel
@onready var value_label: Label = $DimBackground/PanelBox/Margin/VBox/ScrollContainer/ContentVBox/HudSizeRow/ValueLabel
@onready var slider: HSlider = $DimBackground/PanelBox/Margin/VBox/ScrollContainer/ContentVBox/Slider
@onready var graphics_title_label: Label = $DimBackground/PanelBox/Margin/VBox/ScrollContainer/ContentVBox/GraphicsTitleLabel
@onready var graphics_section: VBoxContainer = $DimBackground/PanelBox/Margin/VBox/ScrollContainer/ContentVBox/GraphicsSection
@onready var close_button: Button = $DimBackground/PanelBox/Margin/VBox/CloseButton

# Graphics row widgets, kept as members so _refresh_graphics_controls() can
# re-sync them (e.g. after a preset applies, or when the panel re-opens).
var _preset_dropdown: OptionButton
var _sdfgi_check: CheckBox
var _sdfgi_quality_dropdown: OptionButton
var _ssr_check: CheckBox
var _ssao_check: CheckBox
var _ssil_check: CheckBox
var _glow_check: CheckBox
var _shadow_dropdown: OptionButton
var _aa_dropdown: OptionButton
var _view_distance_slider: HSlider
var _view_distance_value_label: Label

# Guard: true while a programmatic widget.value/.selected/.button_pressed
# assignment is in flight, so the resulting signal doesn't re-enter
# GraphicsSettings.set_*() (harmless if it did -- idempotent -- but this
# avoids redundant disk saves every refresh).
var _syncing := false

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

	_build_graphics_section()
	_style()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	slider.value = HudSettings.hud_scale
	_update_value_label(HudSettings.hud_scale)
	_refresh_graphics_controls()
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

# ---- Graphics section ----

func _build_graphics_section() -> void:
	graphics_title_label.add_theme_font_size_override("font_size", 20)
	graphics_title_label.add_theme_color_override("font_color", COL_TEXT)

	var preset_row := _add_row("Quality Preset")
	_preset_dropdown = _add_dropdown(preset_row, GraphicsSettings.PRESET_NAMES, GraphicsSettings.preset)
	_preset_dropdown.item_selected.connect(_on_preset_selected)

	var sdfgi_row := _add_row("Global Illumination (SDFGI)")
	_sdfgi_check = _add_checkbox(sdfgi_row, GraphicsSettings.sdfgi_enabled)
	_sdfgi_check.toggled.connect(_on_sdfgi_toggled)

	var sdfgi_quality_row := _add_row("  GI Quality")
	_sdfgi_quality_dropdown = _add_dropdown(sdfgi_quality_row, GraphicsSettings.SDFGI_QUALITY_NAMES, GraphicsSettings.sdfgi_quality)
	_sdfgi_quality_dropdown.item_selected.connect(_on_sdfgi_quality_selected)

	var ssr_row := _add_row("Reflections (SSR)")
	_ssr_check = _add_checkbox(ssr_row, GraphicsSettings.ssr_enabled)
	_ssr_check.toggled.connect(_on_ssr_toggled)

	var ssao_row := _add_row("Ambient Occlusion (SSAO)")
	_ssao_check = _add_checkbox(ssao_row, GraphicsSettings.ssao_enabled)
	_ssao_check.toggled.connect(_on_ssao_toggled)

	var ssil_row := _add_row("Indirect Light (SSIL)")
	_ssil_check = _add_checkbox(ssil_row, GraphicsSettings.ssil_enabled)
	_ssil_check.toggled.connect(_on_ssil_toggled)

	var glow_row := _add_row("Glow / Bloom")
	_glow_check = _add_checkbox(glow_row, GraphicsSettings.glow_enabled)
	_glow_check.toggled.connect(_on_glow_toggled)

	var shadow_row := _add_row("Shadow Quality")
	_shadow_dropdown = _add_dropdown(shadow_row, GraphicsSettings.SHADOW_QUALITY_NAMES, GraphicsSettings.shadow_quality)
	_shadow_dropdown.item_selected.connect(_on_shadow_quality_selected)

	var aa_row := _add_row("Antialiasing")
	_aa_dropdown = _add_dropdown(aa_row, GraphicsSettings.AA_MODE_NAMES, GraphicsSettings.aa_mode)
	_aa_dropdown.item_selected.connect(_on_aa_mode_selected)

	var view_dist_row := _add_row("View Distance")
	_view_distance_slider = HSlider.new()
	_view_distance_slider.custom_minimum_size = Vector2(140, 28)
	_view_distance_slider.min_value = GraphicsSettings.VIEW_DISTANCE_MIN
	_view_distance_slider.max_value = GraphicsSettings.VIEW_DISTANCE_MAX
	_view_distance_slider.step = 1
	_view_distance_slider.value = GraphicsSettings.view_distance
	_view_distance_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_slider(_view_distance_slider)
	view_dist_row.add_child(_view_distance_slider)
	_view_distance_value_label = Label.new()
	_view_distance_value_label.custom_minimum_size = Vector2(70, 0)
	_view_distance_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_view_distance_value_label.add_theme_color_override("font_color", COL_ACCENT)
	view_dist_row.add_child(_view_distance_value_label)
	_view_distance_slider.value_changed.connect(_on_view_distance_changed)

	_refresh_graphics_controls()

func _add_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", COL_TEXT)
	row.add_child(label)
	graphics_section.add_child(row)
	return row

func _add_checkbox(row: HBoxContainer, initial: bool) -> CheckBox:
	var cb := CheckBox.new()
	cb.button_pressed = initial
	cb.add_theme_color_override("font_color", COL_TEXT)
	cb.add_theme_color_override("font_hover_color", COL_TEXT)
	cb.add_theme_color_override("font_pressed_color", COL_TEXT)
	row.add_child(cb)
	return cb

func _add_dropdown(row: HBoxContainer, options: Array, initial_index: int) -> OptionButton:
	var ob := OptionButton.new()
	for o in options:
		ob.add_item(o)
	ob.selected = initial_index
	ob.custom_minimum_size = Vector2(150, 0)
	_style_option_button(ob)
	row.add_child(ob)
	return ob

# Re-syncs every graphics widget from GraphicsSettings' current field values
# without re-triggering the setters (guarded by _syncing). Called after
# building the section, on panel open(), and after a preset applies.
func _refresh_graphics_controls() -> void:
	_syncing = true
	_preset_dropdown.selected = GraphicsSettings.preset
	_sdfgi_check.button_pressed = GraphicsSettings.sdfgi_enabled
	_sdfgi_quality_dropdown.selected = GraphicsSettings.sdfgi_quality
	_sdfgi_quality_dropdown.disabled = not GraphicsSettings.sdfgi_enabled
	_ssr_check.button_pressed = GraphicsSettings.ssr_enabled
	_ssao_check.button_pressed = GraphicsSettings.ssao_enabled
	_ssil_check.button_pressed = GraphicsSettings.ssil_enabled
	_glow_check.button_pressed = GraphicsSettings.glow_enabled
	_shadow_dropdown.selected = GraphicsSettings.shadow_quality
	_aa_dropdown.selected = GraphicsSettings.aa_mode
	_view_distance_slider.value = GraphicsSettings.view_distance
	_view_distance_value_label.text = "%d chunks" % GraphicsSettings.view_distance
	_syncing = false

func _on_preset_selected(index: int) -> void:
	if _syncing:
		return
	GraphicsSettings.apply_preset(index)
	_refresh_graphics_controls()

func _on_sdfgi_toggled(pressed: bool) -> void:
	if _syncing:
		return
	GraphicsSettings.set_sdfgi_enabled(pressed)
	_refresh_graphics_controls()

func _on_sdfgi_quality_selected(index: int) -> void:
	if _syncing:
		return
	GraphicsSettings.set_sdfgi_quality(index)
	_refresh_graphics_controls()

func _on_ssr_toggled(pressed: bool) -> void:
	if _syncing:
		return
	GraphicsSettings.set_ssr_enabled(pressed)
	_refresh_graphics_controls()

func _on_ssao_toggled(pressed: bool) -> void:
	if _syncing:
		return
	GraphicsSettings.set_ssao_enabled(pressed)
	_refresh_graphics_controls()

func _on_ssil_toggled(pressed: bool) -> void:
	if _syncing:
		return
	GraphicsSettings.set_ssil_enabled(pressed)
	_refresh_graphics_controls()

func _on_glow_toggled(pressed: bool) -> void:
	if _syncing:
		return
	GraphicsSettings.set_glow_enabled(pressed)
	_refresh_graphics_controls()

func _on_shadow_quality_selected(index: int) -> void:
	if _syncing:
		return
	GraphicsSettings.set_shadow_quality(index)
	_refresh_graphics_controls()

func _on_aa_mode_selected(index: int) -> void:
	if _syncing:
		return
	GraphicsSettings.set_aa_mode(index)
	_refresh_graphics_controls()

func _on_view_distance_changed(value: float) -> void:
	if _syncing:
		return
	GraphicsSettings.set_view_distance(int(round(value)))
	_refresh_graphics_controls()

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

	_style_slider(slider)

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

# Shared chunky track/fill/grabber styling, used by both the HUD-size slider
# and the graphics section's View Distance slider.
func _style_slider(s: HSlider) -> void:
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = COL_TRACK_BG
	track_style.set_corner_radius_all(10)
	track_style.set_border_width_all(3)
	track_style.border_color = COL_PANEL_BORDER
	track_style.content_margin_top = 6
	track_style.content_margin_bottom = 6
	s.add_theme_stylebox_override("slider", track_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COL_ACCENT
	fill_style.set_corner_radius_all(10)
	fill_style.content_margin_top = 6
	fill_style.content_margin_bottom = 6
	s.add_theme_stylebox_override("grabber_area", fill_style)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_style)

	var grabber_icon := _make_grabber_icon()
	s.add_theme_icon_override("grabber", grabber_icon)
	s.add_theme_icon_override("grabber_highlight", grabber_icon)
	s.add_theme_constant_override("grabber_offset", 0)

func _style_option_button(ob: OptionButton) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = COL_TRACK_BG
	box.set_corner_radius_all(8)
	box.set_border_width_all(2)
	box.border_color = COL_PANEL_BORDER
	box.content_margin_left = 10
	box.content_margin_right = 6
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	ob.add_theme_stylebox_override("normal", box)
	ob.add_theme_stylebox_override("hover", box)
	ob.add_theme_stylebox_override("pressed", box)
	ob.add_theme_stylebox_override("focus", box)
	ob.add_theme_stylebox_override("disabled", box)
	ob.add_theme_color_override("font_color", COL_TEXT)
	ob.add_theme_color_override("font_hover_color", COL_TEXT)
	ob.add_theme_color_override("font_pressed_color", COL_TEXT)
	ob.add_theme_color_override("font_disabled_color", COL_TEXT.lerp(COL_TRACK_BG, 0.6))

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
