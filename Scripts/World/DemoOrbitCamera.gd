extends Camera3D
class_name DemoOrbitCamera

## Optional low-angle orbit camera used ONLY to capture render/screenshot
## proof of the sky+water integration (Shaders/atmosphere_sky.gdshader +
## addons/boujie_water_shader). It stays completely inert during normal
## play: Godot auto-promotes the first ready Camera3D with no other current
## camera, so without the opt-in gate below this would silently steal the
## view from the player's own Camera3D (Scenes/Player.tscn) every time
## World.tscn loads.
##
## Opt in for a render pass with either:
##   godot ... res://Scenes/World.tscn -- --demo-camera
## or by setting the environment variable VWC_DEMO_CAMERA=1.
##
## Orbits at sea level around the world origin so both the atmosphere
## sky's horizon band and the ocean's Gerstner waves / shore foam stay in
## frame together (a straight-down vista would show neither).

@export var center: Vector3 = Vector3(0, 90, 0)
@export var radius: float = 55.0
@export var height: float = 22.0
@export var angular_speed: float = 0.08  # radians/sec
@export var start_angle: float = 0.0

var _t: float = 0.0
var _active: bool = false

func _ready() -> void:
	_active = OS.get_cmdline_user_args().has("--demo-camera") or OS.get_environment("VWC_DEMO_CAMERA") == "1"
	if not _active:
		set_process(false)
		return
	current = true
	_t = start_angle
	_apply()

func _process(delta: float) -> void:
	_t += angular_speed * delta
	_apply()

func _apply() -> void:
	var pos := center + Vector3(cos(_t) * radius, height, sin(_t) * radius)
	global_position = pos
	look_at(center, Vector3.UP)
