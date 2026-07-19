extends CanvasLayer
# Small on-screen feed of recent player actions/events -- corner overlay,
# last MAX_LINES lines, each auto-fading out after LINE_LIFETIME seconds.
#
# Global autoload (its own top-level CanvasLayer under /root, not scoped to
# Player.tscn's own "HUD" CanvasLayer) so it keeps working the same
# regardless of which scene is active and survives World.tscn <->
# MainMenu.tscn scene changes without needing to be re-wired per scene.
#
# Hooked from: Player.gd (block break/place, death/respawn) and
# CraftingUI.gd (successful craft) -- see each call site's own comment for
# why that's the right point of truth for that action.

const MAX_LINES := 5
const LINE_LIFETIME := 4.0
const FADE_TIME := 0.6

var _vbox: VBoxContainer

func _ready() -> void:
	layer = 20 # above Player.tscn's own "HUD" CanvasLayer (default layer 0)

	var anchor := Control.new()
	anchor.name = "Anchor"
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	anchor.offset_left = 14.0
	anchor.offset_top = -190.0
	anchor.offset_right = 420.0
	anchor.offset_bottom = -14.0
	# New lines get added at the bottom of the VBox; growing "up" (BEGIN)
	# keeps the feed anchored to its bottom-left corner as it fills rather
	# than pushing content off toward the top-left.
	anchor.grow_vertical = Control.GROW_DIRECTION_BEGIN
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_vbox = VBoxContainer.new()
	_vbox.name = "VBox"
	_vbox.alignment = BoxContainer.ALIGNMENT_END
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.add_child(_vbox)

## Appends one line to the feed. Safe to call before this autoload's
## _ready() has run (e.g. from another autoload's own _ready()) -- just
## drops the line instead of erroring, since _vbox doesn't exist that early.
func log_event(text: String) -> void:
	if not _vbox:
		return

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(label)

	while _vbox.get_child_count() > MAX_LINES:
		var oldest := _vbox.get_child(0)
		_vbox.remove_child(oldest)
		oldest.queue_free()

	var tween := create_tween()
	tween.tween_interval(LINE_LIFETIME)
	tween.tween_property(label, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(label.queue_free)
