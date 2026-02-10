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

@export var max_health: float = 20.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 2.0
@export var detection_range: float = 15.0

var health: float
var target_player: Node3D = null

# AI improvements
var wall_ray: RayCast3D
var stuck_timer: float = 0.0
var last_position: Vector3

func _ready():
	health = max_health
	setup_raycast()

func setup_raycast():
	wall_ray = RayCast3D.new()
	wall_ray.name = "WallRay"
	wall_ray.target_position = Vector3(0, 0, -1.0) # Look forward
	wall_ray.enabled = true
	wall_ray.position.y = 0.5 # Chest height
	add_child(wall_ray)

func take_damage(amount: float):
	health -= amount
	if health <= 0:
		die()
	# Aggro on hit
	if not target_player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			# Find closest just in case
			target_player = players[0]
			current_state = State.CHASE

func die():
	queue_free()

func _process(delta):
	# Update Raycast rotation to match mob (it's a child so it matches body, but body rotates)
	# CharacterBody3D rotation is handled via rotation.y
	match current_state:
		State.IDLE:
			move_timer -= delta
			if move_timer <= 0:
				pick_random_state()
			check_for_player()
			
		State.WANDER:
			move_timer -= delta
			if move_timer <= 0:
				pick_random_state()
			
			rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * 5.0)
			check_for_player()
			check_stuck(delta)
			
		State.CHASE:
			if target_player:
				var dist = global_position.distance_to(target_player.global_position)
				if dist > detection_range * 1.5:
					# Lost player
					current_state = State.IDLE
					target_player = null
				elif dist <= attack_range:
					attack_player()
				else:
					var dir = (target_player.global_position - global_position).normalized()
					move_direction = Vector3(dir.x, 0, dir.z).normalized()
					target_rotation_y = atan2(move_direction.x, move_direction.z)
					rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * 10.0)
					
					check_stuck(delta)
			else:
				current_state = State.IDLE
	
	if attack_cooldown > 0:
		attack_cooldown -= delta

func check_stuck(delta):
	stuck_timer += delta
	if stuck_timer > 0.5:
		stuck_timer = 0.0
		var dist_moved = global_position.distance_to(last_position)
		if dist_moved < 0.1:
			# Stuck
			if current_state == State.WANDER:
				# Turn around
				pick_random_state()
			elif current_state == State.CHASE:
				# Jump? already handled. Maybe strafe?
				# For now just jump again or drift
				velocity.y = JUMP_VELOCITY
		last_position = global_position

func check_for_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var closest = players[0]
		var dist = global_position.distance_to(closest.global_position)
		if dist < detection_range:
			target_player = closest
			current_state = State.CHASE

var attack_cooldown = 0.0

func attack_player():
	if attack_cooldown <= 0:
		if target_player and target_player.has_method("take_damage"):
			target_player.take_damage(attack_damage)
			attack_cooldown = 1.0

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	if current_state == State.WANDER or current_state == State.CHASE:
		velocity.x = move_direction.x * SPEED
		velocity.z = move_direction.z * SPEED
		
		# Obstacle Avoidance (Auto Jump)
		if is_on_floor() and wall_ray.is_colliding():
			velocity.y = JUMP_VELOCITY
			
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func pick_random_state():
	# Reset stuck tracker
	last_position = global_position
	
	if randf() > 0.4: # More wandering
		current_state = State.IDLE
		move_timer = randf_range(1.0, 3.0)
	else:
		current_state = State.WANDER
		move_timer = randf_range(2.0, 5.0)
		var angle = randf() * PI * 2
		move_direction = Vector3(sin(angle), 0, cos(angle))
		target_rotation_y = atan2(move_direction.x, move_direction.z)
