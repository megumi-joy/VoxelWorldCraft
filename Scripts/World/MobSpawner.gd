extends Node

@export var player_path: NodePath
@export var mob_scene: PackedScene
@export var time_cycle: TimeCycle
@export var voxel_world: VoxelWorld

@export var max_mobs: int = 20
@export var spawn_interval: float = 2.0
@export var spawn_range_min: float = 24.0
@export var spawn_range_max: float = 64.0
@export var despawn_range: float = 128.0

var timer: float = 0.0

func _process(delta):
	# Only run on server
	if not is_multiplayer_authority():
		return

	# Logic to check night time from TimeCycle
	# TimeCycle doesn't expose "is_night" directly yet, but we can check sun angle or energy.
	# Or we can check if time_cycle.time is in night range.
	var is_night = false
	if time_cycle and time_cycle.sun:
		is_night = time_cycle.sun.light_energy < 0.1 # Threshold for spawning

	if not is_night:
		despawn_all_mobs() # Optional: Burn them or just despawn? Minecraft keeps them but checks light.
		# For simplicity, let's just stop spawning. 
		# If we want them to despawn at day, we can do that.
		return

	timer += delta
	if timer > spawn_interval:
		timer = 0.0
		try_spawn_mob()
		check_despawn()

func try_spawn_mob():
	var existing_mobs = get_children()
	if existing_mobs.size() >= max_mobs:
		return

	var time_val = time_cycle.time
	var is_night = time_val > 0.75 or time_val < 0.25 # Assuming standard day/night cycle
	
	# Cap generic mob count to avoid lag
	var mob_count = get_tree().get_nodes_in_group("mobs").size()
	if mob_count >= 20: return
	
	# Spawn Logic
	# Night -> Zombies (Mob.tscn)
	# Day -> Villagers (Villager.tscn)
	
	if is_night:
		if randf() < 0.02: # Chance per frame (approx 1 per sec at 60fps)
			trigger_spawn("res://Scenes/Mob.tscn")
	else:
		if randf() < 0.005: # Rare day spawns
			trigger_spawn("res://Scenes/Villager.tscn")

func trigger_spawn(scene_path: String):
	# Pick random player
	var players = get_tree().get_nodes_in_group("player")
	if players.size() == 0: return
	
	var player = players.pick_random()
	
	# Pick random spot near player
	var angle = randf() * PI * 2
	var dist = randf_range(spawn_range_min, spawn_range_max)
	var x = player.global_position.x + sin(angle) * dist
	var z = player.global_position.z + cos(angle) * dist
	
	# Find ground height
	var y = 0
	if voxel_world and voxel_world.noise:
		var height = int((voxel_world.noise.get_noise_2d(x, z) + 1) * 32) + 64
		y = height + 2
	
	var spawn_pos = Vector3(x, y, z)
	
	spawn_mob_at(spawn_pos, scene_path)

func spawn_mob_at(pos: Vector3, scene_path: String):
	var scene = load(scene_path)
	if not scene: return
	
	var mob = scene.instantiate()
	mob.position = pos
	mob.name = "Mob_" + str(randi())
	add_child(mob, true)

	# Function replaced by spawn_mob_at
	pass

func check_despawn():
	var player = get_tree().get_first_node_in_group("player")
	if not player: return
	
	for child in get_children():
		if child is Mob:
			if child.global_position.distance_to(player.global_position) > despawn_range:
				child.queue_free()

func despawn_all_mobs():
	# Optional logic
	pass
