extends Node
class_name CraftingManager

# Recipe format:
# {
#   "inputs": [ {id: 1, count: 2}, ... ],
#   "output": {id: 3, count: 1}
# }
var recipes = []

func _ready():
	# Define recipes
	# Wood (4) x 2 -> Stick (assume ID 99 for now, or just convert to planks)
	# Let's say: 1 Log (4) -> 4 Planks (10)
	# For prototype: 2 Dirt (1) -> 1 Grass (2)
	recipes.append({
		"inputs": [ {"id": 1, "count": 2}],
		"output": {"id": 2, "count": 1}
	})
	
	# 1 Coal (5) + 1 Iron Ore (6) -> Iron Ingot (7) - Just for test
	recipes.append({
		"inputs": [ {"id": 5, "count": 1}, {"id": 6, "count": 1}],
		"output": {"id": 7, "count": 1} # ID 7 not defined yet
	})

func can_craft(recipe_index: int, inventory: Inventory) -> bool:
	if recipe_index < 0 or recipe_index >= recipes.size(): return false
	
	var recipe = recipes[recipe_index]
	
	# Check inputs
	for input in recipe.inputs:
		if not inventory_has(inventory, input.id, input.count):
			return false
			
	# Check output space
	# Simplified: Assume space exists or drop item?
	# Better: Check if we can add output
	return can_add_item(inventory, recipe.output.id, recipe.output.count)

func craft(recipe_index: int, inventory: Inventory):
	if not can_craft(recipe_index, inventory): return
	
	var recipe = recipes[recipe_index]
	
	# Consume inputs
	for input in recipe.inputs:
		inventory.remove_item(input.id, input.count)
		
	# Add output
	inventory.add_item(recipe.output.id, recipe.output.count)

# Helper to check inventory (since Inventory.gd doesn't strictly have "has_items")
func inventory_has(inv: Inventory, id: int, count: int) -> bool:
	var found = 0
	for item in inv.items:
		if item and item.id == id:
			found += item.count
	return found >= count

func can_add_item(inv: Inventory, id: int, count: int) -> bool:
	# Simulate add
	var remaining = count
	for item in inv.items:
		if item and item.id == id:
			if item.count < 64:
				remaining -= (64 - item.count)
	
	if remaining <= 0: return true
	
	# Need empty slots
	var slots_needed = ceil(remaining / 64.0)
	var slots_found = 0
	for item in inv.items:
		if item == null:
			slots_found += 1
			
	return slots_found >= slots_needed
