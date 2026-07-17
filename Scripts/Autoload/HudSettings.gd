extends Node
# HudSettings -- persists + live-applies the player's chosen HUD size ("HUD
# Size" / "Размер интерфейса" slider in Scenes/SettingsPanel.tscn).
#
# Knob: get_tree().root.content_scale_factor (Godot 4's global GUI scale).
# Verified empirically (probe render, before/after frame comparison) that
# with content_scale_mode switched to CANVAS_ITEMS, content_scale_factor
# scales HUD Controls (they're laid out in "virtual" pixels relative to
# content_scale_size) while the 3D world's camera-driven framing is
# untouched -- block sizes/positions on screen are identical before/after,
# only the HUD panels/buttons/hotbar grow or shrink.
#
# This project's project.godot has NO [display] window/stretch section, so
# stretch mode defaults to DISABLED, under which content_scale_factor alone
# is a no-op -- content_scale_mode must be switched to CANVAS_ITEMS here
# too, once, at startup (and is re-applied defensively on every set_hud_scale
# call in case anything else ever touches it).

signal hud_scale_changed(value: float)

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "ui"
const KEY := "hud_scale"
const MIN_SCALE := 0.5
const MAX_SCALE := 2.0
const DEFAULT_SCALE := 1.0

var hud_scale: float = DEFAULT_SCALE

func _ready() -> void:
	hud_scale = _load_from_disk()
	_apply(hud_scale)

func set_hud_scale(value: float) -> void:
	value = clamp(value, MIN_SCALE, MAX_SCALE)
	if is_equal_approx(value, hud_scale):
		return
	hud_scale = value
	_apply(hud_scale)
	_save_to_disk(hud_scale)
	hud_scale_changed.emit(hud_scale)

func _apply(value: float) -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_factor = value

func _load_from_disk() -> float:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return DEFAULT_SCALE
	return clamp(float(cfg.get_value(SECTION, KEY, DEFAULT_SCALE)), MIN_SCALE, MAX_SCALE)

func _save_to_disk(value: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # best-effort merge -- keep any other future settings in the same file
	cfg.set_value(SECTION, KEY, value)
	cfg.save(SETTINGS_PATH)
