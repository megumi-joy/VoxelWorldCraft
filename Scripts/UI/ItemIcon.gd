extends RefCounted
class_name ItemIcon
## Shared Minecraft-style slot visual: item ICON (real block-atlas texture
## region when available, flat color swatch fallback otherwise) + a
## bottom-right count badge (only when count > 1) + name-on-hover tooltip.
## Used by InventoryUI/CraftingUI/FurnaceUI/ChestUI so all 4 menus render
## slots the same way instead of each rebuilding its own text label.
##
## Deliberately does NOT touch Scripts/World/Chunk.gd or HotbarUI.gd -- this
## is a UI-only change (see task scope). ATLAS_CELL below is a data-only
## COPY of Chunk.gd's block-type -> atlas-cell mapping, keyed by ITEM id
## instead of raw voxel `type` (for every block item these are the same
## value except Sand/Snow, which are folded in directly under their item
## ids 42/43 to match what Chunk.gd actually draws for those). If Chunk.gd's
## mapping changes, update the table here too.

const CELL_PX := 64
const ATLAS_TOTAL_PX := 512

const ATLAS_CELL := {
	2: Vector2i(0, 0),   # Grass (top face -- green)
	1: Vector2i(1, 0),   # Dirt
	3: Vector2i(2, 0),   # Stone
	4: Vector2i(4, 0),   # Wood (side/bark face -- top face atlas cell is
	                     # visually a leaf-green placeholder in Chunk.gd, so
	                     # the bark face reads as "wood" correctly here)
	73: Vector2i(5, 0),  # Storage Chest

	5: Vector2i(0, 1),   # Coal Ore
	6: Vector2i(1, 1),   # Iron Ore
	13: Vector2i(2, 1),  # Planks
	14: Vector2i(3, 1),  # Farmland
	96: Vector2i(4, 1),  # Clay
	97: Vector2i(5, 1),  # Glass
	98: Vector2i(6, 1),  # Brick

	43: Vector2i(0, 2),  # Snow
	42: Vector2i(1, 2),  # Sand
	50: Vector2i(2, 2),  # Birch Leaves (reuses generic Leaves cell)
	57: Vector2i(2, 2),  # Oak Leaves
	52: Vector2i(3, 2),  # Ice

	40: Vector2i(0, 3),  # Water
	41: Vector2i(1, 3),  # Lava
	48: Vector2i(2, 3),  # Birch Wood
	49: Vector2i(3, 3),  # Pine Wood
	51: Vector2i(2, 2),  # Pine Leaves (reuse Oak, matches Chunk.gd)

	44: Vector2i(0, 4),  # Flower (Red)
	45: Vector2i(1, 4),  # Flower (Yellow)
	46: Vector2i(2, 4),  # Tall Grass
	47: Vector2i(3, 4),  # Cactus
	55: Vector2i(4, 4),  # Berry Bush
	53: Vector2i(5, 4),  # Flower (Blue)
	54: Vector2i(6, 4),  # Flower (Pink)

	80: Vector2i(2, 5),  # Copper Ore
	81: Vector2i(3, 5),  # Gold Ore
	82: Vector2i(4, 5),  # Quartz
	83: Vector2i(5, 5),  # Hematite
	84: Vector2i(6, 5),  # Malachite Ore
	85: Vector2i(7, 5),  # Amethyst Ore
}

# Flat-color fallback for items with no atlas cell (tools, resources,
# consumables, block-entities rendered as their own 3D model instead of a
# textured cube, chemical elements). Specific, recognizable colors where it
# matters (smelting outputs especially, since a furnace's output slot is the
# most likely place a player stares at one of these); a generic per-type
# color otherwise.
const FALLBACK_COLOR := {
	63: Color(0.80, 0.82, 0.85),  # Iron Ingot
	64: Color(1.00, 0.84, 0.00),  # Gold Ingot
	65: Color(0.85, 0.45, 0.15),  # Copper Ingot
	23: Color(0.75, 0.60, 0.35),  # Sticks
	20: Color(0.55, 0.75, 0.35),  # Seeds
	21: Color(0.85, 0.75, 0.25),  # Wheat
	22: Color(0.78, 0.55, 0.25),  # Bread
	11: Color(0.85, 0.15, 0.15),  # Apple
	70: Color(0.65, 0.05, 0.15),  # Berries
	71: Color(0.92, 0.90, 0.85),  # Wool
	72: Color(0.85, 0.55, 0.55),  # Mutton
	94: Color(0.85, 0.35, 0.35),  # Raw Meat
	95: Color(0.65, 0.35, 0.15),  # Cooked Meat
	99: Color(0.55, 0.35, 0.18),  # Leather
	66: Color(0.65, 0.45, 0.85),  # Amethyst Shard
	67: Color(0.55, 0.55, 0.58),  # Bucket
	68: Color(0.25, 0.45, 0.90),  # Water Bucket
	69: Color(1.00, 0.35, 0.05),  # Lava Bucket
	60: Color(0.50, 0.32, 0.14),  # Leather Tunic
	61: Color(0.60, 0.62, 0.65),  # Iron Chestplate
	8: Color(0.45, 0.45, 0.48),   # Furnace (own 3D model, no atlas cell)
	9: Color(0.55, 0.36, 0.16),   # Crafting Table (own 3D model)
	10: Color(0.85, 0.15, 0.20),  # Bed (own 3D model)
	62: Color(0.72, 0.42, 0.30),  # Raw Iron
	12: Color(0.78, 0.80, 0.84),  # Iron Sword
}

static func _get_atlas_texture(ref_node: Node) -> Texture2D:
	if not ref_node:
		return null
	var world = ref_node.get_node_or_null("/root/World/VoxelWorld")
	if world and ("chunk_material" in world) and world.chunk_material:
		return world.chunk_material.albedo_texture
	return null

static func _fallback_color(item_data) -> Color:
	if FALLBACK_COLOR.has(item_data.id):
		return FALLBACK_COLOR[item_data.id]

	if item_data.type == 1: # TOOL
		match item_data.tier:
			1: return Color(0.62, 0.45, 0.25) # Wood tier
			2: return Color(0.55, 0.55, 0.55) # Stone tier
			3: return Color(0.75, 0.78, 0.82) # Iron tier
		return Color(0.55, 0.58, 0.62)

	if item_data.type == 3: # CONSUMABLE
		return Color(0.95, 0.35, 0.25)

	if item_data.id >= 100: # Periodic-table elements
		return Color(0.55, 0.75, 0.85)

	return Color(0.65, 0.45, 0.85) # generic RESOURCE fallback

## Builds one icon control: atlas TextureRect for a real block texture,
## procedurally-drawn glyph TextureRect (ItemIconGenerator) for everything
## else (tools/food/ingots/resources/block-entities), rounded color-swatch
## panel only as a last-resort fallback (block item while the world atlas
## hasn't loaded yet, or a glyph the generator doesn't recognize). `ref_node`
## just needs to be any node currently inside the scene tree (used to resolve
## the shared world atlas texture via an absolute node path).
static func make_icon_node(item_data, ref_node: Node, icon_size: float) -> Control:
	var cell = ATLAS_CELL.get(item_data.id)
	var atlas_tex: Texture2D = _get_atlas_texture(ref_node) if cell != null else null

	if cell != null and atlas_tex:
		var region_tex := AtlasTexture.new()
		region_tex.atlas = atlas_tex
		region_tex.region = Rect2(cell.x * CELL_PX, cell.y * CELL_PX, CELL_PX, CELL_PX)

		var rect := TextureRect.new()
		rect.texture = region_tex
		rect.custom_minimum_size = Vector2(icon_size, icon_size)
		rect.size = Vector2(icon_size, icon_size)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		# Blocky/no-blur, same intent as TextureGenerator's 3D material NEAREST
		# filter -- that setting is 3D-material-only, so the 2D TextureRect
		# needs its own filter set explicitly or it defaults to linear/blurry.
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect

	if cell == null:
		# preload (compile-time const) instead of the global class_name so this
		# resolves even when .godot's global class cache hasn't registered the
		# freshly-added ItemIconGenerator.gd (headless/container runs).
		var glyph_tex: ImageTexture = preload("res://Scripts/UI/ItemIconGenerator.gd").get_texture(item_data)
		if glyph_tex:
			var rect := TextureRect.new()
			rect.texture = glyph_tex
			rect.custom_minimum_size = Vector2(icon_size, icon_size)
			rect.size = Vector2(icon_size, icon_size)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_SCALE
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return rect

	# Fallback: rounded flat-color swatch (mirrors HotbarUI.gd's existing
	# icon-swatch style so a slot without a real texture still reads as an
	# "icon", never as bare text). Only reached for a block item while the
	# world atlas texture isn't resolved yet, or an id ItemIconGenerator has
	# no glyph for.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(icon_size, icon_size)
	panel.size = Vector2(icon_size, icon_size)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = _fallback_color(item_data)
	style.set_corner_radius_all(int(icon_size * 0.12))
	style.set_border_width_all(1)
	style.border_color = Color(0, 0, 0, 0.35)
	panel.add_theme_stylebox_override("panel", style)
	return panel

static func _make_count_badge(count: int, slot_size: float) -> Control:
	var badge := PanelContainer.new()
	var bw = slot_size * 0.46
	var bh = slot_size * 0.30
	badge.custom_minimum_size = Vector2(bw, bh)
	badge.size = Vector2(bw, bh)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -bw
	badge.offset_right = 0
	badge.offset_top = -bh
	badge.offset_bottom = 0
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.03, 0.88)
	style.set_corner_radius_all(int(bh * 0.35))
	badge.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = str(count)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", max(10, int(slot_size * 0.24)))
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(lbl)
	return badge

## Fills a slot Button with the icon-grid visual: icon + count badge (if
## count > 1) as ignore-mouse children (so the Button's own `pressed` signal
## keeps firing -- see HotbarUI.gd's identical convention), name shown only
## as `tooltip_text` (hover), never as a visible label. `item_data == null`
## clears the slot to empty (also needed for FurnaceUI's 3 fixed slot nodes,
## which are reused across update_ui() calls rather than recreated).
static func populate_slot(button: Button, item_data, count: int, slot_size: float) -> void:
	for child in button.get_children():
		child.queue_free()
	button.text = ""
	button.clip_text = true

	if not item_data:
		button.tooltip_text = ""
		return

	button.tooltip_text = item_data.name

	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(content)

	var margin = slot_size * 0.12
	var icon_size = slot_size - margin * 2.0
	var icon = make_icon_node(item_data, button, icon_size)
	icon.position = Vector2(margin, margin)
	content.add_child(icon)

	if count > 1:
		content.add_child(_make_count_badge(count, slot_size))

## Rounded, translucent slot-button chrome matching the HUD's existing look
## (same corner-radius/border idea as HotbarUI.gd's slot panels), applied to
## the plain-Godot-theme Buttons FurnaceUI.gd/ChestUI.gd used to leave
## unstyled. Purely cosmetic chrome -- does not touch click wiring.
static func apply_slot_style(button: Button, highlighted: bool = false) -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	if highlighted:
		style.bg_color = Color(1.0, 0.85, 0.2, 0.35)
		style.border_color = Color(1.0, 0.85, 0.2, 0.9)
	else:
		style.bg_color = Color(1, 1, 1, 0.07)
		style.border_color = Color(1, 1, 1, 0.18)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
