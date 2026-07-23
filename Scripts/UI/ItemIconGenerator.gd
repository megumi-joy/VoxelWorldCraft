class_name ItemIconGenerator
extends RefCounted
## Procedural pixel-art icon generator for non-block items (tools, food,
## ingots, resources, block-entities with no atlas cell). ItemIcon.gd's
## ATLAS_CELL only covers items that draw as a textured cube face -- anything
## else (pickaxe/axe/shovel/hoe/sword, bread/apple/berries/meat, iron/gold/
## copper ingots, sticks, furnace/crafting-table/bed/torch, ...) used to fall
## back to a flat color square, which is why every non-block slot looked like
## an identical colored swatch. This draws a small recognizable glyph into an
## Image (same Image.create -> set_pixel -> ImageTexture approach as
## Scripts/World/TextureGenerator.gd, just per-item instead of per-atlas-cell)
## so each item at least has a distinct silhouette, not just a distinct tint.
##
## Entry point: get_texture(item_data) -> ImageTexture, cached per item id.

const ICON_PX := 32
const OUTLINE := Color(0.08, 0.07, 0.06, 1)
const HANDLE_COLOR := Color(0.55, 0.36, 0.16, 1)

static var _cache: Dictionary = {}

static func get_texture(item_data) -> ImageTexture:
	if not item_data:
		return null
	if _cache.has(item_data.id):
		return _cache[item_data.id]
	var tex := _generate(item_data)
	_cache[item_data.id] = tex
	return tex

static func _generate(item_data) -> ImageTexture:
	var img := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_item(img, item_data)
	return ImageTexture.create_from_image(img)

static func _draw_item(img: Image, item_data) -> void:
	match item_data.id:
		8:
			_draw_furnace(img)
			return
		9:
			_draw_crafting_table(img)
			return
		10:
			_draw_bed(img)
			return
		56:
			_draw_torch(img)
			return
		11:
			_draw_apple(img)
			return
		22:
			_draw_bread(img)
			return
		70:
			_draw_berries(img)
			return
		94:
			_draw_meat(img, Color(0.82, 0.30, 0.30), false)
			return
		95:
			_draw_meat(img, Color(0.55, 0.32, 0.16), true)
			return
		72:
			_draw_meat(img, Color(0.88, 0.60, 0.62), false)
			return
		23:
			_draw_stick(img)
			return
		20:
			_draw_seeds(img)
			return
		21:
			_draw_wheat(img)
			return
		71:
			_draw_wool(img)
			return
		99:
			_draw_leather(img)
			return
		66:
			_draw_gem(img, Color(0.65, 0.45, 0.85))
			return
		62:
			_draw_raw_nugget(img, Color(0.72, 0.42, 0.30))
			return
		63:
			_draw_ingot(img, Color(0.80, 0.82, 0.85))
			return
		64:
			_draw_ingot(img, Color(1.00, 0.84, 0.00))
			return
		65:
			_draw_ingot(img, Color(0.85, 0.45, 0.15))
			return
		67:
			_draw_bucket(img, -1)
			return
		68:
			_draw_bucket(img, 0)
			return
		69:
			_draw_bucket(img, 1)
			return
		60:
			_draw_torso(img, Color(0.50, 0.32, 0.14), false)
			return
		61:
			_draw_torso(img, Color(0.65, 0.68, 0.72), true)
			return

	if item_data.type == 1: # TOOL
		match item_data.tool_type:
			"pickaxe":
				_draw_pickaxe(img, _tier_color(item_data.tier))
				return
			"shovel":
				_draw_shovel(img, _tier_color(item_data.tier))
				return
			"axe":
				_draw_axe(img, _tier_color(item_data.tier))
				return
			"hoe":
				_draw_hoe(img, _tier_color(item_data.tier))
				return
		if item_data.tier > 0: # bare tool_type + a material tier == a sword
			_draw_sword(img, _tier_color(item_data.tier))
			return
		_draw_generic_tool(img, Color(0.6, 0.6, 0.6))
		return

	if item_data.id >= 100: # Periodic-table elements -- one generic gem/shard
		_draw_gem(img, Color(0.55, 0.75, 0.85))
		return

	# Last-resort so nothing silently renders blank.
	_draw_gem(img, Color(0.65, 0.45, 0.85))

static func _tier_color(tier: int) -> Color:
	match tier:
		1: return Color(0.68, 0.52, 0.32) # Wood
		2: return Color(0.58, 0.58, 0.60) # Stone
		3: return Color(0.82, 0.84, 0.87) # Iron
	return Color(0.60, 0.62, 0.66)

# --- Low-level drawing primitives -------------------------------------------

static func _px(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < ICON_PX and y >= 0 and y < ICON_PX:
		img.set_pixel(x, y, color)

static func _fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(img, x, y, color)

static func _stroke_rect(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	for x in range(x0, x1 + 1):
		_px(img, x, y0, color)
		_px(img, x, y1, color)
	for y in range(y0, y1 + 1):
		_px(img, x0, y, color)
		_px(img, x1, y, color)

static func _fill_circle(img: Image, cx: float, cy: float, r: float, color: Color) -> void:
	var ri := int(ceil(r))
	for y in range(int(cy) - ri, int(cy) + ri + 1):
		for x in range(int(cx) - ri, int(cx) + ri + 1):
			var dx = x - cx
			var dy = y - cy
			if dx * dx + dy * dy <= r * r:
				_px(img, x, y, color)

static func _line(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx + dy
	var x = x0
	var y = y0
	while true:
		_px(img, x, y, color)
		if x == x1 and y == y1:
			break
		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy

# Even-odd scanline polygon fill (pts: Array of Vector2). Handles the convex
# and mildly-concave shapes used below (triangles, trapezoids, kite shapes).
static func _fill_polygon(img: Image, pts: Array, color: Color) -> void:
	if pts.size() < 3:
		return
	var miny = pts[0].y
	var maxy = pts[0].y
	for p in pts:
		miny = min(miny, p.y)
		maxy = max(maxy, p.y)
	var n = pts.size()
	for y in range(int(floor(miny)), int(ceil(maxy)) + 1):
		var xs: Array = []
		for i in range(n):
			var p1: Vector2 = pts[i]
			var p2: Vector2 = pts[(i + 1) % n]
			if (p1.y <= y and p2.y > y) or (p2.y <= y and p1.y > y):
				var t = (float(y) - p1.y) / (p2.y - p1.y)
				xs.append(p1.x + t * (p2.x - p1.x))
		xs.sort()
		var i = 0
		while i + 1 < xs.size():
			var xa = int(round(xs[i]))
			var xb = int(round(xs[i + 1]))
			for x in range(xa, xb + 1):
				_px(img, x, y, color)
			i += 2

static func _stroke_polygon(img: Image, pts: Array, color: Color) -> void:
	var n = pts.size()
	for i in range(n):
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		_line(img, int(round(p1.x)), int(round(p1.y)), int(round(p2.x)), int(round(p2.y)), color)

# Thick-line quad (a rotated rectangle from p0 to p1, half-width hw) -- used
# for tool handles/sticks/torch pole, where a single flat _line would be too
# thin to read at icon size.
static func _thick_quad(p0: Vector2, p1: Vector2, hw: float) -> Array:
	var dir: Vector2 = p1 - p0
	if dir.length() < 0.001:
		dir = Vector2(1, 0)
	dir = dir.normalized()
	var perp = Vector2(-dir.y, dir.x) * hw
	return [p0 + perp, p1 + perp, p1 - perp, p0 - perp]

# --- Tools (diagonal handle bottom-right -> head top-left, Minecraft-style) --

static func _draw_handle(img: Image) -> void:
	var quad = _thick_quad(Vector2(27, 29), Vector2(13, 17), 1.8)
	_fill_polygon(img, quad, HANDLE_COLOR)
	_stroke_polygon(img, quad, OUTLINE)

static func _draw_pickaxe(img: Image, head_color: Color) -> void:
	_draw_handle(img)
	var spike_a = [Vector2(13, 17), Vector2(9, 16), Vector2(2, 7)]
	var spike_b = [Vector2(13, 17), Vector2(18, 14), Vector2(26, 4)]
	_fill_polygon(img, spike_a, head_color)
	_stroke_polygon(img, spike_a, OUTLINE)
	_fill_polygon(img, spike_b, head_color)
	_stroke_polygon(img, spike_b, OUTLINE)

static func _draw_axe(img: Image, head_color: Color) -> void:
	_draw_handle(img)
	var blade = [Vector2(13, 18), Vector2(12, 4), Vector2(27, 9)]
	_fill_polygon(img, blade, head_color)
	_stroke_polygon(img, blade, OUTLINE)

static func _draw_shovel(img: Image, head_color: Color) -> void:
	_draw_handle(img)
	var blade = [Vector2(7, 3), Vector2(19, 3), Vector2(20, 11), Vector2(13, 18), Vector2(6, 11)]
	_fill_polygon(img, blade, head_color)
	_stroke_polygon(img, blade, OUTLINE)

static func _draw_hoe(img: Image, head_color: Color) -> void:
	_draw_handle(img)
	var blade = [Vector2(5, 10), Vector2(20, 4), Vector2(23, 8), Vector2(8, 14)]
	_fill_polygon(img, blade, head_color)
	_stroke_polygon(img, blade, OUTLINE)

static func _draw_sword(img: Image, blade_color: Color) -> void:
	var blade = [Vector2(16, 2), Vector2(19, 21), Vector2(13, 21)]
	_fill_polygon(img, blade, blade_color)
	_stroke_polygon(img, blade, OUTLINE)
	_fill_rect(img, 9, 21, 23, 24, Color(0.30, 0.30, 0.33))
	_stroke_rect(img, 9, 21, 23, 24, OUTLINE)
	_fill_rect(img, 14, 24, 18, 29, Color(0.32, 0.20, 0.10))
	_stroke_rect(img, 14, 24, 18, 29, OUTLINE)
	_fill_rect(img, 13, 29, 19, 30, Color(0.22, 0.22, 0.24))
	_stroke_rect(img, 13, 29, 19, 30, OUTLINE)

static func _draw_generic_tool(img: Image, color: Color) -> void:
	_draw_handle(img)
	_fill_circle(img, 13, 13, 7, OUTLINE)
	_fill_circle(img, 13, 13, 6, color)

static func _draw_bucket(img: Image, variant: int) -> void:
	var body = [Vector2(8, 12), Vector2(24, 12), Vector2(21, 29), Vector2(11, 29)]
	_fill_polygon(img, body, Color(0.55, 0.55, 0.58))
	_stroke_polygon(img, body, OUTLINE)
	_fill_rect(img, 10, 7, 22, 9, Color(0.42, 0.42, 0.45))
	_stroke_rect(img, 10, 7, 22, 9, OUTLINE)
	if variant == 0: # Water
		_fill_rect(img, 10, 13, 22, 17, Color(0.20, 0.45, 0.95))
		_stroke_rect(img, 10, 13, 22, 17, OUTLINE)
	elif variant == 1: # Lava
		_fill_rect(img, 10, 13, 22, 17, Color(1.00, 0.40, 0.05))
		_stroke_rect(img, 10, 13, 22, 17, OUTLINE)

# --- Ingots / raw materials / gems ------------------------------------------

static func _draw_ingot(img: Image, color: Color) -> void:
	var body = [Vector2(6, 20), Vector2(26, 20), Vector2(23, 27), Vector2(9, 27)]
	_fill_polygon(img, body, color)
	_stroke_polygon(img, body, OUTLINE)
	for x in range(9, 24):
		_px(img, x, 21, color.lightened(0.35))

static func _draw_raw_nugget(img: Image, color: Color) -> void:
	var body = [Vector2(10, 10), Vector2(20, 7), Vector2(26, 14), Vector2(23, 23), Vector2(13, 26), Vector2(6, 17)]
	_fill_polygon(img, body, color)
	_stroke_polygon(img, body, OUTLINE)
	_px(img, 13, 14, color.darkened(0.35))
	_px(img, 18, 17, color.darkened(0.35))
	_px(img, 15, 21, color.darkened(0.35))

static func _draw_gem(img: Image, color: Color) -> void:
	var body = [Vector2(16, 4), Vector2(23, 12), Vector2(20, 27), Vector2(12, 27), Vector2(9, 12)]
	_fill_polygon(img, body, color)
	_stroke_polygon(img, body, OUTLINE)
	_line(img, 16, 7, 18, 20, color.lightened(0.4))

# --- Food --------------------------------------------------------------------

static func _draw_apple(img: Image) -> void:
	_fill_circle(img, 16, 18, 9, OUTLINE)
	_fill_circle(img, 16, 18, 8, Color(0.82, 0.12, 0.12))
	_fill_rect(img, 15, 5, 17, 9, Color(0.40, 0.26, 0.10))
	var leaf = [Vector2(17, 7), Vector2(22, 5), Vector2(20, 10)]
	_fill_polygon(img, leaf, Color(0.25, 0.55, 0.20))

static func _draw_bread(img: Image) -> void:
	var body = [Vector2(7, 13), Vector2(11, 9), Vector2(21, 9), Vector2(25, 13), Vector2(25, 21), Vector2(21, 25), Vector2(11, 25), Vector2(7, 21)]
	_fill_polygon(img, body, Color(0.78, 0.55, 0.25))
	_stroke_polygon(img, body, OUTLINE)
	_line(img, 11, 13, 15, 17, Color(0.55, 0.35, 0.12))
	_line(img, 15, 13, 19, 17, Color(0.55, 0.35, 0.12))
	_line(img, 19, 13, 23, 17, Color(0.55, 0.35, 0.12))

static func _draw_berries(img: Image) -> void:
	var leaf = [Vector2(14, 7), Vector2(18, 7), Vector2(16, 3)]
	_fill_polygon(img, leaf, Color(0.25, 0.55, 0.20))
	var centers = [Vector2(11, 15), Vector2(18, 13), Vector2(14, 20), Vector2(21, 19), Vector2(16, 16)]
	for i in range(centers.size()):
		var c: Vector2 = centers[i]
		var shade = 0.55 if i % 2 == 0 else 0.42
		_fill_circle(img, c.x, c.y, 3.4, OUTLINE)
		_fill_circle(img, c.x, c.y, 2.6, Color(shade, 0.04, 0.16 + shade * 0.1))

static func _draw_meat(img: Image, color: Color, grilled: bool) -> void:
	var body = [Vector2(10, 10), Vector2(20, 8), Vector2(25, 14), Vector2(23, 21), Vector2(15, 24), Vector2(9, 19)]
	_fill_polygon(img, body, color)
	_stroke_polygon(img, body, OUTLINE)
	if grilled:
		_line(img, 11, 12, 22, 18, color.darkened(0.5))
		_line(img, 12, 18, 22, 12, color.darkened(0.5))
	_fill_rect(img, 16, 22, 20, 29, Color(0.92, 0.90, 0.85))
	_stroke_rect(img, 16, 22, 20, 29, OUTLINE)
	_fill_rect(img, 14, 27, 22, 30, Color(0.92, 0.90, 0.85))
	_stroke_rect(img, 14, 27, 22, 30, OUTLINE)

# --- Misc resources ----------------------------------------------------------

static func _draw_stick(img: Image) -> void:
	var quad = _thick_quad(Vector2(8, 27), Vector2(25, 6), 1.6)
	_fill_polygon(img, quad, Color(0.62, 0.42, 0.20))
	_stroke_polygon(img, quad, OUTLINE)
	_line(img, 13, 22, 16, 19, Color(0.40, 0.26, 0.10))
	_line(img, 18, 16, 21, 13, Color(0.40, 0.26, 0.10))

static func _draw_seeds(img: Image) -> void:
	var centers = [Vector2(12, 13), Vector2(20, 13), Vector2(16, 10), Vector2(10, 20), Vector2(22, 20), Vector2(16, 23)]
	for c in centers:
		_fill_circle(img, c.x, c.y, 2.2, OUTLINE)
		_fill_circle(img, c.x, c.y, 1.5, Color(0.65, 0.55, 0.25))

static func _draw_wheat(img: Image) -> void:
	for x in [9, 16, 23]:
		_line(img, x, 27, x, 9, Color(0.80, 0.68, 0.18))
		var ty = 9
		while ty < 18:
			_line(img, x, ty, x - 3, ty - 2, Color(0.85, 0.75, 0.25))
			_line(img, x, ty, x + 3, ty - 2, Color(0.85, 0.75, 0.25))
			ty += 3

static func _draw_wool(img: Image) -> void:
	var centers = [Vector2(12, 14), Vector2(20, 13), Vector2(16, 19), Vector2(10, 20), Vector2(22, 20)]
	for c in centers:
		_fill_circle(img, c.x, c.y, 6.2, OUTLINE)
	for c in centers:
		_fill_circle(img, c.x, c.y, 5.2, Color(0.92, 0.90, 0.85))

static func _draw_leather(img: Image) -> void:
	var body = [Vector2(6, 9), Vector2(22, 7), Vector2(26, 17), Vector2(20, 26), Vector2(8, 24), Vector2(5, 15)]
	_fill_polygon(img, body, Color(0.55, 0.35, 0.18))
	_stroke_polygon(img, body, OUTLINE)
	_line(img, 9, 13, 14, 11, Color(0.35, 0.20, 0.08))
	_line(img, 16, 20, 21, 17, Color(0.35, 0.20, 0.08))

static func _draw_torso(img: Image, color: Color, metallic: bool) -> void:
	var body = [Vector2(10, 8), Vector2(22, 8), Vector2(24, 27), Vector2(8, 27)]
	_fill_polygon(img, body, color)
	_stroke_polygon(img, body, OUTLINE)
	var sleeve_l = [Vector2(5, 9), Vector2(10, 9), Vector2(9, 17), Vector2(4, 17)]
	var sleeve_r = [Vector2(22, 9), Vector2(27, 9), Vector2(28, 17), Vector2(23, 17)]
	_fill_polygon(img, sleeve_l, color)
	_stroke_polygon(img, sleeve_l, OUTLINE)
	_fill_polygon(img, sleeve_r, color)
	_stroke_polygon(img, sleeve_r, OUTLINE)
	_fill_rect(img, 14, 8, 18, 11, color.darkened(0.25))
	if metallic:
		for x in range(9, 23):
			_px(img, x, 14, color.lightened(0.35))
			_px(img, x, 20, color.lightened(0.35))

# --- Block-entities with no atlas cell (own 3D model in-world) --------------

static func _draw_furnace(img: Image) -> void:
	_fill_rect(img, 5, 6, 27, 28, Color(0.42, 0.42, 0.45))
	_stroke_rect(img, 5, 6, 27, 28, OUTLINE)
	_fill_rect(img, 4, 4, 28, 7, Color(0.28, 0.28, 0.30))
	_stroke_rect(img, 4, 4, 28, 7, OUTLINE)
	_fill_rect(img, 11, 17, 21, 25, Color(0.05, 0.05, 0.05))
	_stroke_rect(img, 11, 17, 21, 25, OUTLINE)
	_fill_rect(img, 14, 19, 18, 23, Color(0.95, 0.50, 0.10))

static func _draw_crafting_table(img: Image) -> void:
	_fill_rect(img, 4, 4, 28, 28, Color(0.55, 0.36, 0.16))
	_stroke_rect(img, 4, 4, 28, 28, OUTLINE)
	_line(img, 16, 4, 16, 28, Color(0.35, 0.22, 0.10))
	_line(img, 4, 16, 28, 16, Color(0.35, 0.22, 0.10))

static func _draw_bed(img: Image) -> void:
	_fill_rect(img, 4, 10, 28, 26, Color(0.80, 0.15, 0.20))
	_stroke_rect(img, 4, 10, 28, 26, OUTLINE)
	_fill_rect(img, 4, 10, 11, 26, Color(0.90, 0.88, 0.85))
	_stroke_rect(img, 4, 10, 11, 26, OUTLINE)
	_fill_rect(img, 5, 26, 7, 29, Color(0.30, 0.20, 0.10))
	_fill_rect(img, 25, 26, 27, 29, Color(0.30, 0.20, 0.10))

static func _draw_torch(img: Image) -> void:
	var quad = _thick_quad(Vector2(16, 30), Vector2(16, 14), 1.4)
	_fill_polygon(img, quad, Color(0.45, 0.30, 0.14))
	_stroke_polygon(img, quad, OUTLINE)
	var flame = [Vector2(16, 4), Vector2(21, 10), Vector2(18, 15), Vector2(14, 15), Vector2(11, 10)]
	_fill_polygon(img, flame, Color(0.95, 0.45, 0.05))
	_stroke_polygon(img, flame, OUTLINE)
	var inner = [Vector2(16, 7), Vector2(19, 11), Vector2(17, 14), Vector2(15, 14), Vector2(13, 11)]
	_fill_polygon(img, inner, Color(1.00, 0.82, 0.20))
