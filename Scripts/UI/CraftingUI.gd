extends Control

@onready var container = $Panel/RecipeScroll/RecipeList
@onready var title_label = $Panel/Label

const RECIPE_ICON_SIZE := 48.0
var crafting_manager
var inventory

func _ready():
	if title_label:
		title_label.text = "Верстак"

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
	# Clear list
	for child in container.get_children():
		child.queue_free()

	var db = get_node_or_null("/root/ItemDatabase")

	# One row per recipe: RESULT ICON (primary visual, Minecraft-style) +
	# name/count + a small ingredient-breakdown line, instead of the old
	# plain text list. Affordability reads as a dim/bright state on the
	# whole row (see _style_row below), same idea as an unaffordable
	# Minecraft recipe greying out, not just a disabled button.
	for i in range(crafting_manager.recipes.size()):
		var recipe = crafting_manager.recipes[i]
		if not recipe.has("output") or not recipe.output.has("id"): continue

		var output_id = recipe.output.id
		var output_data = db.get_item(output_id) if db else null
		var can_make = inventory and crafting_manager.can_craft(i, inventory)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, RECIPE_ICON_SIZE + 16.0)
		btn.text = ""
		btn.disabled = not can_make
		ItemIcon.apply_slot_style(btn)
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

		btn.pressed.connect(func(): on_craft(i))
		container.add_child(btn)

func on_craft(index: int):
	if inventory:
		var recipe = crafting_manager.recipes[index] if index >= 0 and index < crafting_manager.recipes.size() else null
		crafting_manager.craft(index, inventory)
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
