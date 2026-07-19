extends CanvasLayer
# Sound-subtitle captions (accessibility): a brief on-screen line whenever a
# gameplay "sound" fires -- "[Шаги]" on footsteps, "[Копание]" on a block
# break, "[Стук]" on a block place, "[Урон]" on taking damage, "[Смерть]" on
# death.
#
# NOTE: this project has no audio system at all yet -- zero
# AudioStreamPlayer nodes and zero sound assets anywhere in the repo (see
# TextureGenerator.gd/etc.; nothing plays audio today). Per the task spec's
# own fallback ("if there's a central audio play point, hook there;
# otherwise caption the main gameplay sounds"), this captions the *moments*
# a sound would play rather than an actual mixed sound -- it's both the
# accessibility feature on its own, and it marks exactly the call sites a
# real SFX system should hook into later (Player.gd / PlayerStats.gd).
#
# Global autoload (own top-level CanvasLayer), same reasoning as
# ActionLog.gd -- survives scene changes, no per-scene wiring needed.

const MAX_LINES := 3
const LIFETIME := 1.6
const FADE_TIME := 0.4

var _vbox: VBoxContainer

func _ready() -> void:
	layer = 21 # above ActionLog (20) and the default HUD CanvasLayer (0)

	var anchor := Control.new()
	anchor.name = "Anchor"
	anchor.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor.offset_left = -160.0
	anchor.offset_right = 160.0
	anchor.offset_top = -150.0
	anchor.offset_bottom = -104.0 # sits just above HotbarUI.tscn
	anchor.grow_horizontal = Control.GROW_DIRECTION_BOTH
	anchor.grow_vertical = Control.GROW_DIRECTION_BEGIN
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_vbox = VBoxContainer.new()
	_vbox.name = "VBox"
	_vbox.alignment = BoxContainer.ALIGNMENT_END
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override("separation", 2)
	anchor.add_child(_vbox)

## Shows one caption line, e.g. caption("[Шаги]"). Safe to call before
## _ready() has run -- see ActionLog.log_event()'s matching note.
func caption(text: String) -> void:
	if not _vbox:
		return

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(label)

	while _vbox.get_child_count() > MAX_LINES:
		var oldest := _vbox.get_child(0)
		_vbox.remove_child(oldest)
		oldest.queue_free()

	var tween := create_tween()
	tween.tween_interval(LIFETIME)
	tween.tween_property(label, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(label.queue_free)
