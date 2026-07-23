extends Control

# Grid UI for a placed ChestBlock: shows the chest's own slots on top and the
# player's Inventory below, click-to-transfer between the two. Modeled on
# FurnaceUI.gd (set_x/update_ui/signal-driven refresh) plus InventoryUI.gd's
# slot-grid rendering, but slots are Buttons (not bare Panels) so they can
# be clicked. Ported from voxel-train3 branch commit c618890 (id 71 -> 73,
# see ChestBlock.gd for why).

var chest # : ChestBlock (loose typing, same convention as FurnaceUI's `furnace`)
var player_inventory # : Inventory

@onready var chest_grid = $Panel/ChestGrid
@onready var inv_grid = $Panel/InventoryGrid

const SLOT_SIZE := 56.0

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
		ItemIcon.apply_slot_style(btn)

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
