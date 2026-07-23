extends Control
# Furnace menu: input/fuel/output slots (Furnace.gd owns the actual smelting
# tick -- fuel burn, cook progress, output -- this is purely the UI/transfer
# layer on top of it) plus the player's own inventory grid underneath, click-
# to-transfer both ways. Modeled directly on ChestUI.gd's set_x/update_ui/
# Button-slot pattern, since a furnace is really "a 3-slot chest with a
# built-in timer".

var furnace # : Furnace (loose typing to fix lint)
var player_inventory # : Inventory

@onready var title_label = $Panel/Label
@onready var input_slot: Button = $Panel/InputSlot
@onready var fuel_slot: Button = $Panel/FuelSlot
@onready var output_slot: Button = $Panel/OutputSlot
@onready var burn_bar = $Panel/BurnBar
@onready var cook_bar = $Panel/CookBar
@onready var input_label = $Panel/InputLabel
@onready var fuel_label = $Panel/FuelLabel
@onready var output_label = $Panel/OutputLabel
@onready var inv_label = $Panel/InvLabel
@onready var inv_grid = $Panel/InventoryGrid

const SLOT_SIZE := 60.0

func _ready():
	if title_label:
		title_label.text = "Печь"
	if input_label:
		input_label.text = "Вход"
	if fuel_label:
		fuel_label.text = "Топливо"
	if output_label:
		output_label.text = "Выход"
	if inv_label:
		inv_label.text = "Инвентарь"

	# Rounded HUD-style chrome on the 3 fixed slots (see ItemIcon.gd) -- these
	# are persistent scene nodes (not recreated each update_ui() like the
	# grid buttons below), so the style only needs applying once.
	ItemIcon.apply_slot_style(input_slot)
	ItemIcon.apply_slot_style(fuel_slot)
	ItemIcon.apply_slot_style(output_slot)

	input_slot.pressed.connect(_on_furnace_slot_pressed.bind(0))
	fuel_slot.pressed.connect(_on_furnace_slot_pressed.bind(1))
	output_slot.pressed.connect(_on_furnace_slot_pressed.bind(2))

func set_furnace(f: Node):
	if furnace and furnace.furnace_updated.is_connected(update_ui):
		furnace.furnace_updated.disconnect(update_ui)

	furnace = f
	furnace.furnace_updated.connect(update_ui)

	# No _ready()-time race here (unlike CraftingUI.gd's old bug) -- set_furnace()
	# is only ever called from Furnace.interact(player), well after the player
	# exists and joined the "player" group.
	if not player_inventory:
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_node("Inventory"):
			player_inventory = player.get_node("Inventory")
			player_inventory.inventory_changed.connect(update_ui)

	update_ui()

func _process(_delta):
	if visible and furnace:
		update_bars()

func update_bars():
	if furnace.max_burn_time > 0:
		burn_bar.value = (furnace.burn_time / furnace.max_burn_time) * 100
	else:
		burn_bar.value = 0

	cook_bar.value = (furnace.cook_time / 5.0) * 100

func update_ui():
	if not furnace:
		return
	update_slot_visual(input_slot, furnace.inventory[0])
	update_slot_visual(fuel_slot, furnace.inventory[1])
	update_slot_visual(output_slot, furnace.inventory[2])

	if player_inventory:
		_rebuild_inv_grid()

func update_slot_visual(slot: Button, item):
	var item_data = null
	if item:
		var db = get_node_or_null("/root/ItemDatabase")
		item_data = db.get_item(item.id) if db else null
	ItemIcon.populate_slot(slot, item_data, item.count if item else 0, SLOT_SIZE)

func _rebuild_inv_grid():
	for child in inv_grid.get_children():
		child.queue_free()

	inv_grid.add_theme_constant_override("h_separation", 6)
	inv_grid.add_theme_constant_override("v_separation", 6)

	var db = get_node_or_null("/root/ItemDatabase")
	for i in range(player_inventory.size):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		ItemIcon.apply_slot_style(btn)

		var item = player_inventory.items[i]
		var item_data = db.get_item(item.id) if (item and db) else null
		ItemIcon.populate_slot(btn, item_data, item.count if item else 0, SLOT_SIZE)

		btn.pressed.connect(_on_inv_slot_pressed.bind(i))
		inv_grid.add_child(btn)

# Click a player-inventory slot: route the whole stack into the furnace.
# Fuel-capable items (Furnace.get_fuel_time > 0, e.g. Wood/Coal Ore) go to the
# fuel slot; smeltable items (Furnace.get_smelting_result != 0, e.g. Raw
# Iron/Gold Ore/Copper Ore) go to the input slot. No current item is both, so
# the routing is unambiguous (see Furnace.gd's get_fuel_time/get_smelting_result).
# Anything else (a sword, dirt, ...) is simply not accepted -- nothing happens.
func _on_inv_slot_pressed(i: int) -> void:
	if not furnace or not player_inventory:
		return

	var item = player_inventory.items[i]
	if not item:
		return

	var target_index = -1
	if furnace.get_fuel_time(item.id) > 0:
		target_index = 1
	elif furnace.get_smelting_result(item.id) != 0:
		target_index = 0
	else:
		return # Not fuel, not smeltable -- furnace has no use for this item.

	if _furnace_slot_accept(target_index, item.id, item.count):
		player_inventory.remove_item(item.id, item.count)

	update_ui()
	furnace.furnace_updated.emit()

# Merge/insert `count` of `id` into furnace.inventory[slot_index], same
# stack-then-empty-slot rule as Inventory.add_item()/ChestBlock.add_item().
# Furnace slots are fixed to a single item (no "search all slots"), so this
# only ever touches the one slot_index passed in.
func _furnace_slot_accept(slot_index: int, id: int, count: int) -> bool:
	var slot = furnace.inventory[slot_index]
	if slot == null:
		furnace.inventory[slot_index] = {"id": id, "count": count}
		return true
	if slot.id == id and slot.count < 64:
		var space = 64 - slot.count
		var to_add = min(count, space)
		slot.count += to_add
		return to_add == count
	return false

# Click a furnace slot (input/fuel/output): move its whole stack back into the
# player's inventory.
func _on_furnace_slot_pressed(slot_index: int) -> void:
	if not furnace or not player_inventory:
		return

	var item = furnace.inventory[slot_index]
	if not item:
		return

	if player_inventory.add_item(item.id, item.count):
		furnace.inventory[slot_index] = null

	update_ui()
	furnace.furnace_updated.emit()
