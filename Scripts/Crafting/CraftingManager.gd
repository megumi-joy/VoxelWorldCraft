extends Node
class_name CraftingManager

# Recipe data structure
# { "input": [{id: int, count: int}, ...], "output": {id: int, count: int} }
var recipes = []

func _ready():
	# Wood -> 4 Planks
	recipes.append({
		"input": [{"id": 4, "count": 1}],
		"output": {"id": 13, "count": 4}
	})
	
	# 4 Planks -> Crafting Table
	recipes.append({
		"input": [{"id": 13, "count": 4}],
		"output": {"id": 9, "count": 1}
	})
	
	# Wheat -> Bread
	recipes.append({
		"input": [{"id": 21, "count": 3}],
		"output": {"id": 22, "count": 1}
	})
	
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

	# 2 Iron Ingot + 1 Sticks -> Iron Sword. Item 12 (Iron Sword) existed in
	# ItemDatabase.gd with no recipe anywhere -- gives Iron Ingot (63) an
	# actual crafting use instead of introducing a brand new consumer item.
	recipes.append({
		"input": [{"id": 63, "count": 2}, {"id": 23, "count": 1}],
		"output": {"id": 12, "count": 1}
	})

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
