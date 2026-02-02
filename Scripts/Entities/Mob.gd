extends CharacterBody3D
class_name Mob

const SPEED = 3.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8

# States
enum State {IDLE, WANDER, CHASE}
var current_state = State.IDLE

var move_timer = 0.0
var move_direction = Vector3.ZERO
var target_rotation_y = 0.0

func _process(delta):
	# Simple State Machine
	match current_state:
		State.IDLE:
			move_timer -= delta
			if move_timer <= 0:
				pick_random_state()
		State.WANDER:
			move_timer -= delta
			if move_timer <= 0:
				pick_random_state()
			
			# Rotation smoothing
			rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * 5.0)

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Movement
	if current_state == State.WANDER:
		velocity.x = move_direction.x * SPEED
		velocity.z = move_direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func pick_random_state():
	if randf() > 0.5:
		current_state = State.IDLE
		move_timer = randf_range(1.0, 3.0)
	else:
		current_state = State.WANDER
		move_timer = randf_range(2.0, 5.0)
		# Pick random direction
		var angle = randf() * PI * 2
		move_direction = Vector3(sin(angle), 0, cos(angle))
		target_rotation_y = atan2(move_direction.x, move_direction.z)
