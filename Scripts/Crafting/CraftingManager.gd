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
	
	# Planks -> Wooden Tools
	# (Simplified: 2 Planks for any tool for now)
	for tid in [30, 31, 32, 33]:
		recipes.append({
			"input": [{"id": 13, "count": 2}],
			"output": {"id": tid, "count": 1}
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
