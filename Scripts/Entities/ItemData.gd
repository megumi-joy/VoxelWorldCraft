extends Resource
class_name ItemData

enum ItemType {BLOCK, TOOL, RESOURCE}

@export var id: int
@export var name: String
@export var type: ItemType
@export var icon: Texture2D
@export var stackable: bool = true
@export var max_stack: int = 64

# For blocks
@export var block_id: int = 0
