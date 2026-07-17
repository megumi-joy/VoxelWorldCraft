extends Control
# Bottom hotbar: 9 chunky slots bound to the real Inventory (Scripts/UI/Inventory.gd),
# selected slot driven by number keys / mouse wheel. Bright hypercasual style:
# big rounded slots, a colored icon swatch per item (no image assets), a bold
# gold-highlighted selection border.

@onready var grid = $HBoxContainer
var inventory
var slot_selected: int = 0

signal on_slot_selected(item_id)

const COL_SLOT_BG := Color(1.0, 0.97, 0.88, 0.92)
const COL_SLOT_BORDER := Color(0.16, 0.09, 0.04, 0.9)
const COL_SLOT_SELECTED_BG := Color(1.0, 0.93, 0.55, 0.98)
const COL_SLOT_SELECTED_BORDER := Color(1.0, 0.75, 0.05, 1.0)

func _ready():
	grid.add_theme_constant_override("separation", 10)
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

func update_ui():
	if not inventory: return

	# Clear existing
	for child in grid.get_children():
		child.queue_free()

	_update_gold_label()

	# Build Hotbar (First 9 slots)
	for i in range(9):
		var slot = PanelContainer.new()
		slot.custom_minimum_size = Vector2(64, 64)
		grid.add_child(slot)

		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(14)
		style.set_border_width_all(4)
		style.shadow_color = Color(0, 0, 0, 0.3)
		style.shadow_size = 4
		style.shadow_offset = Vector2(0, 3)

		if i == slot_selected:
			style.bg_color = COL_SLOT_SELECTED_BG
			style.border_color = COL_SLOT_SELECTED_BORDER
			slot.scale = Vector2(1.08, 1.08)
			slot.pivot_offset = Vector2(32, 32)
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
				icon.custom_minimum_size = Vector2(28, 28)
				icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				var icon_style = StyleBoxFlat.new()
				icon_style.bg_color = _item_color(item_data)
				icon_style.set_corner_radius_all(8)
				icon_style.set_border_width_all(2)
				icon_style.border_color = Color(0, 0, 0, 0.35)
				icon.add_theme_stylebox_override("panel", icon_style)
				vbox.add_child(icon)

				var count = Label.new()
				count.text = "x" + str(item.count)
				count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				count.add_theme_font_size_override("font_size", 15)
				count.add_theme_color_override("font_color", Color(0.16, 0.09, 0.04))
				vbox.add_child(count)

		# Slot number badge (1-9), top-left, always visible for chunky readability
		var num = Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", 12)
		num.add_theme_color_override("font_color", Color(0.16, 0.09, 0.04, 0.6))
		num.position = Vector2(4, 2)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(num)

func _update_gold_label() -> void:
	var gold_label = get_node_or_null("GoldLabel")
	if not gold_label:
		gold_label = Label.new()
		gold_label.name = "GoldLabel"
		# HotbarUI's own root is anchored full-width, so center this on the
		# HBoxContainer of slots (which is itself centered) rather than
		# anchoring at x=0 (screen's left edge -- was clipped off-screen).
		gold_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		gold_label.offset_left = -60.0
		gold_label.offset_right = 60.0
		gold_label.offset_top = -42.0
		gold_label.offset_bottom = -16.0
		gold_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gold_label.add_theme_font_size_override("font_size", 20)
		gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		gold_label.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.04))
		gold_label.add_theme_constant_override("outline_size", 5)
		add_child(gold_label)

	var p = get_tree().get_first_node_in_group("player")
	if p and p.has_node("PlayerStats"):
		gold_label.text = "G: " + str(p.get_node("PlayerStats").gold)
	else:
		gold_label.text = "G: 0"

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
		_: return Color(0.65, 0.45, 0.85) # fallback (misc)
