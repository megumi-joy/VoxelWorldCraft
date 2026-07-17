extends Resource
class_name ItemData

enum ItemType {BLOCK, TOOL, RESOURCE, CONSUMABLE}

@export var id: int
@export var name: String
@export var type: ItemType
@export var icon: Texture2D
@export var stackable: bool = true
@export var max_stack: int = 64

# For blocks
@export var block_id: int = 0

# For tools: matches ItemDatabase.get_block_category(block_type), e.g.
# "pickaxe" / "axe" / "shovel". Empty string = not a mining tool (sword, hoe).
@export var tool_type: String = ""

# Stats
@export var damage_value: float = 0.0
@export var nutrition_value: float = 0.0
@export var armor_value: float = 0.0
