extends Control
# Simple chunky centered crosshair: a dark outline pass then a bright fill
# pass so it stays readable against any background (sky, terrain, mobs).

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw():
	var c = size / 2.0
	var gap = size.x * 0.20
	var arm = size.x * 0.32

	var segments = [
		[Vector2(c.x, c.y - gap - arm), Vector2(c.x, c.y - gap)],
		[Vector2(c.x, c.y + gap), Vector2(c.x, c.y + gap + arm)],
		[Vector2(c.x - gap - arm, c.y), Vector2(c.x - gap, c.y)],
		[Vector2(c.x + gap, c.y), Vector2(c.x + gap + arm, c.y)],
	]

	for seg in segments:
		draw_line(seg[0], seg[1], Color(0, 0, 0, 0.6), 5.0, true)
	for seg in segments:
		draw_line(seg[0], seg[1], Color(1, 1, 1, 0.95), 2.5, true)

	draw_circle(c, 1.6, Color(1, 1, 1, 0.9))
