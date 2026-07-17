extends Control
# Bottom hotbar: 9 chunky slots bound to the real Inventory (Scripts/UI/Inventory.gd),
# selected slot driven by number keys / mouse wheel. Bright hypercasual style:
# rounded slots, a colored icon swatch per item (no image assets), a bold
# gold-highlighted selection border.
#
# Slot size is computed at runtime from the viewport width (see
# _compute_slot_size()), not a fixed constant -- a size that reads as
# comfortably "readable, ~1.5-2x bigger" on a wide landscape/desktop frame
# would overflow off the sides of a narrow portrait-phone frame if fixed in
# pixels (9 slots at that scale is wider than a phone). Scaling with the
# viewport keeps the row within a fixed fraction of the screen width in both
# orientations while still growing on wider frames where there's room --
# project.godot's canvas_items stretch keeps this consistent across render
# resolutions.
const MAX_ROW_WIDTH_FRACTION := 0.92
const SEPARATION := 10.0
const MIN_SLOT_SIZE := 40.0
const MAX_SLOT_SIZE := 68.0

@onready var grid = $HBoxContainer
var inventory
var slot_selected: int = 0
var _slot_size: float = MAX_SLOT_SIZE

signal on_slot_selected(item_id)

const COL_SLOT_BG := Color(1.0, 0.97, 0.88, 0.92)
const COL_SLOT_BORDER := Color(0.16, 0.09, 0.04, 0.9)
const COL_SLOT_SELECTED_BG := Color(1.0, 0.93, 0.55, 0.98)
const COL_SLOT_SELECTED_BORDER := Color(1.0, 0.75, 0.05, 1.0)

func _ready():
	grid.add_theme_constant_override("separation", SEPARATION)
	set_process_input(true)

	# HotbarUI is a grandchild of Player (Player/HUD/HotbarUI). Godot calls
	# _ready() bottom-up (children before parent), but Player.gd only calls
	# add_to_group("player") inside its OWN _ready() -- so looking up the
	# "player" group right here, synchronously, always misses (Player hasn't
	# joined the group yet) and the hotbar silently never populates. Deferring
	# one idle-frame tick runs this after the whole Player._ready() cascade
	# has completed, once Player is actually in the group.
	call_deferred("_find_inventory")

func _find_inventory():
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_node("Inventory"):
		inventory = player.get_node("Inventory")
		inventory.inventory_changed.connect(update_ui)

		# Connect to stats for gold
		if player.has_node("PlayerStats"):
			player.get_node("PlayerStats").gold_changed.connect(func(_val): update_ui())

		update_ui()

func _input(event):
	if event is InputEventKey:
		if event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			slot_selected = event.keycode - KEY_1
			update_selection()

	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				slot_selected = (slot_selected - 1 + 9) % 9
				update_selection()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				slot_selected = (slot_selected + 1) % 9
				update_selection()

func update_selection():
	# Visual update
	update_ui()
	# Notify player logic
	if inventory and inventory.items.size() > slot_selected:
		var item = inventory.items[slot_selected]
		if item:
			on_slot_selected.emit(item.id)
		else:
			on_slot_selected.emit(0) # 0 = Empty

func _compute_slot_size() -> float:
	var viewport_w = get_viewport_rect().size.x
	if viewport_w <= 0:
		return MAX_SLOT_SIZE
	var max_row_w = viewport_w * MAX_ROW_WIDTH_FRACTION
	var raw = (max_row_w - SEPARATION * 8.0) / 9.0
	return clamp(raw, MIN_SLOT_SIZE, MAX_SLOT_SIZE)

# Repositions the centered slot row and the root's reserved bottom band to
# fit `_slot_size` -- done in code (not fixed .tscn offsets) since the size
# itself is runtime-computed from the viewport (see _compute_slot_size()).
func _layout_for_slot_size() -> void:
	var row_w = _slot_size * 9.0 + SEPARATION * 8.0
	grid.offset_left = -row_w / 2.0
	grid.offset_right = row_w / 2.0
	grid.offset_top = -(_slot_size + 10.0)

	offset_top = -(_slot_size + 34.0) # HotbarUI root's own reserved band

func update_ui():
	if not inventory: return

	_slot_size = _compute_slot_size()
	_layout_for_slot_size()

	# Clear existing
	for child in grid.get_children():
		child.queue_free()

	_update_gold_label()

	# Build Hotbar (First 9 slots)
	for i in range(9):
		var slot = PanelContainer.new()
		slot.custom_minimum_size = Vector2(_slot_size, _slot_size)
		grid.add_child(slot)

		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.set_border_width_all(3)
		style.shadow_color = Color(0, 0, 0, 0.3)
		style.shadow_size = 3
		style.shadow_offset = Vector2(0, 2)

		if i == slot_selected:
			style.bg_color = COL_SLOT_SELECTED_BG
			style.border_color = COL_SLOT_SELECTED_BORDER
			slot.scale = Vector2(1.08, 1.08)
			slot.pivot_offset = Vector2(_slot_size / 2.0, _slot_size / 2.0)
		else:
			style.bg_color = COL_SLOT_BG
			style.border_color = COL_SLOT_BORDER

		slot.add_theme_stylebox_override("panel", style)

		# PanelContainer force-fills every direct child to its content rect,
		# so give it a single plain Control child and free-position the icon
		# stack + slot-number badge inside that instead.
		var content = Control.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(content)

		var item_data = null
		if i < inventory.size and inventory.items[i]:
			var item = inventory.items[i]
			var db = get_node_or_null("/root/ItemDatabase")
			if db:
				item_data = db.get_item(item.id)

			if item_data:
				var vbox = VBoxContainer.new()
				vbox.alignment = BoxContainer.ALIGNMENT_CENTER
				vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
				vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
				content.add_child(vbox)

				var icon = PanelContainer.new()
				var icon_size = _slot_size * 0.45
				icon.custom_minimum_size = Vector2(icon_size, icon_size)
				icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				var icon_style = StyleBoxFlat.new()
				icon_style.bg_color = _item_color(item_data)
				icon_style.set_corner_radius_all(6)
				icon_style.set_border_width_all(1)
				icon_style.border_color = Color(0, 0, 0, 0.35)
				icon.add_theme_stylebox_override("panel", icon_style)
				vbox.add_child(icon)

				var count = Label.new()
				count.text = "x" + str(item.count)
				count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				count.add_theme_font_size_override("font_size", int(_slot_size * 0.25))
				count.add_theme_color_override("font_color", Color(0.16, 0.09, 0.04))
				vbox.add_child(count)

		# Slot number badge (1-9), top-left, always visible for chunky readability
		var num = Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", int(_slot_size * 0.22))
		num.add_theme_color_override("font_color", Color(0.16, 0.09, 0.04, 0.6))
		num.position = Vector2(3, 1)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(num)

# A small rounded "coin chip" (icon + count), not a raw "G: 0" text label --
# anchored to the bottom-right corner of HotbarUI's own full-width root,
# independent of the centered slot row, so it stays put in the corner
# regardless of screen aspect (the slot row's fixed content width wouldn't
# reliably have a "space above it" to anchor to in portrait).
func _update_gold_label() -> void:
	var chip = get_node_or_null("GoldChip")
	if not chip:
		chip = PanelContainer.new()
		chip.name = "GoldChip"
		# Stacked ABOVE the hotbar's 60px bottom band (not beside it) so it
		# never collides with the centered slot row even at narrow portrait
		# widths, where the row's fixed content width leaves little side
		# margin to share with a corner element.
		chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		chip.offset_left = -70.0
		chip.offset_right = -14.0
		# Vertical position is re-set every _update_gold_label() call below
		# (coupled to the hotbar's own dynamic band height), these are just
		# placeholder initial values.
		chip.offset_top = -96.0
		chip.offset_bottom = -64.0
		chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var chip_style = StyleBoxFlat.new()
		chip_style.bg_color = Color(1.0, 0.97, 0.88, 0.92)
		chip_style.set_corner_radius_all(10)
		chip_style.set_border_width_all(2)
		chip_style.border_color = Color(0.16, 0.09, 0.04, 0.9)
		chip_style.shadow_color = Color(0, 0, 0, 0.3)
		chip_style.shadow_size = 3
		chip_style.shadow_offset = Vector2(0, 2)
		chip.add_theme_stylebox_override("panel", chip_style)

		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 6)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_top", 4)
		margin.add_theme_constant_override("margin_bottom", 4)
		chip.add_child(margin)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		margin.add_child(row)

		var coin = Control.new()
		coin.name = "CoinIcon"
		coin.custom_minimum_size = Vector2(16, 16)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		coin.set_script(load("res://Scripts/UI/HudStatIcon.gd"))
		coin.icon_type = "coin"
		row.add_child(coin)

		var gold_label = Label.new()
		gold_label.name = "GoldLabel"
		gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gold_label.add_theme_font_size_override("font_size", 14)
		gold_label.add_theme_color_override("font_color", Color(0.16, 0.09, 0.04))
		row.add_child(gold_label)

		add_child(chip)

	# Keep the chip stacked just above the hotbar's own (dynamically sized)
	# reserved band, whatever that band's current height is. offset_top here
	# is negative (distance up from the bottom anchor) -- "above" the band
	# means an even more negative offset, hence the subtraction.
	chip.offset_bottom = offset_top - 8.0
	chip.offset_top = chip.offset_bottom - 36.0

	var gold_label: Label = chip.find_child("GoldLabel", true, false)
	var p = get_tree().get_first_node_in_group("player")
	var gold_amount = 0
	if p and p.has_node("PlayerStats"):
		gold_amount = p.get_node("PlayerStats").gold
	if gold_label:
		gold_label.text = str(gold_amount)

# Flat color swatch standing in for an item icon texture (no image assets in
# the project yet). Grouped roughly by ItemData.type / block_id so related
# items read as similar colors, same idea as the world's block palette.
func _item_color(item_data) -> Color:
	if item_data.type == 1: # TOOL
		return Color(0.55, 0.58, 0.62)
	if item_data.type == 3: # CONSUMABLE
		return Color(0.95, 0.35, 0.25)

	match item_data.block_id:
		1: return Color(0.42, 0.30, 0.18) # Dirt
		2: return Color(0.25, 0.75, 0.28) # Grass
		3: return Color(0.55, 0.55, 0.55) # Stone
		4: return Color(0.55, 0.36, 0.16) # Wood
		5: return Color(0.25, 0.25, 0.25) # Coal Ore
		6: return Color(0.75, 0.65, 0.55) # Iron Ore
		80: return Color(0.85, 0.45, 0.15) # Copper Ore
		81: return Color(1.0, 0.84, 0.0) # Gold Ore
		82: return Color(0.88, 0.88, 0.92) # Quartz
		83: return Color(0.55, 0.2, 0.15) # Hematite
		84: return Color(0.1, 0.55, 0.25) # Malachite Ore
		_: return Color(0.65, 0.45, 0.85) # fallback (misc)
