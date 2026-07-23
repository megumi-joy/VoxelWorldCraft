extends Node
## Headless verification driver for the 4 UI menus (Inventory/Crafting/
## Furnace/Chest) the owner asked to have "доделать" (finished). Drives the
## REAL shipped nodes under the player's HUD -- InventoryUI/CraftingUI/
## FurnaceUI/ChestUI, the same instances a human clicks -- rather than the
## underlying model classes directly, so a pass here proves the UI/wiring
## layer works, not just that Inventory.gd/CraftingManager.gd/Furnace.gd/
## ChestBlock.gd are individually correct in isolation.
##
## Exercises, in order:
##   1. Crafting: waits for CraftingUI.inventory to wire up (proves the
##      _ready()-race fix -- see CraftingUI.gd), then crafts Wood -> Planks by
##      driving the real 3x3-grid + recipe-book UI path (select the recipe,
##      then "click" the result slot), which ends up calling on_craft()/
##      CraftingManager.craft() the same as a human would. Asserts the grid
##      shows the recipe, Planks appeared, and Wood was consumed.
##   2. Inventory: adds a marker item, then drives InventoryUI's real
##      click-to-pick-up/click-to-place handler (_on_slot_pressed) to move it
##      from one slot to another. Asserts the move landed and the source is
##      empty.
##   3. Furnace: places a real FurnaceBlock in the world, opens it via
##      entity.interact(player) (the exact code path a right-click uses),
##      loads fuel (Wood) + input (Raw Iron) through FurnaceUI's real
##      inventory-slot click handler, waits out a real smelt tick (fuel
##      consumed then COOK_DURATION seconds of cooking), asserts Iron Ingot
##      output appeared + fuel/input decremented, then extracts the output
##      back to the player's inventory via the output slot's click handler.
##   4. Chest: places a real ChestBlock (prepopulated per ChestBlock.gd),
##      opens it via entity.interact(player), moves a marker item from
##      player inventory into the chest, "reopens" it (calls set_chest again
##      on the same still-alive block-entity instance -- exactly what
##      happens if a player walks away and back) to prove per-chest
##      persistence, then moves an existing chest item back to the player.
##
## Only active with --menus-demo (see Scripts/Tools/LaunchTest.gd). Optional
## --menus-shot-dir=<dir> saves one screenshot per open menu (inventory.png,
## crafting.png, furnace.png, chest.png) for owner-facing visual proof, same
## "wait a few frames then get_viewport().get_texture().get_image().save_png()"
## pattern GraphicsSettingsDriver.gd/HudScaleDriver.gd already use.

const WOOD_ID := 4
const RAW_IRON_ID := 62
const IRON_INGOT_ID := 63
const INV_MARKER_ID := 66 # Amethyst Shard -- not in anyone's starter kit, safe marker
const PLANKS_ID := 13

var player: CharacterBody3D = null
var voxel_world: Node = null
var inventory = null
var inventory_ui: Control = null
var crafting_ui: Control = null
var furnace_ui: Control = null
var chest_ui: Control = null

var _shot_dir := ""
var _all_passed := true

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--menus-demo"):
		queue_free()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menus-shot-dir="):
			_shot_dir = a.split("=")[1]
	print("[MenusDemo] driver active, shot_dir=", _shot_dir)
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
	inventory_ui = player.get_node("HUD/InventoryUI")
	crafting_ui = player.get_node("HUD/CraftingUI")
	furnace_ui = player.get_node("HUD/FurnaceUI")
	chest_ui = player.get_node("HUD/ChestUI")
	print("[MenusDemo] player found, voxel_world=", voxel_world != null)

	# Wait for chunk loading to finish (same signal ShowcaseDemoDriver.gd
	# waits on) before opening any menu -- purely cosmetic, so screenshots
	# show the menu instead of the LoadingScreen overlay sitting on top of
	# it. Only bother when actually capturing screenshots (--menus-shot-dir):
	# waiting for the full ~81-chunk load adds real wall-clock time and (on
	# this engine build) a burst of "mesh_get_surface_count" noise during
	# process teardown at quit -- harmless, but it drowns out the assertion
	# log in a `tail -N` capture. The plain assertion run doesn't need
	# clean visuals, so skip the wait there and quit fast.
	var already_loaded = voxel_world and ("initial_load_done" in voxel_world) and voxel_world.initial_load_done
	if _shot_dir != "" and voxel_world and voxel_world.has_signal("initial_load_complete") and not already_loaded:
		print("[MenusDemo] waiting for world load...")
		await voxel_world.initial_load_complete
		print("[MenusDemo] world load complete")

	_assert("nodes_resolved",
		inventory != null and inventory_ui != null and crafting_ui != null
		and furnace_ui != null and chest_ui != null,
		"all 4 menu UI nodes + player Inventory resolved")
	_run_sequence()

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_all_passed = false
	var status = "PASS" if cond else "FAIL"
	print("[MenusDemo] ASSERT ", name, ": ", status, (" -- " + detail) if detail != "" else "")
	if get_node_or_null("/root/Telemetry"):
		Telemetry.log_event("menus_demo_assert", {"name": name, "passed": cond, "detail": detail})

func _find_slot(inv, id: int) -> int:
	for i in range(inv.size):
		if inv.items[i] and inv.items[i].id == id:
			return i
	return -1

func _find_empty_slot(inv) -> int:
	for i in range(inv.size):
		if inv.items[i] == null:
			return i
	return -1

func _count_of(inv, id: int) -> int:
	var total = 0
	for item in inv.items:
		if item and item.id == id:
			total += item.count
	return total

func _shot(name: String) -> void:
	if _shot_dir == "":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	# Under --headless there is no viewport texture to grab (get_image()
	# returns null) -- only meaningful when this driver runs under a real
	# (even virtual/Xvfb) display. Skip quietly rather than SCRIPT ERROR so
	# the plain --headless verification run (the one that matters for
	# assertions) stays clean.
	var tex := get_viewport().get_texture()
	var img := tex.get_image() if tex else null
	if not img:
		print("[MenusDemo] shot skipped (no viewport texture -- headless render): ", name)
		return
	var path := _shot_dir.trim_suffix("/") + "/" + name + ".png"
	var err := img.save_png(path)
	print("[MenusDemo] shot ", path, " err=", err)

func _run_sequence() -> void:
	await _test_crafting()
	await _test_inventory()
	await _test_furnace()
	await _test_chest()

	inventory_ui.visible = false
	crafting_ui.visible = false
	furnace_ui.visible = false
	chest_ui.visible = false

	print("[MenusDemo] SUMMARY all_passed=", _all_passed)
	if get_node_or_null("/root/Telemetry"):
		Telemetry.log_event("menus_demo_summary", {"all_passed": _all_passed})
	await get_tree().create_timer(0.3).timeout
	print("[MenusDemo] done, quitting")
	get_tree().quit()

# ---------------------------------------------------------------------------
# 1. Crafting
# ---------------------------------------------------------------------------
func _test_crafting() -> void:
	print("[MenusDemo] --- Crafting ---")
	crafting_ui.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# CraftingUI._wire_inventory_deferred() retries across frames -- wait for
	# it (up to ~3s) rather than assuming it's already wired. A non-null
	# `inventory` here is the actual proof the _ready()-race fix took; if the
	# old one-shot lookup regressed, this would time out with inventory==null
	# and craft() below would silently no-op (see CraftingUI.gd's old bug).
	var waited := 0.0
	while crafting_ui.inventory == null and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_assert("crafting_inventory_wired", crafting_ui.inventory != null,
		"waited " + String.num(waited, 2) + "s")

	var wood_before = _count_of(inventory, WOOD_ID)
	var planks_before = _count_of(inventory, PLANKS_ID)
	print("[MenusDemo] before craft: wood=", wood_before, " planks=", planks_before)

	crafting_ui.update_ui()
	# Recipe 0 is Wood(1) -> Planks(4), first one CraftingManager.gd appends.
	# Drive the real 3x3-grid + recipe-book UI path (see CraftingUI.gd) rather
	# than calling on_craft() directly: select the recipe like a book-row
	# click would (lays Wood into the crafting grid, Planks into the result
	# slot), assert the grid/result actually reflect it, then "click" the
	# result slot -- which is what finally calls on_craft()/craft() under the
	# hood, so this still exercises the same CraftingManager path the
	# assertions below depend on.
	crafting_ui._on_recipe_selected(0)
	_assert("crafting_grid_shows_recipe", crafting_ui.selected_recipe == 0,
		"selected_recipe=" + str(crafting_ui.selected_recipe))
	_assert("crafting_grid_populated", crafting_ui.craft_slot_buttons[4].get_child_count() > 0,
		"center grid slot should show Wood after selecting recipe 0")
	crafting_ui._on_result_pressed()

	var wood_after = _count_of(inventory, WOOD_ID)
	var planks_after = _count_of(inventory, PLANKS_ID)
	print("[MenusDemo] after craft: wood=", wood_after, " planks=", planks_after)
	_assert("crafting_output_appeared", planks_after == planks_before + 4,
		"planks " + str(planks_before) + " -> " + str(planks_after))
	_assert("crafting_input_consumed", wood_after == wood_before - 1,
		"wood " + str(wood_before) + " -> " + str(wood_after))

	await _shot("crafting")

# ---------------------------------------------------------------------------
# 2. Inventory
# ---------------------------------------------------------------------------
func _test_inventory() -> void:
	print("[MenusDemo] --- Inventory ---")
	crafting_ui.visible = false
	inventory_ui.visible = true
	inventory_ui.update_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	inventory.add_item(INV_MARKER_ID, 2)
	var from_i = _find_slot(inventory, INV_MARKER_ID)
	var to_i = _find_empty_slot(inventory)
	_assert("inventory_move_setup", from_i >= 0 and to_i >= 0 and from_i != to_i,
		"from=" + str(from_i) + " to=" + str(to_i))

	inventory_ui.update_ui()
	# Drive the real click handler exactly as two Button.pressed signals would:
	# first click picks up slot `from_i`, second click places onto `to_i`.
	inventory_ui._on_slot_pressed(from_i)
	_assert("inventory_pickup_selected", inventory_ui._selected_slot == from_i)
	inventory_ui._on_slot_pressed(to_i)

	var moved_ok = inventory.items[from_i] == null \
		and inventory.items[to_i] != null \
		and inventory.items[to_i].id == INV_MARKER_ID \
		and inventory.items[to_i].count == 2
	_assert("inventory_move_landed", moved_ok,
		"slot[" + str(from_i) + "]=" + str(inventory.items[from_i]) +
		" slot[" + str(to_i) + "]=" + str(inventory.items[to_i]))
	_assert("inventory_selection_cleared", inventory_ui._selected_slot == -1)

	await _shot("inventory")

# ---------------------------------------------------------------------------
# 3. Furnace
# ---------------------------------------------------------------------------
func _test_furnace() -> void:
	print("[MenusDemo] --- Furnace ---")
	inventory_ui.visible = false
	if not voxel_world:
		_assert("furnace_world_available", false, "no VoxelWorld -- cannot place FurnaceBlock")
		return

	var pos := Vector3i(0, 220, 0)
	voxel_world.set_voxel(Vector3(pos) + Vector3(0.5, 0.5, 0.5), 8) # 8 = Furnace
	var entity = voxel_world.get_block_entity(pos)
	_assert("furnace_entity_spawned", entity != null)
	if not entity:
		return

	# Real interaction path: same call Player.gd's manual_interaction_check()
	# makes on a right-click against a block-entity (see Player.gd "3. Block
	# Entity Interaction").
	entity.interact(player)
	_assert("furnace_ui_opened", furnace_ui.visible and furnace_ui.furnace == entity)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	inventory.add_item(RAW_IRON_ID, 3)
	var wood_idx = _find_slot(inventory, WOOD_ID)
	var iron_idx = _find_slot(inventory, RAW_IRON_ID)
	_assert("furnace_load_setup", wood_idx >= 0 and iron_idx >= 0,
		"wood_idx=" + str(wood_idx) + " iron_idx=" + str(iron_idx))

	var wood_before = _count_of(inventory, WOOD_ID)
	var iron_before = _count_of(inventory, RAW_IRON_ID)

	# Load fuel and input THROUGH the real UI click handler, not by poking
	# furnace.inventory directly -- this is the code that was entirely
	# missing before (FurnaceUI had no way to get items in/out at all).
	furnace_ui._on_inv_slot_pressed(wood_idx)
	# Re-find the raw iron slot: removing the wood stack can shift which
	# index still holds iron if they were adjacent, so re-scan rather than
	# assume iron_idx is still valid.
	iron_idx = _find_slot(inventory, RAW_IRON_ID)
	furnace_ui._on_inv_slot_pressed(iron_idx)

	_assert("furnace_fuel_loaded", entity.inventory[1] != null and entity.inventory[1].id == WOOD_ID,
		str(entity.inventory[1]))
	_assert("furnace_input_loaded", entity.inventory[0] != null and entity.inventory[0].id == RAW_IRON_ID,
		str(entity.inventory[0]))
	_assert("furnace_items_left_player_inventory",
		_count_of(inventory, WOOD_ID) < wood_before and _count_of(inventory, RAW_IRON_ID) < iron_before)

	await _shot("furnace")

	# Furnace.gd's _process(): first tick consumes fuel (burn_time <- max_burn_time
	# for Wood = 10s), then accumulates cook_time each frame smelt_item() is
	# valid, producing 1 output once cook_time >= COOK_DURATION (5s). Real
	# time, not skippable -- wait comfortably past both.
	print("[MenusDemo] waiting for smelt tick...")
	await get_tree().create_timer(6.5).timeout

	print("[MenusDemo] furnace state: input=", entity.inventory[0],
		" fuel=", entity.inventory[1], " output=", entity.inventory[2],
		" burn_time=", entity.burn_time, " cook_time=", entity.cook_time)
	_assert("furnace_output_produced",
		entity.inventory[2] != null and entity.inventory[2].id == IRON_INGOT_ID and entity.inventory[2].count >= 1,
		str(entity.inventory[2]))
	_assert("furnace_input_decremented",
		entity.inventory[0] == null or entity.inventory[0].count < 3,
		str(entity.inventory[0]))
	_assert("furnace_fuel_consumed",
		entity.inventory[1] == null or entity.burn_time < 10.0,
		"fuel=" + str(entity.inventory[1]) + " burn_time=" + str(entity.burn_time))

	# Extract the smelted output back into the player's inventory through the
	# real output-slot click handler.
	var ingot_before = _count_of(inventory, IRON_INGOT_ID)
	furnace_ui._on_furnace_slot_pressed(2)
	_assert("furnace_output_extracted",
		entity.inventory[2] == null and _count_of(inventory, IRON_INGOT_ID) > ingot_before,
		"ingot count " + str(ingot_before) + " -> " + str(_count_of(inventory, IRON_INGOT_ID)))

# ---------------------------------------------------------------------------
# 4. Chest
# ---------------------------------------------------------------------------
func _test_chest() -> void:
	print("[MenusDemo] --- Chest ---")
	furnace_ui.visible = false
	if not voxel_world:
		_assert("chest_world_available", false, "no VoxelWorld -- cannot place ChestBlock")
		return

	var pos := Vector3i(4, 220, 0)
	voxel_world.set_voxel(Vector3(pos) + Vector3(0.5, 0.5, 0.5), 73) # 73 = Storage Chest
	var entity = voxel_world.get_block_entity(pos)
	_assert("chest_entity_spawned", entity != null)
	if not entity:
		return
	_assert("chest_prepopulated", entity.slots[0] != null,
		"ChestBlock._prepopulate() should have filled slot 0")

	entity.interact(player)
	_assert("chest_ui_opened", chest_ui.visible and chest_ui.chest == entity)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Move a marker item from the player's inventory into the chest. Amethyst
	# Ore (85) -- distinct from everything else touched in this driver, and
	# not part of any starter kit, so it's an unambiguous marker.
	var marker_id := 85
	inventory.add_item(marker_id, 2)
	var inv_idx = _find_slot(inventory, marker_id)
	_assert("chest_marker_in_inventory", inv_idx >= 0)
	chest_ui.update_ui()
	chest_ui._on_inv_slot_pressed(inv_idx)

	var chest_idx = _find_slot_in_array(entity.slots, marker_id)
	_assert("chest_received_item", chest_idx >= 0 and entity.slots[chest_idx].count == 2,
		"chest_idx=" + str(chest_idx))
	_assert("chest_item_left_inventory", _find_slot(inventory, marker_id) == -1)

	await _shot("chest")

	# "Reopen" the SAME still-alive block-entity (walking away and back never
	# frees/recreates it -- see VoxelWorld.gd's block_entities dict) and
	# confirm the marker item is still there: this is the per-chest
	# persistence proof.
	chest_ui.set_chest(entity)
	var still_there = chest_idx >= 0 and entity.slots[chest_idx] != null \
		and entity.slots[chest_idx].id == marker_id and entity.slots[chest_idx].count == 2
	_assert("chest_persisted_on_reopen", still_there)

	# Move an original prepopulated item (slot 0, Wood x5 per ChestBlock.gd)
	# back out into the player's inventory.
	var wood_in_chest_before = entity.slots[0].count if entity.slots[0] else 0
	var wood_in_inv_before = _count_of(inventory, WOOD_ID)
	chest_ui._on_chest_slot_pressed(0)
	_assert("chest_to_inventory_transfer",
		entity.slots[0] == null and _count_of(inventory, WOOD_ID) == wood_in_inv_before + wood_in_chest_before,
		"chest[0]=" + str(entity.slots[0]) + " inv_wood=" + str(_count_of(inventory, WOOD_ID)))

func _find_slot_in_array(arr: Array, id: int) -> int:
	for i in range(arr.size()):
		if arr[i] and arr[i].id == id:
			return i
	return -1
