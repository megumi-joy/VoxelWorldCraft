extends CharacterBody3D
class_name Sheep

# First passive fauna (naturalist direction). Structurally mirrors
# Mob.gd/Villager.gd's IDLE/WANDER state machine (no NavigationAgent3D --
# the world has no navmesh; neither hostile Mob nor Villager use one
# either, they just move+turn with a forward RayCast3D + auto-jump) but is
# never hostile: no detection_range, no target_player chase/attack. The
# only reaction to the player is FLEE, entered on take_damage().

const SPEED = 2.0
const FLEE_SPEED_MULT = 2.2
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8

const WOOL_ITEM_ID = 71
const MUTTON_ITEM_ID = 72

enum State { IDLE, WANDER, FLEE }
var current_state = State.IDLE

var move_timer = 0.0
var move_direction = Vector3.ZERO
var target_rotation_y = 0.0

@export var max_health: float = 8.0
@export var flee_duration: float = 3.0

var health: float
var flee_timer: float = 0.0
var last_attacker: Node3D = null

# Obstacle-avoidance raycast + stuck detection, same shape as Mob.gd.
var wall_ray: RayCast3D
var stuck_timer: float = 0.0
var last_position: Vector3

func _ready():
	add_to_group("animals")
	health = max_health
	last_position = global_position
	setup_raycast()

func setup_raycast():
	wall_ray = RayCast3D.new()
	wall_ray.name = "WallRay"
	wall_ray.target_position = Vector3(0, 0, -1.0)
	wall_ray.enabled = true
	wall_ray.position.y = 0.35 # Sheep are short -- chest height, lower than Mob's 0.5
	add_child(wall_ray)

## Called by Player.gd's melee hit (`collider.take_damage(dmg)`, single arg
## -- see manual_interaction_check()). Never retaliates: just flees.
func take_damage(amount: float, _cause: String = ""):
	health -= amount
	if health <= 0:
		die()
		return

	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		last_attacker = players[0]
		var away = global_position - last_attacker.global_position
		away.y = 0
		if away.length() < 0.01:
			away = Vector3(randf() * 2.0 - 1.0, 0, randf() * 2.0 - 1.0)
		move_direction = away.normalized()
		target_rotation_y = atan2(move_direction.x, move_direction.z)

	current_state = State.FLEE
	flee_timer = flee_duration

## Direct-to-inventory drop, matching the rest of the codebase (there is no
## physical item-pickup entity anywhere -- Player.gd's block mining does
## `inventory.add_item(...)` straight into the harvesting player's
## inventory; this does the same for whichever player last hit the sheep).
func die():
	var target = last_attacker
	if not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
	if target:
		var inv = target.get_node_or_null("Inventory")
		if inv:
			inv.add_item(WOOL_ITEM_ID, randi_range(1, 2))
			if randf() < 0.5:
				inv.add_item(MUTTON_ITEM_ID, 1)
	queue_free()

func _process(delta):
	match current_state:
		State.IDLE:
			move_timer -= delta
			if move_timer <= 0:
				pick_random_state()

		State.WANDER:
			move_timer -= delta
			if move_timer <= 0:
				pick_random_state()
			rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * 5.0)
			check_stuck(delta)

		State.FLEE:
			flee_timer -= delta
			rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * 8.0)
			check_stuck(delta)
			if flee_timer <= 0:
				current_state = State.IDLE
				move_timer = randf_range(1.0, 2.0)

func check_stuck(delta):
	stuck_timer += delta
	if stuck_timer > 0.5:
		stuck_timer = 0.0
		var dist_moved = global_position.distance_to(last_position)
		if dist_moved < 0.1:
			if current_state == State.WANDER:
				pick_random_state()
			elif current_state == State.FLEE:
				# Stuck mid-flee (cornered) -- jump and pick a fresh
				# direction rather than pressing uselessly into a wall.
				velocity.y = JUMP_VELOCITY
				var angle = randf() * PI * 2
				move_direction = Vector3(sin(angle), 0, cos(angle))
				target_rotation_y = atan2(move_direction.x, move_direction.z)
		last_position = global_position

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if current_state == State.WANDER:
		velocity.x = move_direction.x * SPEED
		velocity.z = move_direction.z * SPEED
		if is_on_floor() and wall_ray.is_colliding():
			velocity.y = JUMP_VELOCITY
	elif current_state == State.FLEE:
		velocity.x = move_direction.x * SPEED * FLEE_SPEED_MULT
		velocity.z = move_direction.z * SPEED * FLEE_SPEED_MULT
		if is_on_floor() and wall_ray.is_colliding():
			velocity.y = JUMP_VELOCITY
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func pick_random_state():
	last_position = global_position
	if randf() > 0.5:
		current_state = State.IDLE
		move_timer = randf_range(1.5, 4.0)
	else:
		current_state = State.WANDER
		move_timer = randf_range(2.0, 4.0)
		var angle = randf() * PI * 2
		move_direction = Vector3(sin(angle), 0, cos(angle))
		target_rotation_y = atan2(move_direction.x, move_direction.z)
