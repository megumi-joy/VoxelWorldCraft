extends Node
class_name TrainMover

## Moves a PathFollow3D at a constant speed along its Path3D curve.
## Attach as a child of the PathFollow3D node (e.g. "TrainHead").
## First-cut mover: no stations, no braking -- just steady loop motion so
## the clip has obvious, continuous movement start to finish.

@export var speed: float = 10.0  # metres / second along the curve

var _path_follow: PathFollow3D

func _ready() -> void:
	_path_follow = get_parent() as PathFollow3D
	if not _path_follow:
		push_warning("[TrainMover] parent is not a PathFollow3D, mover is inert.")

func _physics_process(delta: float) -> void:
	if not _path_follow:
		return
	_path_follow.progress += speed * delta
