extends Node
class_name Inventory

signal inventory_changed
# Fired whenever `count` units of item `id` are successfully added -- unlike
# inventory_changed (a bare "something changed, go re-render" ping), this
# carries which item, so listeners can react to specific pickups. Player.gd
# uses it to drive Field Journal discovery (see PlayerStats.discover_item).
signal item_picked_up(id, count)

@export var size: int = 24
var items = [] # Array of dictionaries { "id": int, "count": int } or null

func _ready():
	items.resize(size)
	# Fill with null
	for i in range(size):
		items[i] = null
		
	# Debug: Add starter items
	add_item(1, 10) # Dirt
	add_item(4, 5) # Wood

func add_item(id: int, count: int) -> bool:
	var requested = count

	# Try to stack first
	for i in range(size):
		if items[i] and items[i].id == id:
			# Check max stack (assume 64 for now)
			if items[i].count < 64:
				var space = 64 - items[i].count
				var to_add = min(count, space)
				items[i].count += to_add
				count -= to_add
				if count == 0:
					inventory_changed.emit()
					item_picked_up.emit(id, requested)
					return true

	# Find empty slot
	if count > 0:
		for i in range(size):
			if items[i] == null:
				items[i] = {"id": id, "count": count}
				inventory_changed.emit()
				item_picked_up.emit(id, requested)
				return true

	inventory_changed.emit()
	return false # Could not add all

func remove_item(id: int, count: int) -> bool:
	# Keep logic simple for now
	for i in range(size):
		if items[i] and items[i].id == id:
			if items[i].count >= count:
				items[i].count -= count
				if items[i].count == 0:
					items[i] = null
				inventory_changed.emit()
				return true
	return false
