extends Node
## Headless verification driver for the new tiered Tools / Food+hunger /
## expanded Crafting+Furnace recipes (owner ask: "fill the game with usable
## items"). Drives the REAL production code paths -- CraftingUI.on_craft(),
## PlayerStats.eat(), Player.get_break_speed()/_process_mining(), and the
## real FurnaceBlock/FurnaceUI -- the same instances/functions a human
## playing the game goes through, not a re-implementation of their logic.
## Modeled on Scripts/Testing/MenusDemoDriver.gd (same _assert/_shot/_count_of
## helper shape).
##
## Exercises, in order:
##   1. Crafting: gives the player Stone + Sticks, crafts a Stone Pickaxe
##      (ID 87) through the real CraftingUI.on_craft() path. Asserts it
##      appears in inventory and the ingredients were consumed.
##   2. Mining speed: places three throwaway Stone blocks at fixed world
##      coordinates and calls the REAL Player._process_mining() repeatedly
##      (same function manual_interaction_check() drives every physics
##      frame while LMB is held) once per tool -- bare hand, Stone Pickaxe,
##      Iron Pickaxe -- counting ticks until each block actually breaks.
##      Asserts hand > stone > iron (tier speeds the real hold-to-mine timer).
##   3. Food/hunger: drains hunger, then calls the same stats.eat(nutrition)
##      call manual_interaction_check()'s "Handle Consumables" branch makes,
##      for both Raw Meat (94) and Cooked Meat (95). Asserts hunger rises by
##      exactly each item's nutrition_value.
##   4. Furnace smelting: places a real FurnaceBlock, opens it via
##      entity.interact(player) (the exact right-click path), loads Wood
##      (fuel) + Raw Meat (input) through FurnaceUI's real click handler,
##      waits out a real smelt tick, asserts Cooked Meat output appeared.
##
## Only active with --items-demo (see Scripts/Tools/LaunchTest.gd).

const STONE_ID := 3
const STICKS_ID := 23
const STONE_PICKAXE_ID := 87
const IRON_PICKAXE_ID := 91
const WOOD_ID := 4
const RAW_MEAT_ID := 94
const COOKED_MEAT_ID := 95

var player: CharacterBody3D = null
var voxel_world: Node = null
var inventory = null
var crafting_ui: Control = null
var furnace_ui: Control = null

var _all_passed := true

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--items-demo"):
		queue_free()
		return
	print("[ItemsDemo] driver active")
	_find_player()

func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if not player:
		await get_tree().create_timer(0.2).timeout
		_find_player()
		return
	player.ai_enabled = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	voxel_world = get_node_or_null("/root/World/VoxelWorld")
	inventory = player.get_node("Inventory")
	crafting_ui = player.get_node("HUD/CraftingUI")
	furnace_ui = player.get_node("HUD/FurnaceUI")
	print("[ItemsDemo] player found, voxel_world=", voxel_world != null)

	_assert("nodes_resolved",
		inventory != null and crafting_ui != null and furnace_ui != null and voxel_world != null,
		"inventory/crafting_ui/furnace_ui/voxel_world all resolved")
	_run_sequence()

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_all_passed = false
	var status = "PASS" if cond else "FAIL"
	print("[ItemsDemo] ASSERT ", name, ": ", status, (" -- " + detail) if detail != "" else "")
	if get_node_or_null("/root/Telemetry"):
		Telemetry.log_event("items_demo_assert", {"name": name, "passed": cond, "detail": detail})

func _count_of(inv, id: int) -> int:
	var total = 0
	for item in inv.items:
		if item and item.id == id:
			total += item.count
	return total

func _run_sequence() -> void:
	await _test_crafting_stone_pickaxe()
	await _test_mining_speed()
	await _test_food_hunger()
	await _test_furnace_smelt()

	print("[ItemsDemo] SUMMARY all_passed=", _all_passed)
	if get_node_or_null("/root/Telemetry"):
		Telemetry.log_event("items_demo_summary", {"all_passed": _all_passed})
	await get_tree().create_timer(0.3).timeout
	print("[ItemsDemo] done, quitting")
	get_tree().quit()

# ---------------------------------------------------------------------------
# 1. Crafting: Stone Pickaxe
# ---------------------------------------------------------------------------
func _test_crafting_stone_pickaxe() -> void:
	print("[ItemsDemo] --- Crafting: Stone Pickaxe ---")
	crafting_ui.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var waited := 0.0
	while crafting_ui.inventory == null and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_assert("crafting_inventory_wired", crafting_ui.inventory != null)

	inventory.add_item(STONE_ID, 2)
	inventory.add_item(STICKS_ID, 1)

	var recipe_index := -1
	for i in range(crafting_ui.crafting_manager.recipes.size()):
		var recipe = crafting_ui.crafting_manager.recipes[i]
		if recipe.output.id == STONE_PICKAXE_ID:
			recipe_index = i
			break
	_assert("stone_pickaxe_recipe_exists", recipe_index >= 0, "index=" + str(recipe_index))
	if recipe_index < 0:
		return

	var stone_before = _count_of(inventory, STONE_ID)
	var sticks_before = _count_of(inventory, STICKS_ID)
	var pickaxe_before = _count_of(inventory, STONE_PICKAXE_ID)

	crafting_ui.update_ui()
	crafting_ui.on_craft(recipe_index)

	var pickaxe_after = _count_of(inventory, STONE_PICKAXE_ID)
	print("[ItemsDemo] stone_pickaxe: ", pickaxe_before, " -> ", pickaxe_after,
		" stone=", stone_before, "->", _count_of(inventory, STONE_ID),
		" sticks=", sticks_before, "->", _count_of(inventory, STICKS_ID))
	_assert("stone_pickaxe_crafted", pickaxe_after == pickaxe_before + 1)
	_assert("stone_pickaxe_ingredients_consumed",
		_count_of(inventory, STONE_ID) == stone_before - 2 and _count_of(inventory, STICKS_ID) == sticks_before - 1)

	crafting_ui.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ---------------------------------------------------------------------------
# 2. Mining speed: bare hand vs Stone Pickaxe vs Iron Pickaxe on Stone
# ---------------------------------------------------------------------------
## Drives the REAL Player._process_mining() in a tight synthetic tick loop
## (fixed 1/60s steps, no real-world wait) against a Stone block placed at
## `cell`, with `tool_item_id` selected -- exactly the function
## manual_interaction_check() calls every physics frame LMB is held, just
## ticked manually here instead of over real wall-clock frames. Returns
## seconds-to-break. Resets the player's mining-progress state before/after
## so each measurement starts clean.
func _measure_mine_time(cell: Vector3i, tool_item_id: int) -> float:
	voxel_world.set_voxel(Vector3(cell) + Vector3(0.5, 0.5, 0.5), STONE_ID)
	player.selected_block_id = tool_item_id
	player._mining_block = Vector3i(-99999, -99999, -99999)
	player._mining_progress = 0.0
	player._mining_blocked = false
	player._mining_target_hysteresis = 0.0

	var point := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var normal := Vector3.UP
	var fixed_delta := 1.0 / 60.0
	var elapsed := 0.0
	var ticks := 0
	while player.get_block_at(voxel_world, point - normal * 0.1) != 0 and ticks < 3600:
		player._process_mining(fixed_delta, voxel_world, point, normal)
		elapsed += fixed_delta
		ticks += 1
	return elapsed

func _test_mining_speed() -> void:
	print("[ItemsDemo] --- Mining speed: hand vs Stone Pickaxe vs Iron Pickaxe ---")
	inventory.add_item(IRON_PICKAXE_ID, 1) # not craftable in this driver's scope -- granted directly to isolate the speed measurement

	var hand_time = _measure_mine_time(Vector3i(0, 210, 0), 0) # 0 = empty hand
	var stone_pick_time = _measure_mine_time(Vector3i(2, 210, 0), STONE_PICKAXE_ID)
	var iron_pick_time = _measure_mine_time(Vector3i(4, 210, 0), IRON_PICKAXE_ID)

	print("[ItemsDemo] mine_time seconds: hand=", String.num(hand_time, 3),
		" stone_pickaxe=", String.num(stone_pick_time, 3),
		" iron_pickaxe=", String.num(iron_pick_time, 3))
	_assert("stone_pickaxe_faster_than_hand", stone_pick_time < hand_time,
		"stone=" + String.num(stone_pick_time, 3) + " hand=" + String.num(hand_time, 3))
	_assert("iron_pickaxe_faster_than_stone", iron_pick_time < stone_pick_time,
		"iron=" + String.num(iron_pick_time, 3) + " stone=" + String.num(stone_pick_time, 3))

	player.selected_block_id = 1 # restore default (Dirt)

# ---------------------------------------------------------------------------
# 3. Food + hunger
# ---------------------------------------------------------------------------
func _test_food_hunger() -> void:
	print("[ItemsDemo] --- Food/Hunger: Raw Meat + Cooked Meat ---")
	if not player.stats:
		_assert("stats_available", false, "player.stats is null -- no hunger system to test")
		return

	inventory.add_item(RAW_MEAT_ID, 2)
	inventory.add_item(COOKED_MEAT_ID, 1)

	# Drain hunger first so eating has visible room to raise it (matches
	# the real starvation-decay range, see PlayerStats.gd).
	player.stats.hunger = 20.0
	player.stats.emit_stats()

	var raw_meat_item = ItemDatabase.get_item(RAW_MEAT_ID)
	var hunger_before_raw = player.stats.hunger
	player.stats.eat(raw_meat_item.nutrition_value) # same call manual_interaction_check() makes
	inventory.remove_item(RAW_MEAT_ID, 1)
	var hunger_after_raw = player.stats.hunger
	print("[ItemsDemo] raw meat: hunger ", hunger_before_raw, " -> ", hunger_after_raw,
		" (nutrition=", raw_meat_item.nutrition_value, ")")
	_assert("raw_meat_restores_hunger",
		abs((hunger_after_raw - hunger_before_raw) - raw_meat_item.nutrition_value) < 0.01,
		"delta=" + str(hunger_after_raw - hunger_before_raw))

	var cooked_meat_item = ItemDatabase.get_item(COOKED_MEAT_ID)
	var hunger_before_cooked = player.stats.hunger
	player.stats.eat(cooked_meat_item.nutrition_value)
	inventory.remove_item(COOKED_MEAT_ID, 1)
	var hunger_after_cooked = player.stats.hunger
	print("[ItemsDemo] cooked meat: hunger ", hunger_before_cooked, " -> ", hunger_after_cooked,
		" (nutrition=", cooked_meat_item.nutrition_value, ")")
	_assert("cooked_meat_restores_hunger",
		abs((hunger_after_cooked - hunger_before_cooked) - cooked_meat_item.nutrition_value) < 0.01,
		"delta=" + str(hunger_after_cooked - hunger_before_cooked))
	_assert("cooked_meat_better_than_raw", cooked_meat_item.nutrition_value > raw_meat_item.nutrition_value,
		"cooked=" + str(cooked_meat_item.nutrition_value) + " raw=" + str(raw_meat_item.nutrition_value))

# ---------------------------------------------------------------------------
# 4. Furnace: Raw Meat -> Cooked Meat
# ---------------------------------------------------------------------------
func _test_furnace_smelt() -> void:
	print("[ItemsDemo] --- Furnace: Raw Meat -> Cooked Meat ---")
	var pos := Vector3i(6, 210, 0)
	voxel_world.set_voxel(Vector3(pos) + Vector3(0.5, 0.5, 0.5), 8) # 8 = Furnace
	var entity = voxel_world.get_block_entity(pos)
	_assert("furnace_entity_spawned", entity != null)
	if not entity:
		return

	entity.interact(player)
	_assert("furnace_ui_opened", furnace_ui.visible and furnace_ui.furnace == entity)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	inventory.add_item(WOOD_ID, 2)
	inventory.add_item(RAW_MEAT_ID, 2)
	var wood_idx = -1
	var meat_idx = -1
	for i in range(inventory.size):
		if inventory.items[i] and inventory.items[i].id == WOOD_ID: wood_idx = i
		if inventory.items[i] and inventory.items[i].id == RAW_MEAT_ID: meat_idx = i
	_assert("furnace_load_setup", wood_idx >= 0 and meat_idx >= 0,
		"wood_idx=" + str(wood_idx) + " meat_idx=" + str(meat_idx))

	furnace_ui._on_inv_slot_pressed(wood_idx)
	# Re-find Raw Meat's slot -- removing the wood stack can shift indices.
	meat_idx = -1
	for i in range(inventory.size):
		if inventory.items[i] and inventory.items[i].id == RAW_MEAT_ID: meat_idx = i
	furnace_ui._on_inv_slot_pressed(meat_idx)

	_assert("furnace_fuel_loaded", entity.inventory[1] != null and entity.inventory[1].id == WOOD_ID)
	_assert("furnace_input_loaded", entity.inventory[0] != null and entity.inventory[0].id == RAW_MEAT_ID)

	print("[ItemsDemo] waiting for smelt tick...")
	await get_tree().create_timer(6.5).timeout

	print("[ItemsDemo] furnace state: input=", entity.inventory[0],
		" fuel=", entity.inventory[1], " output=", entity.inventory[2])
	_assert("furnace_cooked_meat_produced",
		entity.inventory[2] != null and entity.inventory[2].id == COOKED_MEAT_ID and entity.inventory[2].count >= 1,
		str(entity.inventory[2]))

	furnace_ui.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
