extends Node

var items = {}

func _ready():
	var ItemData = load("res://Scripts/Entities/ItemData.gd")
	# Hardcoded items for prototype
	# ID 1: Dirt Block
	var dirt = ItemData.new()
	dirt.id = 1
	dirt.name = "Dirt"
	dirt.type = ItemData.ItemType.BLOCK
	dirt.block_id = 1
	items[1] = dirt
	
	# ID 2: Grass Block
	var grass = ItemData.new()
	grass.id = 2
	grass.name = "Grass"
	grass.type = ItemData.ItemType.BLOCK
	grass.block_id = 2
	items[2] = grass
	
	# ID 3: Stone Block
	var stone = ItemData.new()
	stone.id = 3
	stone.name = "Stone"
	stone.type = ItemData.ItemType.BLOCK
	stone.block_id = 3
	items[3] = stone
	
	# ID 4: Wood Block
	var wood = ItemData.new()
	wood.id = 4
	wood.name = "Wood"
	wood.type = ItemData.ItemType.BLOCK
	wood.block_id = 4
	items[4] = wood
	
	# ID 5: Coal Ore
	var coal = ItemData.new()
	coal.id = 5
	coal.name = "Coal Ore"
	coal.type = ItemData.ItemType.BLOCK
	coal.block_id = 5
	items[5] = coal
	
	# ID 6: Iron Ore
	var iron = ItemData.new()
	iron.id = 6
	iron.name = "Iron Ore"
	iron.type = ItemData.ItemType.BLOCK
	iron.block_id = 6
	items[6] = iron
	
	# ID 10: Bed
	var bed = ItemData.new()
	bed.id = 10
	bed.name = "Bed"
	bed.type = ItemData.ItemType.BLOCK
	bed.block_id = 10
	items[10] = bed

	# ID 8: Furnace
	var furnace = ItemData.new()
	furnace.id = 8
	furnace.name = "Furnace"
	furnace.type = ItemData.ItemType.BLOCK
	furnace.block_id = 8
	items[8] = furnace
	
	# ID 9: Crafting Table
	var ctable = ItemData.new()
	ctable.id = 9
	ctable.name = "Crafting Table"
	ctable.type = ItemData.ItemType.BLOCK
	ctable.block_id = 9
	items[9] = ctable
	
	# ID 11: Apple
	var apple = ItemData.new()
	apple.id = 11
	apple.name = "Apple"
	apple.type = ItemData.ItemType.CONSUMABLE
	apple.nutrition_value = 20.0
	items[11] = apple
	
	# ID 12: Sword
	var sword = ItemData.new()
	sword.id = 12
	sword.name = "Iron Sword"
	sword.type = ItemData.ItemType.TOOL
	sword.damage_value = 10.0
	items[12] = sword

func get_item(id: int):
	if items.has(id):
		return items[id]
	return null
