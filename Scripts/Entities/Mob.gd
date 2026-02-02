extends CharacterBody3D
class_name Mob

const SPEED = 3.0
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

func _ready():
	health = max_health

func take_damage(amount: float):
	health -= amount
	if health <= 0:
		die()

func die():
	queue_free()

func _process(delta):
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
			else:
				current_state = State.IDLE
	
	if attack_cooldown > 0:
		attack_cooldown -= delta

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
		var angle = randf() * PI * 2
		move_direction = Vector3(sin(angle), 0, cos(angle))
		target_rotation_y = atan2(move_direction.x, move_direction.z)
