extends Control

# Grid UI for a placed ChestBlock: shows the chest's own slots on top and the
# player's Inventory below, click-to-transfer between the two. Modeled on
# FurnaceUI.gd (set_x/update_ui/signal-driven refresh) plus InventoryUI.gd's
# slot-grid rendering, but slots are Buttons (not bare Panels) so they can
# be clicked. Ported from voxel-train3 branch commit c618890 (id 71 -> 73,
# see ChestBlock.gd for why).

var chest # : ChestBlock (loose typing, same convention as FurnaceUI's `furnace`)
var player_inventory # : Inventory

@onready var chest_label = $Panel/ChestLabel
@onready var inv_label = $Panel/InvLabel
@onready var chest_grid = $Panel/ChestGrid
@onready var inv_grid = $Panel/InventoryGrid

const SLOT_SIZE := 56.0

# Minecraft-style chrome, same palette as InventoryUI.gd/FurnaceUI.gd --
# opaque dark panel + light border, cream slot squares, so all menus read as
# one consistent set instead of the previous half-transparent look.
const COL_PANEL_BG := Color(0.10, 0.07, 0.05, 1.0)
const COL_PANEL_BORDER := Color(0.85, 0.78, 0.62, 0.95)
const COL_SLOT_BG := Color(1.0, 0.97, 0.88, 0.92)
const COL_SLOT_BORDER := Color(0.16, 0.09, 0.04, 0.9)

func _ready():
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COL_PANEL_BG
	panel_style.set_corner_radius_all(10)
	panel_style.set_border_width_all(4)
	panel_style.border_color = COL_PANEL_BORDER
	panel_style.shadow_color = Color(0, 0, 0, 0.4)
	panel_style.shadow_size = 12
	$Panel.add_theme_stylebox_override("panel", panel_style)

	if chest_label:
		chest_label.add_theme_font_size_override("font_size", 20)
		chest_label.add_theme_color_override("font_color", COL_PANEL_BORDER)
	if inv_label:
		inv_label.add_theme_font_size_override("font_size", 18)

func _style_slot(button: Button) -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(3)
	style.bg_color = COL_SLOT_BG
	style.border_color = COL_SLOT_BORDER
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)

func set_chest(c):
	if chest and chest.chest_updated.is_connected(update_ui):
		chest.chest_updated.disconnect(update_ui)

	chest = c
	chest.chest_updated.connect(update_ui)

	if not player_inventory:
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_node("Inventory"):
			player_inventory = player.get_node("Inventory")
			player_inventory.inventory_changed.connect(update_ui)

	update_ui()

func update_ui():
	if not chest:
		return
	_rebuild_grid(chest_grid, chest.slots, ChestBlock.SIZE, _on_chest_slot_pressed)
	if player_inventory:
		_rebuild_grid(inv_grid, player_inventory.items, player_inventory.size, _on_inv_slot_pressed)

func _rebuild_grid(grid: GridContainer, items: Array, size: int, callback: Callable):
	for child in grid.get_children():
		child.queue_free()

	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)

	var db = get_node_or_null("/root/ItemDatabase")
	for i in range(size):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		_style_slot(btn)

		var item = items[i]
		var item_data = db.get_item(item.id) if (item and db) else null
		ItemIcon.populate_slot(btn, item_data, item.count if item else 0, SLOT_SIZE)

		btn.pressed.connect(callback.bind(i))
		grid.add_child(btn)

# Click a chest slot: move that whole stack into the player's inventory.
func _on_chest_slot_pressed(i: int):
	if not chest or not player_inventory:
		return

	var item = chest.slots[i]
	if not item:
		return

	if player_inventory.add_item(item.id, item.count):
		chest.remove_slot(i)

	update_ui()

# Click a player-inventory slot: move that whole stack into the chest.
func _on_inv_slot_pressed(i: int):
	if not chest or not player_inventory:
		return

	var item = player_inventory.items[i]
	if not item:
		return

	if chest.add_item(item.id, item.count):
		player_inventory.remove_item(item.id, item.count)

	update_ui()
