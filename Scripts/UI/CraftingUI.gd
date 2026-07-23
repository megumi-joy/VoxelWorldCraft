extends Control

@onready var container = $Panel/RecipeScroll/RecipeList
@onready var title_label = $Panel/Label
@onready var craft_label = $Panel/CraftLabel
@onready var book_label = $Panel/BookLabel
@onready var craft_grid = $Panel/CraftGrid
@onready var result_slot: Button = $Panel/ResultSlot

const RECIPE_ICON_SIZE := 40.0
const BOOK_ROW_HEIGHT := 96.0
const CRAFT_SLOT_SIZE := 74.0
var crafting_manager
var inventory

# 9 fixed preview slots for the 3x3 crafting grid (Minecraft-style), built
# once in _ready() and repopulated in _update_craft_preview() -- same
# "persistent nodes, refill on update" convention FurnaceUI.gd uses for its
# 3 fixed slots, rather than recreating them every frame like the dynamic
# recipe-book rows below.
var craft_slot_buttons: Array[Button] = []

# Index into crafting_manager.recipes of the recipe currently laid out in the
# 3x3 grid + result slot, or -1 if nothing is selected. Set either by
# clicking a recipe row in the book (_on_recipe_selected) or by on_craft()
# itself (so a direct on_craft(i) call -- e.g. MenusDemoDriver's legacy path
# -- still leaves the grid/result showing the recipe that was just crafted,
# instead of an empty grid).
var selected_recipe: int = -1

func _ready():
	if title_label:
		title_label.text = "Верстак"
	if craft_label:
		craft_label.text = "Крафт"
	if book_label:
		book_label.text = "Книга рецептов"

	# Opaque, dense backdrop (Minecraft-style menu chrome) -- the world must
	# never show through a menu panel. Was translucent glass before, which
	# read as unfinished; light border keeps the classic inventory-frame look.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.08, 0.07, 1.0)
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.border_color = Color(0.82, 0.78, 0.68, 0.95)
	$Panel.add_theme_stylebox_override("panel", style)

	# Build the 9 crafting-grid preview slots once. These are display-only
	# (mouse ignored) -- ingredients come from the selected book recipe's
	# shape, not from manually dragging items in, so there's nothing to click
	# here; only the book row (pick a recipe) and the result slot (craft it)
	# are interactive.
	for i in range(9):
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(CRAFT_SLOT_SIZE, CRAFT_SLOT_SIZE)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ItemIcon.apply_slot_style(slot)
		craft_grid.add_child(slot)
		craft_slot_buttons.append(slot)

	ItemIcon.apply_slot_style(result_slot)
	result_slot.pressed.connect(_on_result_pressed)

	var cm_script = load("res://Scripts/Crafting/CraftingManager.gd")
	crafting_manager = cm_script.new()
	add_child(crafting_manager)

	# Find player inventory. Same race as InventoryUI.gd used to have (fixed
	# there, see that file's _ready() comment): CraftingUI is a sibling of
	# Player's "Inventory" node under HUD, and Godot calls _ready() bottom-up
	# (children before parent) -- Player.gd only calls add_to_group("player")
	# in its OWN _ready(), which runs AFTER this one. A single get_first_node_
	# in_group("player") lookup here always found nothing, `inventory` stayed
	# null forever, and every recipe button rendered permanently disabled
	# ("Missing Materials") no matter what the player was actually carrying --
	# crafting was silently dead in real play (only ever worked in contexts
	# that poked `inventory` in some other way). Retry across frames instead.
	_wire_inventory_deferred()

## Mirrors InventoryUI.gd's _wire_inventory_deferred(): retries once per frame
## for ~2s, then gives up quietly (so a stripped test scene without a player
## never spins forever). Idempotent.
func _wire_inventory_deferred() -> void:
	if inventory:
		return
	for _attempt in range(120): # ~2s at 60fps
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_node("Inventory"):
			inventory = player.get_node("Inventory")
			inventory.inventory_changed.connect(update_ui)
			update_ui()
			print("[CraftingUI] inventory wired after ", _attempt, " frame(s)")
			return
		await get_tree().process_frame
	update_ui()

func update_ui():
	# Clear book list
	for child in container.get_children():
		child.queue_free()

	var db = get_node_or_null("/root/ItemDatabase")

	# One row per recipe: RESULT ICON (primary visual, Minecraft-style) +
	# name/count + a small ingredient-breakdown line -- this list is now the
	# "Книга рецептов" (recipe book) sidebar: clicking a row no longer crafts
	# directly, it lays that recipe's shape into the 3x3 grid + result slot
	# on the left (see _on_recipe_selected/_update_craft_preview below).
	# Affordability still reads as a dim/bright state on the whole row (row
	# modulate below), same idea as an unaffordable Minecraft recipe greying
	# out.
	for i in range(crafting_manager.recipes.size()):
		var recipe = crafting_manager.recipes[i]
		if not recipe.has("output") or not recipe.output.has("id"): continue

		var output_id = recipe.output.id
		var output_data = db.get_item(output_id) if db else null
		var can_make = inventory and crafting_manager.can_craft(i, inventory)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, BOOK_ROW_HEIGHT)
		btn.text = ""
		btn.clip_text = true
		# Rows used to overflow their allocated height when the ingredient
		# line wrapped to 2+ lines, bleeding visually into the row below
		# ("наезд строк друг на друга") -- clip_contents makes a too-long
		# row's overflow disappear instead of spilling onto its neighbour,
		# so every row reads as the same fixed height no matter what.
		btn.clip_contents = true
		ItemIcon.apply_slot_style(btn, i == selected_recipe)
		if output_data:
			btn.tooltip_text = output_data.name

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 10)
		row.offset_left = 8
		row.offset_top = 8
		row.offset_right = -8
		row.offset_bottom = -8
		btn.add_child(row)

		if output_data:
			var icon = ItemIcon.make_icon_node(output_data, btn, RECIPE_ICON_SIZE)
			row.add_child(icon)

		var text_col := VBoxContainer.new()
		text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text_col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(text_col)

		var name = output_data.name if output_data else ("#" + str(output_id))
		var name_lbl := Label.new()
		name_lbl.text = name + " x" + str(recipe.output.count)
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_col.add_child(name_lbl)

		# Ingredient breakdown so the player can see what a recipe actually
		# costs before crafting it, not just a pass/fail "can afford" flag --
		# e.g. "Палки x1, Уголь x1 (есть: 4)". Per-ingredient have/need counts
		# so a partial shortage (have 1, need 2) is visible too. Kept as
		# small side text under the icon+name (task allows this), not the
		# primary visual anymore.
		var parts = []
		for req in recipe.input:
			var req_name = "#" + str(req.id)
			if db:
				var req_data = db.get_item(req.id)
				if req_data: req_name = req_data.name
			var have = 0
			if inventory:
				for item in inventory.items:
					if item and item.id == req.id:
						have += item.count
			parts.append(req_name + " x" + str(req.count) + " (есть: " + str(have) + ")")
		var ingredients_lbl := Label.new()
		ingredients_lbl.text = ", ".join(parts)
		ingredients_lbl.add_theme_font_size_override("font_size", 12)
		ingredients_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		ingredients_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ingredients_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		text_col.add_child(ingredients_lbl)

		# Whole row dims when not affordable -- clearer at a glance than text
		# appended to a button label, and still visible through btn.disabled.
		row.modulate = Color(1, 1, 1, 1) if can_make else Color(1, 1, 1, 0.45)

		btn.pressed.connect(func(): _on_recipe_selected(i))
		container.add_child(btn)

	_update_craft_preview()

## Clicking a book row selects that recipe: lays its ingredients out in the
## 3x3 crafting grid (per CraftingManager.shape_for) and shows the result, but
## does NOT craft yet -- crafting happens on the result-slot click below, same
## two-step feel as real Minecraft (recipe book fills the grid, you still
## click the output to take it).
func _on_recipe_selected(index: int) -> void:
	selected_recipe = index
	update_ui()

## 3x3 grid + result slot showing whatever recipe is currently selected (see
## `selected_recipe`). Guards inventory/ItemDatabase being momentarily null
## (e.g. before _wire_inventory_deferred() finishes) by just rendering an
## empty/disabled preview instead of erroring.
func _update_craft_preview() -> void:
	var db = get_node_or_null("/root/ItemDatabase")
	var recipe = null
	if crafting_manager and selected_recipe >= 0 and selected_recipe < crafting_manager.recipes.size():
		recipe = crafting_manager.recipes[selected_recipe]

	var shape = crafting_manager.shape_for(selected_recipe) if crafting_manager else []
	for i in range(craft_slot_buttons.size()):
		var item_id = shape[i] if i < shape.size() else 0
		var item_data = db.get_item(item_id) if (db and item_id != 0) else null
		ItemIcon.populate_slot(craft_slot_buttons[i], item_data, 1 if item_data else 0, CRAFT_SLOT_SIZE)

	if not recipe:
		ItemIcon.populate_slot(result_slot, null, 0, CRAFT_SLOT_SIZE)
		result_slot.disabled = true
		result_slot.modulate = Color(1, 1, 1, 1)
		return

	var output_data = db.get_item(recipe.output.id) if db else null
	var can_make = inventory and crafting_manager.can_craft(selected_recipe, inventory)
	ItemIcon.populate_slot(result_slot, output_data, recipe.output.count, CRAFT_SLOT_SIZE)
	# disabled just guards the human click (a disabled Button doesn't emit
	# `pressed`) -- craft() itself re-checks can_craft(), so this is UI
	# affordance only, not the source of truth.
	result_slot.disabled = not can_make
	result_slot.modulate = Color(1, 1, 1, 1) if can_make else Color(1, 1, 1, 0.45)

## Result-slot click: craft whatever recipe is currently laid out in the grid.
func _on_result_pressed() -> void:
	if selected_recipe == -1:
		return
	on_craft(selected_recipe)

func on_craft(index: int):
	if inventory:
		var recipe = crafting_manager.recipes[index] if index >= 0 and index < crafting_manager.recipes.size() else null
		crafting_manager.craft(index, inventory)
		# Keep (or set) this recipe selected so the 3x3 grid/result slot still
		# show it afterwards -- matters both for a human clicking the result
		# slot and for MenusDemoDriver.gd's legacy direct on_craft(i) call,
		# which never goes through _on_recipe_selected().
		selected_recipe = index
		update_ui() # Refresh

		# Action-log entry (see Scripts/Autoload/ActionLog.gd) -- logged here
		# rather than off Inventory.item_picked_up, since craft() adds the
		# output through the same add_item() a plain pickup uses; hooking
		# the signal instead would double-log every craft as a "pickup" too.
		if recipe and recipe.has("output") and recipe.output.has("id"):
			var db = get_node("/root/ItemDatabase")
			var name = "Unknown"
			if db:
				var data = db.get_item(recipe.output.id)
				if data: name = data.name
			ActionLog.log_event("Скрафчено: " + name + " x" + str(recipe.output.count))
