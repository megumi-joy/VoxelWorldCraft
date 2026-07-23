extends Node3D
class_name ChestBlock

# Block-entity for the Storage Chest (block/item id 73 -- ported from
# voxel-train3 branch commit c618890, which used id 71; THAT id is already
# Wool on this branch's ItemDatabase.gd, so this port uses 73, the next free
# id after Berries(70)/Wool(71)/Mutton(72) and before the wave-2 minerals
# (80-85) -- see ItemDatabase.gd for the full id map). Modeled on Furnace.gd's
# block-entity pattern minus the smelting: this just holds a fixed-size slot
# array that VoxelWorld keeps alive per-placement (one ChestBlock instance
# per placed chest, so each chest has its own independent contents -- see
# VoxelWorld.gd block_entities dict / spawn_block_entity()).

const SIZE = 27

# Array of {"id": int, "count": int} or null, same shape as Inventory.gd's
# `items` array so ChestUI can treat both the same way.
var slots = []

signal chest_updated

func _ready():
	slots.resize(SIZE)
	for i in range(SIZE):
		slots[i] = null
	_prepopulate()

# Owner asked for the chest to come "с предметами" (with items) so opening a
# freshly-placed chest obviously shows working contents instead of an empty
# grid.
func _prepopulate():
	add_item(4, 5)   # Wood
	add_item(3, 8)   # Stone
	add_item(11, 2)  # Apple

func interact(player):
	var hud = player.get_node_or_null("HUD")
	if hud and hud.has_node("ChestUI"):
		var ui = hud.get_node("ChestUI")
		ui.set_chest(self)
		ui.visible = not ui.visible
		if ui.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Mirrors Inventory.gd's add_item() logic (stack first, then first empty
# slot) so the two feel consistent from the player's perspective.
func add_item(id: int, count: int) -> bool:
	for i in range(SIZE):
		if slots[i] and slots[i].id == id:
			if slots[i].count < 64:
				var space = 64 - slots[i].count
				var to_add = min(count, space)
				slots[i].count += to_add
				count -= to_add
				if count == 0:
					chest_updated.emit()
					return true

	if count > 0:
		for i in range(SIZE):
			if slots[i] == null:
				slots[i] = {"id": id, "count": count}
				chest_updated.emit()
				return true

	chest_updated.emit()
	return false

# Removes up to `count` from a specific slot index (used by ChestUI, which
# already knows which slot was clicked). count < 0 removes the whole stack.
func remove_slot(i: int, count: int = -1) -> Dictionary:
	if i < 0 or i >= SIZE or slots[i] == null:
		return {}

	var item = slots[i]
	var take = item.count if count < 0 else min(count, item.count)
	var removed = {"id": item.id, "count": take}

	item.count -= take
	if item.count <= 0:
		slots[i] = null

	chest_updated.emit()
	return removed
