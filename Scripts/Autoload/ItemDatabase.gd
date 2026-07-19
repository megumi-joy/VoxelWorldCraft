extends Node

var items = {}

func _ready():
	var item_data_type = load("res://Scripts/Entities/ItemData.gd")
	# Hardcoded items for prototype
	# ID 1: Dirt Block
	var dirt = item_data_type.new()
	dirt.id = 1
	dirt.name = "Dirt"
	dirt.type = item_data_type.ItemType.BLOCK
	dirt.block_id = 1
	items[1] = dirt
	
	# ID 2: Grass Block
	var grass = item_data_type.new()
	grass.id = 2
	grass.name = "Grass"
	grass.type = item_data_type.ItemType.BLOCK
	grass.block_id = 2
	items[2] = grass
	
	# ID 3: Stone Block
	var stone = item_data_type.new()
	stone.id = 3
	stone.name = "Stone"
	stone.type = item_data_type.ItemType.BLOCK
	stone.block_id = 3
	items[3] = stone
	
	# ID 4: Wood Block
	var wood = item_data_type.new()
	wood.id = 4
	wood.name = "Wood"
	wood.type = item_data_type.ItemType.BLOCK
	wood.block_id = 4
	items[4] = wood
	
	# ID 5: Coal Ore
	var coal = item_data_type.new()
	coal.id = 5
	coal.name = "Coal Ore"
	coal.type = item_data_type.ItemType.BLOCK
	coal.block_id = 5
	items[5] = coal
	
	# ID 6: Iron Ore
	var iron = item_data_type.new()
	iron.id = 6
	iron.name = "Iron Ore"
	iron.type = item_data_type.ItemType.BLOCK
	iron.block_id = 6
	items[6] = iron
	
	# ID 10: Bed
	var bed = item_data_type.new()
	bed.id = 10
	bed.name = "Bed"
	bed.type = item_data_type.ItemType.BLOCK
	bed.block_id = 10
	items[10] = bed

	# ID 8: Furnace
	var furnace = item_data_type.new()
	furnace.id = 8
	furnace.name = "Furnace"
	furnace.type = item_data_type.ItemType.BLOCK
	furnace.block_id = 8
	items[8] = furnace
	
	# ID 9: Crafting Table
	var ctable = item_data_type.new()
	ctable.id = 9
	ctable.name = "Crafting Table"
	ctable.type = item_data_type.ItemType.BLOCK
	ctable.block_id = 9
	items[9] = ctable
	
	# ID 11: Apple
	var apple = item_data_type.new()
	apple.id = 11
	apple.name = "Apple"
	apple.type = item_data_type.ItemType.CONSUMABLE
	apple.nutrition_value = 20.0
	items[11] = apple
	
	# ID 12: Sword
	var sword = item_data_type.new()
	sword.id = 12
	sword.name = "Iron Sword"
	sword.type = item_data_type.ItemType.TOOL
	sword.damage_value = 10.0
	items[12] = sword
	
	# ID 13: Planks
	var planks = item_data_type.new()
	planks.id = 13
	planks.name = "Planks"
	planks.type = item_data_type.ItemType.BLOCK
	planks.block_id = 13
	items[13] = planks
	
	# ID 20: Seeds
	var seeds = item_data_type.new()
	seeds.id = 20
	seeds.name = "Seeds"
	seeds.type = item_data_type.ItemType.RESOURCE
	items[20] = seeds
	
	# ID 21: Wheat
	var wheat = item_data_type.new()
	wheat.id = 21
	wheat.name = "Wheat"
	wheat.type = item_data_type.ItemType.RESOURCE
	items[21] = wheat
	
	# ID 22: Bread
	var bread = item_data_type.new()
	bread.id = 22
	bread.name = "Bread"
	bread.type = item_data_type.ItemType.CONSUMABLE
	bread.nutrition_value = 30.0
	items[22] = bread
	
	# ID 23: Sticks (Planks -> Sticks, used as a crafting ingredient)
	var sticks = item_data_type.new()
	sticks.id = 23
	sticks.name = "Sticks"
	sticks.type = item_data_type.ItemType.RESOURCE
	items[23] = sticks

	# ID 30-33: Wooden Tools
	# NOTE: this dict used to be built and then never actually turned into
	# ItemData entries below -- items 30-33 didn't exist in `items` at all,
	# so ItemDatabase.get_item(30..33) always returned null and any tool
	# logic keyed off it (Player.gd break-speed, Hoe check) silently no-opped.
	var tools_data_local = {
		30: ["Wooden Pickaxe", "pickaxe"],
		31: ["Wooden Shovel", "shovel"],
		32: ["Wooden Axe", "axe"],
		33: ["Wooden Hoe", "hoe"]
	}
	for tid in tools_data_local:
		var tool_item = item_data_type.new()
		tool_item.id = tid
		tool_item.name = tools_data_local[tid][0]
		tool_item.type = item_data_type.ItemType.TOOL
		tool_item.tool_type = tools_data_local[tid][1]
		tool_item.stackable = false
		items[tid] = tool_item
	# Nature & Fluids
	var nature_items = {
		40: ["Water", item_data_type.ItemType.BLOCK, 40],
		41: ["Lava", item_data_type.ItemType.BLOCK, 41],
		42: ["Sand", item_data_type.ItemType.BLOCK, 16], # Reuse logic
		43: ["Snow", item_data_type.ItemType.BLOCK, 15],
		44: ["Flower (Red)", item_data_type.ItemType.BLOCK, 44],
		45: ["Flower (Yellow)", item_data_type.ItemType.BLOCK, 45],
		46: ["Tall Grass", item_data_type.ItemType.BLOCK, 46],
		47: ["Cactus", item_data_type.ItemType.BLOCK, 47],
		48: ["Birch Wood", item_data_type.ItemType.BLOCK, 48],
		49: ["Pine Wood", item_data_type.ItemType.BLOCK, 49],
		50: ["Birch Leaves", item_data_type.ItemType.BLOCK, 50],
		51: ["Pine Leaves", item_data_type.ItemType.BLOCK, 51],
		52: ["Ice", item_data_type.ItemType.BLOCK, 52],
		60: ["Leather Tunic", item_data_type.ItemType.RESOURCE, 0], # Armor Type?
		61: ["Iron Chestplate", item_data_type.ItemType.RESOURCE, 0]
	}
	for id in nature_items:
		var n = item_data_type.new()
		n.id = id
		n.name = nature_items[id][0]
		n.type = nature_items[id][1]
		if n.type == item_data_type.ItemType.BLOCK:
			n.block_id = nature_items[id][2]
		items[id] = n
	
	# Set Armor stats
	if items.has(60): items[60].armor_value = 5.0
	if items.has(61): items[61].armor_value = 20.0

	# Flowers & Food (decorative plants + edible harvest, additive block)
	# ID 55: Berry Bush (world decoration, harvestable for Berries)
	# NOTE: originally ID 52 in feat/flowers-food, but feat/biomes
	# independently claimed 52 for Ice (Tundra biome terrain block).
	# Reassigned to the next free id during speedrun integration to resolve
	# the collision -- Ice keeps 52 since it's referenced by more call sites
	# (get_biome/generate_data terrain gen) than the Berry Bush's decorative
	# scatter.
	var berry_bush = item_data_type.new()
	berry_bush.id = 55
	berry_bush.name = "Berry Bush"
	berry_bush.type = item_data_type.ItemType.BLOCK
	berry_bush.block_id = 55
	items[55] = berry_bush

	# ID 53: Blue Flower (decorative)
	var blue_flower = item_data_type.new()
	blue_flower.id = 53
	blue_flower.name = "Flower (Blue)"
	blue_flower.type = item_data_type.ItemType.BLOCK
	blue_flower.block_id = 53
	items[53] = blue_flower

	# ID 54: Pink Flower (decorative)
	var pink_flower = item_data_type.new()
	pink_flower.id = 54
	pink_flower.name = "Flower (Pink)"
	pink_flower.type = item_data_type.ItemType.BLOCK
	pink_flower.block_id = 54
	items[54] = pink_flower

	# ID 56: Torch (placeable light source; block-entity like Furnace/Bed --
	# see Scenes/Blocks/TorchBlock.tscn -- but unlike those it is NOT written
	# into voxel_data/the chunk mesh (see VoxelWorld.set_voxel), so it has no
	# solid cube and no atlas texture entry here. Its only visuals are the
	# entity's own pole+flame mesh and OmniLight3D.)
	var torch = item_data_type.new()
	torch.id = 56
	torch.name = "Torch"
	torch.type = item_data_type.ItemType.BLOCK
	torch.block_id = 56
	items[56] = torch

	# ID 70: Berries (edible; harvested by breaking a Berry Bush)
	var berries = item_data_type.new()
	berries.id = 70
	berries.name = "Berries"
	berries.type = item_data_type.ItemType.CONSUMABLE
	berries.nutrition_value = 12.0
	items[70] = berries

	# ID 80-84: Mineral ores (wave 2). Each is its own block+item (id ==
	# block_id, same pattern as Coal/Iron), mined via the pickaxe category
	# (see BLOCK_TOOL_CATEGORY below), generated depth/biome-gated in
	# Chunk.gd's ORE_TABLE, and registered as Field Journal "Minerals" codex
	# entries in CodexDatabase.gd keyed off these same item ids.
	var minerals = {
		80: "Copper Ore",
		81: "Gold Ore",
		82: "Quartz",
		83: "Hematite",
		84: "Malachite Ore",
	}
	for mid in minerals:
		var m = item_data_type.new()
		m.id = mid
		m.name = minerals[mid]
		m.type = item_data_type.ItemType.BLOCK
		m.block_id = mid
		items[mid] = m

	# Chemical Elements (Simplified range for "Periodic Table")
	# ID 100+ reserved for elements
	var elements = ["Hydrogen", "Helium", "Lithium", "Beryllium", "Boron", "Carbon", "Nitrogen", "Oxygen", "Fluorine", "Neon", "Sodium", "Magnesium", "Aluminum", "Silicon", "Phosphorus", "Sulfur", "Chlorine", "Argon", "Potassium", "Calcium", "Scandium", "Titanium", "Vanadium", "Chromium", "Manganese", "Iron", "Cobalt", "Nickel", "Copper", "Zinc", "Gallium", "Germanium", "Arsenic", "Selenium", "Bromine", "Krypton", "Rubidium", "Strontium", "Yttrium", "Zirconium", "Niobium", "Molybdenum", "Technetium", "Ruthenium", "Rhodium", "Palladium", "Silver", "Cadmium", "Indium", "Tin", "Antimony", "Tellurium", "Iodine", "Xenon", "Cesium", "Barium", "Lanthanum", "Cerium", "Praseodymium", "Neodymium", "Promethium", "Samarium", "Europium", "Gadolinium", "Terbium", "Dysprosium", "Holmium", "Erbium", "Thulium", "Ytterbium", "Lutetium", "Hafnium", "Tantalum", "Tungsten", "Rhenium", "Osmium", "Iridium", "Platinum", "Gold", "Mercury", "Thallium", "Lead", "Bismuth", "Polonium", "Astatine", "Radon", "Francium", "Radium", "Actinium", "Thorium", "Protactinium", "Uranium", "Neptunium", "Plutonium", "Americium", "Curium", "Berkelium", "Californium", "Einsteinium", "Fermium", "Mendelevium", "Nobelium", "Lawrencium", "Rutherfordium", "Dubnium", "Seaborgium", "Bohrium", "Hassium", "Meitnerium", "Darmstadtium", "Roentgenium", "Copernicium", "Nihonium", "Flerovium", "Moscovium", "Livermorium", "Tennessine", "Oganesson"]
	
	for i in range(elements.size()):
		var e = item_data_type.new()
		e.id = 100 + i
		e.name = elements[i]
		e.type = item_data_type.ItemType.RESOURCE # Most are resources
		if elements[i] in ["Iron", "Gold", "Copper", "Silver", "Lead", "Tin", "Aluminum", "Titanium", "Uranium"]:
			e.type = item_data_type.ItemType.BLOCK # Ores are blocks? Or Resource items dropped by blocks? 
			# Let's make them Resource Items for now, and have specific Block IDs for their Ore Block form.
			# Re-mapping: Iron Ore (ID 6) drops Iron (Element 25, ID 125).
		items[e.id] = e

func get_item(id: int):
	if items.has(id):
		return items[id]
	return null

# Voxel block_type -> mining category ("pickaxe" / "axe" / "shovel").
# Used by Player.gd to decide block-break speed for the currently held tool.
# Blocks not listed here (flowers, leaves, water, ores/blocks not covered
# below, ...) are left at the default break speed regardless of held item.
# A couple of ids are listed twice on purpose: world terrain generation
# (Chunk.gd) writes raw block ids 42/43 for Sand/Snow directly, while
# block-placement from the Sand/Snow *items* goes through their declared
# block_id (16/15) -- both need to resolve to "shovel".
const BLOCK_TOOL_CATEGORY = {
	3: "pickaxe",  # Stone
	5: "pickaxe",  # Coal Ore
	6: "pickaxe",  # Iron Ore
	80: "pickaxe", # Copper Ore
	81: "pickaxe", # Gold Ore
	82: "pickaxe", # Quartz
	83: "pickaxe", # Hematite
	84: "pickaxe", # Malachite Ore
	4: "axe",      # Wood (Oak Log)
	13: "axe",     # Planks
	48: "axe",     # Birch Wood
	49: "axe",     # Pine Wood
	1: "shovel",   # Dirt
	2: "shovel",   # Grass
	42: "shovel",  # Sand (as generated in terrain)
	16: "shovel",  # Sand (item.block_id)
	43: "shovel",  # Snow (as generated in terrain)
	15: "shovel",  # Snow (item.block_id)
	14: "shovel",  # Farmland
}

func get_block_category(block_type: int) -> String:
	return BLOCK_TOOL_CATEGORY.get(block_type, "")
