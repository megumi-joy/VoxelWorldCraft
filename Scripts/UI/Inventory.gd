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
	add_item(73, 2) # Storage Chest (placeable, so the feature is reachable)

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

## Moves the contents of slot `from` onto slot `to` -- used by InventoryUI's
## click-to-pick-up/click-to-place interaction. Three cases, mirroring how
## every other stack-aware inventory works:
##   - `to` is empty: the whole stack relocates there.
##   - `to` holds the SAME item id: merge, capped at 64/slot. If the source
##     stack doesn't fully fit, the leftover stays behind in `from` instead of
##     being silently dropped (no dupe/loss either way).
##   - `to` holds a DIFFERENT item id: swap the two stacks.
## No-ops (returns false) for an empty `from`, an out-of-range index, or
## from == to -- callers (InventoryUI) rely on the false return to know
## nothing changed and skip re-rendering/logging a move that didn't happen.
func move_item(from: int, to: int) -> bool:
	if from < 0 or from >= size or to < 0 or to >= size or from == to:
		return false
	if items[from] == null:
		return false

	if items[to] == null:
		items[to] = items[from]
		items[from] = null
	elif items[to].id == items[from].id:
		var space = 64 - items[to].count
		var moving = min(space, items[from].count)
		items[to].count += moving
		items[from].count -= moving
		if items[from].count <= 0:
			items[from] = null
	else:
		var tmp = items[to]
		items[to] = items[from]
		items[from] = tmp

	inventory_changed.emit()
	return true

func remove_item(id: int, count: int) -> bool:
	# Sum across ALL matching stacks first, mirroring how
	# CraftingManager.can_craft() checks affordability (it sums item.count
	# across every slot with a matching id). The old version only ever
	# checked/removed from a single slot: if the same item ended up split
	# across two partial stacks (e.g. a stack hit the 64 cap and the
	# overflow landed in a second slot), can_craft() would say yes but this
	# would find no single slot with enough and return false while
	# craft() -- which ignores remove_item()'s return value -- still handed
	# out the crafted output. That's a free-item dupe. Drain across as many
	# matching slots as it takes instead.
	var total = 0
	for item in items:
		if item and item.id == id:
			total += item.count
	if total < count:
		return false

	var remaining = count
	for i in range(size):
		if remaining <= 0:
			break
		if items[i] and items[i].id == id:
			var take = min(remaining, items[i].count)
			items[i].count -= take
			remaining -= take
			if items[i].count == 0:
				items[i] = null

	inventory_changed.emit()
	return true
