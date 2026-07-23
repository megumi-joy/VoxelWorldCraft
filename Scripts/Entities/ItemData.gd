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

# Tool material tier: 0 = not tiered (bare hand / non-mining tool like the
# Sword), 1 = Wood, 2 = Stone, 3 = Iron. Higher tier breaks its matching
# tool_type category faster -- see Player.gd's get_break_speed() /
# BREAK_SPEED_BY_TIER, and scales weapon damage_value for swords.
@export var tier: int = 0

# Stats
@export var damage_value: float = 0.0
@export var nutrition_value: float = 0.0
@export var armor_value: float = 0.0
