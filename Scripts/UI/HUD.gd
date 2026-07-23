extends Control
# Player HUD chrome: health/hunger bars, AI toggle, message banner, crosshair.
# Instanced as Scenes/HUD.tscn under Player.tscn's "HUD" CanvasLayer (see
# node "PlayerHUD"). Player.gd binds PlayerStats.health_changed /
# hunger_changed to health_bar.value / hunger_bar.value directly, so this
# script only needs to expose those nodes and own their visual style --
# bright/chunky hypercasual, not the old dark "glass" look.

# ---- Bright hypercasual palette ----
const COL_PANEL_BG := Color(1.0, 0.97, 0.88, 0.95)
const COL_PANEL_BORDER := Color(0.16, 0.09, 0.04, 1.0)
const COL_HEALTH_FILL := Color(0.95, 0.18, 0.28)
const COL_HEALTH_BG := Color(0.35, 0.06, 0.09)
const COL_HUNGER_FILL := Color(1.0, 0.62, 0.06)
const COL_HUNGER_BG := Color(0.40, 0.22, 0.03)
const COL_AI_ON := Color(0.30, 0.80, 0.40)
const COL_AI_OFF := Color(0.30, 0.55, 0.95)
const COL_DEATH_TITLE := Color(0.95, 0.22, 0.24)
const COL_DEATH_SUBTITLE := Color(1, 1, 1, 0.9)
# Overlay's own alpha at full "in" -- kept < 1 so it's an unmistakable dim
# rather than a hard cut to black.
const DEATH_OVERLAY_ALPHA := 0.82

@onready var health_bar: ProgressBar = $StatsPanel/Margin/VBox/HealthRow/HealthBar
@onready var hunger_bar: ProgressBar = $StatsPanel/Margin/VBox/HungerRow/HungerBar
@onready var stats_panel: PanelContainer = $StatsPanel
@onready var ai_button: Button = $AIButton
@onready var settings_button: Button = $SettingsButton
@onready var message_label: Label = $MessageLabel
@onready var crosshair: Control = $Crosshair
@onready var death_overlay: ColorRect = $DeathOverlay
@onready var death_cause_label: Label = $DeathOverlay/VBox/CauseLabel
@onready var death_respawn_label: Label = $DeathOverlay/VBox/RespawnLabel

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_panel()
	_style_bar(health_bar, COL_HEALTH_BG, COL_HEALTH_FILL)
	_style_bar(hunger_bar, COL_HUNGER_BG, COL_HUNGER_FILL)
	_style_message_label()
	_style_settings_button()
	_style_death_overlay()
	ai_button.pressed.connect(_on_ai_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	update_ai_button(false)

func _style_panel() -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = COL_PANEL_BG
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(5)
	sb.border_color = COL_PANEL_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 3)
	stats_panel.add_theme_stylebox_override("panel", sb)

func _style_bar(bar: ProgressBar, bg: Color, fill: Color) -> void:
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = bg
	bg_style.set_corner_radius_all(14)
	bg_style.set_border_width_all(3)
	bg_style.border_color = COL_PANEL_BORDER

	# NOTE: rounding the fill's TRAILING (right) corners produced a visible
	# "bite"/notch out of the bar at partial values -- Godot draws the fill
	# stylebox clipped to exactly `width * ratio`, so a rounded right edge
	# exposes a crescent of background color mid-bar instead of a clean cut.
	# Only round the leading (left) corners, which always sit flush against
	# the bg's rounded left edge; the right edge stays a flat cut at any
	# fill ratio (the only place it'd show is a few px of the bg's own
	# rounded corner peeking out at exactly 100%, which is unnoticeable).
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = fill
	fill_style.corner_radius_top_left = 11
	fill_style.corner_radius_bottom_left = 11
	fill_style.corner_radius_top_right = 0
	fill_style.corner_radius_bottom_right = 0

	bar.add_theme_stylebox_override("background", bg_style)
	bar.add_theme_stylebox_override("fill", fill_style)
	bar.show_percentage = false
	bar.max_value = 100.0

func _style_message_label() -> void:
	message_label.add_theme_font_size_override("font_size", 20)
	message_label.add_theme_color_override("font_color", Color(1, 1, 1))
	message_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	message_label.add_theme_constant_override("outline_size", 5)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _on_ai_button_pressed() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("toggle_ai"):
		player.toggle_ai()

# Settings panel (Scenes/SettingsPanel.tscn) is a sibling under the same
# "HUD" CanvasLayer in Player.tscn, not a child of this node -- reached via
# its group rather than a hardcoded relative path, same lookup style
# HotbarUI.gd/AIButton already use for finding the player.
func _on_settings_button_pressed() -> void:
	var panel = get_tree().get_first_node_in_group("settings_panel")
	if panel and panel.has_method("toggle"):
		panel.toggle()

func _style_settings_button() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = COL_PANEL_BG
	style.set_corner_radius_all(16)
	style.set_border_width_all(4)
	style.border_color = COL_PANEL_BORDER
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	settings_button.add_theme_stylebox_override("normal", style)
	settings_button.add_theme_stylebox_override("hover", style)
	settings_button.add_theme_stylebox_override("pressed", style)
	settings_button.add_theme_stylebox_override("focus", style)
	settings_button.add_theme_font_size_override("font_size", 16)
	settings_button.add_theme_color_override("font_color", COL_PANEL_BORDER)
	settings_button.add_theme_color_override("font_hover_color", COL_PANEL_BORDER)
	settings_button.add_theme_color_override("font_pressed_color", COL_PANEL_BORDER)

func _style_death_overlay() -> void:
	death_cause_label.add_theme_font_size_override("font_size", 44)
	death_cause_label.add_theme_color_override("font_color", COL_DEATH_TITLE)
	death_cause_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02))
	death_cause_label.add_theme_constant_override("outline_size", 8)

	death_respawn_label.add_theme_font_size_override("font_size", 22)
	death_respawn_label.add_theme_color_override("font_color", COL_DEATH_SUBTITLE)
	death_respawn_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02))
	death_respawn_label.add_theme_constant_override("outline_size", 5)

## Clear death/respawn feedback (issue: player would respawn with no idea
## why). `reason` is the human-readable cause -- see Player.gd's
## DEATH_REASONS -- shown above a "Respawning..." line while the screen
## fades in, holds, then fades back out as the player reappears at spawn.
## Player.gd calls this the instant PlayerStats.died fires / a void-fall is
## caught, i.e. before the position teleport, so the fade-in reads as "you
## died here" rather than lagging behind the teleport.
const DEATH_FADE_TIME := 0.35
const DEATH_HOLD_TIME := 1.2

func show_death_screen(reason: String) -> void:
	death_cause_label.text = "ВЫ ПОГИБЛИ: " + reason
	death_respawn_label.text = "Возрождение..."
	death_overlay.visible = true
	death_overlay.color.a = 0.0

	var tween = create_tween()
	tween.tween_property(death_overlay, "color:a", DEATH_OVERLAY_ALPHA, DEATH_FADE_TIME)
	tween.tween_interval(DEATH_HOLD_TIME)
	tween.tween_property(death_overlay, "color:a", 0.0, DEATH_FADE_TIME)
	tween.tween_callback(func(): death_overlay.visible = false)

func update_ai_button(enabled: bool) -> void:
	if not ai_button:
		return
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(16)
	style.set_border_width_all(4)
	style.border_color = COL_PANEL_BORDER
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 3)
	if enabled:
		ai_button.text = "ИИ АКТИВЕН"
		style.bg_color = COL_AI_ON
	else:
		ai_button.text = "ВРУЧНУЮ"
		style.bg_color = COL_AI_OFF

	ai_button.add_theme_stylebox_override("normal", style)
	ai_button.add_theme_stylebox_override("hover", style)
	ai_button.add_theme_stylebox_override("pressed", style)
	ai_button.add_theme_stylebox_override("focus", style)
	ai_button.add_theme_font_size_override("font_size", 20)
	ai_button.add_theme_color_override("font_color", Color(1, 1, 1))
	ai_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	ai_button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
