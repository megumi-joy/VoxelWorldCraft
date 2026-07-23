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

# The 3 fixed slots (Input/Fuel/Output) are 60x60 in the .tscn; the player-
# inventory grid below is rebuilt every update_ui() at 56 (matches Inventory/
# ChestUI's grid math -- 8 columns * 56 + 7 * 6px separation = 490, exactly
# the InventoryGrid rect width already reserved in FurnaceUI.tscn). Two
# constants instead of one so the grid keeps fitting inside the panel.
const SLOT_SIZE := 60.0
const GRID_SLOT_SIZE := 56.0

# Minecraft-style chrome, same palette as InventoryUI.gd/ChestUI.gd -- opaque
# dark panel + light border, cream slot squares, so all menus read as one
# consistent set instead of the previous half-transparent look.
const COL_PANEL_BG := Color(0.10, 0.07, 0.05, 1.0)
const COL_PANEL_BORDER := Color(0.85, 0.78, 0.62, 0.95)
const COL_SLOT_BG := Color(1.0, 0.97, 0.88, 0.92)
const COL_SLOT_BORDER := Color(0.16, 0.09, 0.04, 0.9)
const COL_FLAME_FILL := Color(1.0, 0.45, 0.05, 1.0)
const COL_FLAME_BG := Color(0.15, 0.08, 0.04, 0.9)
const COL_COOK_FILL := Color(0.95, 0.75, 0.15, 1.0)
const COL_COOK_BG := Color(0.15, 0.08, 0.04, 0.9)

func _ready():
	if title_label:
		title_label.text = "Печь"
		title_label.add_theme_font_size_override("font_size", 20)
		title_label.add_theme_color_override("font_color", COL_PANEL_BORDER)
	if input_label:
		input_label.text = "Вход"
	if fuel_label:
		fuel_label.text = "Топливо"
	if output_label:
		output_label.text = "Выход"
	if inv_label:
		inv_label.text = "Инвентарь"

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COL_PANEL_BG
	panel_style.set_corner_radius_all(10)
	panel_style.set_border_width_all(4)
	panel_style.border_color = COL_PANEL_BORDER
	panel_style.shadow_color = Color(0, 0, 0, 0.4)
	panel_style.shadow_size = 12
	$Panel.add_theme_stylebox_override("panel", panel_style)

	# Opaque cream chrome on the 3 fixed slots -- persistent scene nodes (not
	# recreated each update_ui() like the grid buttons below), so the style
	# only needs applying once.
	_style_fixed_slot(input_slot)
	_style_fixed_slot(fuel_slot)
	_style_fixed_slot(output_slot)

	_style_burn_bar()

	input_slot.pressed.connect(_on_furnace_slot_pressed.bind(0))
	fuel_slot.pressed.connect(_on_furnace_slot_pressed.bind(1))
	output_slot.pressed.connect(_on_furnace_slot_pressed.bind(2))

func _style_fixed_slot(slot: Button) -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(3)
	style.bg_color = COL_SLOT_BG
	style.border_color = COL_SLOT_BORDER
	for state in ["normal", "hover", "pressed", "focus"]:
		slot.add_theme_stylebox_override(state, style)

# BurnBar (fuel level, rotated vertical) and CookBar (smelt progress, between
# Вход and Выход) get an explicit flame-colored fill instead of the plain
# default ProgressBar look -- this pair IS the furnace's smelting/flame
# indicator, filling as fuel burns and the item cooks.
func _style_burn_bar() -> void:
	var flame_bg := StyleBoxFlat.new()
	flame_bg.bg_color = COL_FLAME_BG
	flame_bg.set_corner_radius_all(4)
	var flame_fill := StyleBoxFlat.new()
	flame_fill.bg_color = COL_FLAME_FILL
	flame_fill.set_corner_radius_all(4)
	burn_bar.add_theme_stylebox_override("background", flame_bg)
	burn_bar.add_theme_stylebox_override("fill", flame_fill)

	var cook_bg := StyleBoxFlat.new()
	cook_bg.bg_color = COL_COOK_BG
	cook_bg.set_corner_radius_all(4)
	var cook_fill := StyleBoxFlat.new()
	cook_fill.bg_color = COL_COOK_FILL
	cook_fill.set_corner_radius_all(4)
	cook_bar.add_theme_stylebox_override("background", cook_bg)
	cook_bar.add_theme_stylebox_override("fill", cook_fill)

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
		btn.custom_minimum_size = Vector2(GRID_SLOT_SIZE, GRID_SLOT_SIZE)
		_style_fixed_slot(btn)

		var item = player_inventory.items[i]
		var item_data = db.get_item(item.id) if (item and db) else null
		ItemIcon.populate_slot(btn, item_data, item.count if item else 0, GRID_SLOT_SIZE)

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
