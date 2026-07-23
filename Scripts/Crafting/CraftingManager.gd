extends Node
class_name CraftingManager

# Recipe data structure
# { "input": [{id: int, count: int}, ...], "output": {id: int, count: int} }
var recipes = []

# Explicit 3x3 crafting-grid layouts (Minecraft-style shaped recipes) for the
# handful of recipes that have a recognizable real-Minecraft shape, keyed by
# index into `recipes` (filled in right after the matching recipes.append()
# below so the two stay in sync). Each value is a 9-entry Array, row-major
# (index 0 = top-left, 8 = bottom-right), item id per cell or 0 for empty.
# Anything not in this dict falls back to a generic top-left fill computed
# from that recipe's "input" list -- see shape_for() below. Purely a UI/visual
# concern: can_craft()/craft() still only look at "input", never at this.
var recipe_shapes = {}

func _ready():
	# Wood -> 4 Planks
	recipes.append({
		"input": [{"id": 4, "count": 1}],
		"output": {"id": 13, "count": 4}
	})
	recipe_shapes[recipes.size() - 1] = [
		0, 0, 0,
		0, 4, 0,
		0, 0, 0,
	]

	# 4 Planks -> Crafting Table
	recipes.append({
		"input": [{"id": 13, "count": 4}],
		"output": {"id": 9, "count": 1}
	})
	recipe_shapes[recipes.size() - 1] = [
		13, 13, 0,
		13, 13, 0,
		0, 0, 0,
	]

	# Wheat -> Bread
	recipes.append({
		"input": [{"id": 21, "count": 3}],
		"output": {"id": 22, "count": 1}
	})
	recipe_shapes[recipes.size() - 1] = [
		21, 21, 21,
		0, 0, 0,
		0, 0, 0,
	]
	
	# Planks -> Wooden Tools (pickaxe/shovel/axe/hoe/sword)
	# (Simplified: 2 Planks for any tool for now)
	for tid in [30, 31, 32, 33, 86]:
		recipes.append({
			"input": [{"id": 13, "count": 2}],
			"output": {"id": tid, "count": 1}
		})

	# Stone -> Stone Tools (pickaxe/shovel/axe/sword, IDs 87-90 -- see
	# ItemDatabase.gd). Same "2 [material] + 1 Stick" shape as the existing
	# Iron Sword recipe below, one tier down in material.
	for tid in [87, 88, 89, 90]:
		recipes.append({
			"input": [{"id": 3, "count": 2}, {"id": 23, "count": 1}],
			"output": {"id": tid, "count": 1}
		})

	# Iron Ingot -> Iron Tools (pickaxe/shovel/axe, IDs 91-93). Iron Sword
	# (12) already has its own recipe below -- this covers the rest of the
	# iron tier.
	for tid in [91, 92, 93]:
		recipes.append({
			"input": [{"id": 63, "count": 2}, {"id": 23, "count": 1}],
			"output": {"id": tid, "count": 1}
		})

	# 2 Planks -> 4 Sticks
	recipes.append({
		"input": [{"id": 13, "count": 2}],
		"output": {"id": 23, "count": 4}
	})
	recipe_shapes[recipes.size() - 1] = [
		0, 13, 0,
		0, 13, 0,
		0, 0, 0,
	]

	# 2 Iron Ingot + 1 Sticks -> Iron Sword. Item 12 (Iron Sword) existed in
	# ItemDatabase.gd with no recipe anywhere -- gives Iron Ingot (63) an
	# actual crafting use instead of introducing a brand new consumer item.
	recipes.append({
		"input": [{"id": 63, "count": 2}, {"id": 23, "count": 1}],
		"output": {"id": 12, "count": 1}
	})
	recipe_shapes[recipes.size() - 1] = [
		0, 63, 0,
		0, 63, 0,
		0, 23, 0,
	]

	# 3 Iron Ingot -> Bucket (Empty, 67). Ties the bucket to the iron chain
	# above, as asked.
	recipes.append({
		"input": [{"id": 63, "count": 3}],
		"output": {"id": 67, "count": 1}
	})

	# 1 Sticks + 1 Coal Ore -> 4 Torches. Torch (56, see ItemDatabase.gd) was
	# only ever placeable via the hotbar with no crafting path -- this gives
	# it one, using items that already exist (Sticks from the plank recipe
	# above, Coal Ore already minable/collectible).
	recipes.append({
		"input": [{"id": 23, "count": 1}, {"id": 5, "count": 1}],
		"output": {"id": 56, "count": 4}
	})

## 3x3 crafting-grid layout for CraftingUI.gd's grid preview: a 9-entry
## Array (row-major, 0 = empty cell) of item ids. Returns the hand-authored
## Minecraft-like shape from `recipe_shapes` when one exists; otherwise
## auto-fills cells left-to-right/top-to-bottom from `recipe.input` (one cell
## per unit of count, extra units beyond 9 total are simply not shown -- no
## current recipe needs more than 9). Purely a display helper: can_craft()/
## craft() above never consult this, so a missing/wrong shape can't affect
## whether crafting actually works.
func shape_for(recipe_index: int) -> Array:
	if recipe_shapes.has(recipe_index):
		return recipe_shapes[recipe_index]
	if recipe_index < 0 or recipe_index >= recipes.size():
		return []

	var cells = []
	cells.resize(9)
	for i in range(9): cells[i] = 0
	var idx = 0
	for req in recipes[recipe_index].input:
		for _n in range(req.count):
			if idx >= 9: break
			cells[idx] = req.id
			idx += 1
	return cells

func can_craft(recipe_index: int, inventory: Node) -> bool:
	if recipe_index < 0 or recipe_index >= recipes.size(): return false
	var recipe = recipes[recipe_index]
	
	for req in recipe.input:
		var found_count = 0
		for item in inventory.items:
			if item and item.id == req.id:
				found_count += item.count
		if found_count < req.count:
			return false
	return true

func craft(recipe_index: int, inventory: Node):
	if not can_craft(recipe_index, inventory): return
	
	var recipe = recipes[recipe_index]
	
	# Consume
	for req in recipe.input:
		inventory.remove_item(req.id, req.count)
		
	# Add
	inventory.add_item(recipe.output.id, recipe.output.count)
	print("Crafted: ", recipe.output.id)
