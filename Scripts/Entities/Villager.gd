extends CharacterBody3D
class_name Villager

const SPEED = 2.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8

# States
enum State {IDLE, WANDER}
var current_state = State.IDLE

var move_timer = 0.0
var move_direction = Vector3.ZERO
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

var wall_ray: RayCast3D

@onready var anim = $AnimationPlayer # Placeholder if we had one

func _ready():
	setup_raycast()

func setup_raycast():
	wall_ray = RayCast3D.new()
	wall_ray.name = "WallRay"
	wall_ray.target_position = Vector3(0, 0, -1.0) # Look forward
	wall_ray.enabled = true
	wall_ray.position.y = 0.5
	add_child(wall_ray)

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	# State Machine
	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
			
			move_timer -= delta
			if move_timer <= 0:
				pick_new_state()
				
		State.WANDER:
			if move_direction != Vector3.ZERO:
				velocity.x = move_direction.x * SPEED
				velocity.z = move_direction.z * SPEED
				
				# Obstacle Avoidance
				if is_on_floor() and wall_ray.is_colliding():
					velocity.y = JUMP_VELOCITY
					
				look_at(global_position + move_direction, Vector3.UP)
			
			move_timer -= delta
			if move_timer <= 0:
				pick_new_state()
	
	move_and_slide()

func pick_new_state():
	if randf() < 0.5:
		current_state = State.IDLE
		move_timer = randf_range(1.0, 3.0)
	else:
		current_state = State.WANDER
		move_timer = randf_range(2.0, 5.0)
		var angle = randf() * PI * 2
		move_direction = Vector3(sin(angle), 0, cos(angle))

func interact(player):
	print("Villager says: Trade?")
	
	# Look for TradingUI in Player HUD
	var hud = player.get_node_or_null("HUD")
	if hud and hud.has_node("TradingUI"):
		var ui = hud.get_node("TradingUI")
		ui.open()
