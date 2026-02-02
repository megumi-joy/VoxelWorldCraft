extends Node3D

@export var rotation_speed: float = 0.1
@export var radius: float = 64.0
@export var height: float = 80.0

@onready var camera = $Camera3D
@onready var pivot = $Pivot

var angle: float = 0.0

func _ready():
	# Ensure VoxelWorld generates chunks around center
	if has_node("VoxelWorld"):
		var vw = $VoxelWorld
		# Force load center chunks
		vw.update_chunks(Vector2i(0, 0))

func _process(delta):
	angle += rotation_speed * delta
	
	var x = cos(angle) * radius
	var z = sin(angle) * radius
	
	if camera:
		camera.global_position = Vector3(x, height, z)
		camera.look_at(Vector3(0, height * 0.8, 0))
