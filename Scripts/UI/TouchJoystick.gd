extends Control
# Procedurally-drawn virtual joystick visual (base ring + knob). No image
# assets -- matches the rest of the HUD's convention of drawing chunky shapes
# in _draw() (see HudCrosshair.gd / HudStatIcon.gd). Purely visual: all touch
# tracking / clamped-output-vector math lives in TouchControls.gd (ported
# from MagicBallsAdventure's scripts/virtual_joystick.gd), which calls
# set_knob_offset() here every time the output vector changes.
#
# Palette intentionally matches Scripts/UI/HUD.gd's "bright hypercasual"
# constants (cream panel, dark-brown outline) so the touch layer reads as
# part of the same HUD family rather than a bolted-on control scheme.

const COL_BASE_BG := Color(1.0, 0.97, 0.88, 0.55)
const COL_BASE_BORDER := Color(0.16, 0.09, 0.04, 0.85)
const COL_KNOB := Color(0.30, 0.55, 0.95, 0.95)
const COL_KNOB_ACTIVE := Color(1.0, 0.62, 0.06, 0.95)
const COL_KNOB_BORDER := Color(0.16, 0.09, 0.04, 1.0)

var knob_offset: Vector2 = Vector2.ZERO # -1..1 on each axis
var active: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func set_knob_offset(offset: Vector2, is_active: bool) -> void:
	knob_offset = offset
	active = is_active
	queue_redraw()

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var c = size / 2.0
	var base_r = min(size.x, size.y) / 2.0
	var knob_r = base_r * 0.42

	draw_circle(c, base_r, COL_BASE_BG)
	draw_arc(c, base_r - 2.0, 0.0, TAU, 48, COL_BASE_BORDER, 4.0, true)

	var knob_c = c + knob_offset * (base_r - knob_r)
	var knob_col = COL_KNOB_ACTIVE if active else COL_KNOB
	draw_circle(knob_c, knob_r, knob_col)
	draw_arc(knob_c, knob_r - 1.5, 0.0, TAU, 32, COL_KNOB_BORDER, 3.0, true)
