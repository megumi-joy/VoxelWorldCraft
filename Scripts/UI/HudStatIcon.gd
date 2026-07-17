extends Control
# Tiny procedurally-drawn chunky icon used next to the HUD stat bars.
# No image assets needed -- shapes are built from primitives so the HUD stays
# self-contained (icon_type is set per-instance in Scenes/HUD.tscn).

@export var icon_type: String = "heart" # "heart" (health) or "food" (hunger)

func _ready():
	queue_redraw()

func _draw():
	var w = size.x
	var h = size.y
	if w <= 0 or h <= 0:
		return
	match icon_type:
		"heart":
			_draw_heart(w, h)
		"food":
			_draw_food(w, h)
		_:
			pass

func _draw_heart(w: float, h: float) -> void:
	var outline := Color(0.28, 0.02, 0.05)
	var fill := Color(0.95, 0.18, 0.28)
	var shine := Color(1, 1, 1, 0.55)

	_heart_shapes(w, h, 1.0, outline)
	_heart_shapes(w, h, 0.82, fill)

	draw_circle(Vector2(w * 0.30, h * 0.30), w * 0.07, shine)

func _heart_shapes(w: float, h: float, scale: float, col: Color) -> void:
	var lobe_r = w * 0.26 * scale
	var left_c = Vector2(w * 0.5 - w * 0.18 * scale, h * 0.38)
	var right_c = Vector2(w * 0.5 + w * 0.18 * scale, h * 0.38)
	draw_circle(left_c, lobe_r, col)
	draw_circle(right_c, lobe_r, col)

	var pts := PackedVector2Array([
		Vector2(w * 0.5 - w * 0.42 * scale, h * 0.42),
		Vector2(w * 0.5 + w * 0.42 * scale, h * 0.42),
		Vector2(w * 0.5, h * 0.92 * scale + h * 0.02),
	])
	draw_colored_polygon(pts, col)

func _draw_food(w: float, h: float) -> void:
	var outline := Color(0.35, 0.18, 0.02)
	var body := Color(1.0, 0.55, 0.14)
	var stem := Color(0.42, 0.26, 0.08)
	var leaf := Color(0.28, 0.75, 0.28)
	var shine := Color(1, 1, 1, 0.5)

	var center = Vector2(w * 0.5, h * 0.58)
	var r = w * 0.34

	draw_circle(center, r + 3.0, outline)
	draw_circle(center, r, body)
	draw_circle(center + Vector2(-r * 0.35, -r * 0.35), r * 0.28, shine)

	draw_rect(Rect2(w * 0.46, h * 0.06, w * 0.08, h * 0.18), stem)

	var leaf_pts := PackedVector2Array([
		Vector2(w * 0.54, h * 0.10),
		Vector2(w * 0.82, h * 0.0),
		Vector2(w * 0.64, h * 0.24),
	])
	draw_colored_polygon(leaf_pts, leaf)
