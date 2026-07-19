extends Node
## Spawns a few passive Sheep on grass during daytime. A separate, self
## contained node rather than an extra branch inside MobSpawner.gd -- see
## that file's try_spawn_mob() for the hostile-mob equivalent, which this
## mirrors structurally (spawn/cull pattern, node_paths wiring) without
## touching it: no chase/attack state, no night-time branch, own species
## cap, own group ("animals", not "mobs").
##
## Day/night gating deliberately reads time_cycle.sun.light_energy (0.0
## night / 1.0 day, set directly by TimeCycle._process) rather than
## MobSpawner's own is_night check inside try_spawn_mob(), which compares
## the raw (non-normalized, 0..day_length) `time_cycle.time` against
## 0.25/0.75 thresholds meant for a 0..1 range -- that comparison is stale
## from before day_length was introduced and is almost always true, so
## reusing it here would make sheep spawn almost never. Out of scope to
## fix in MobSpawner for this change; sun.light_energy is correct and
## already relied on by MobSpawner's own outer _process() gate.

@export var animal_scene: PackedScene
@export var time_cycle: Node
@export var voxel_world: Node

@export var max_animals: int = 6
@export var spawn_interval: float = 3.0
@export var spawn_range_min: float = 12.0
@export var spawn_range_max: float = 40.0
@export var despawn_range: float = 96.0
@export var spawn_chance_per_tick: float = 0.15

const GRASS_BLOCK_ID = 2
const SHEEP_SCENE_PATH = "res://Scenes/Sheep.tscn"

var timer: float = 0.0

func _process(delta):
	if not is_multiplayer_authority():
		return
	if not time_cycle or not voxel_world:
		return
	if not (time_cycle.sun and time_cycle.sun.light_energy > 0.5):
		return # Only spawn in daylight -- calm/observable, naturalist tone.

	timer += delta
	if timer > spawn_interval:
		timer = 0.0
		try_spawn_animal()
		check_despawn()

func try_spawn_animal():
	if get_child_count() >= max_animals:
		return
	if randf() > spawn_chance_per_tick:
		return

	var players = get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		return
	var player = players.pick_random()

	var angle = randf() * PI * 2
	var dist = randf_range(spawn_range_min, spawn_range_max)
	var x = int(floor(player.global_position.x + sin(angle) * dist))
	var z = int(floor(player.global_position.z + cos(angle) * dist))

	var grass_y = _find_grass_surface_y(x, z)
	if grass_y < 0:
		return # No confirmed grass here (or chunk not loaded yet) -- try again next tick.

	var scene = animal_scene if animal_scene else load(SHEEP_SCENE_PATH)
	if not scene:
		return
	var sheep = scene.instantiate()
	# Drop from a couple blocks up and let gravity settle it onto the
	# surface, same approach MobSpawner uses for Mob/Villager -- avoids
	# needing to know the collision shape's exact rest offset.
	sheep.position = Vector3(x + 0.5, grass_y + 2.0, z + 0.5)
	sheep.name = "Sheep_" + str(randi())
	add_child(sheep, true)

## Scans a small window around the terrain-noise height estimate (same
## formula MobSpawner/Chunk use for surface height) for the actual topmost
## Grass voxel in the loaded chunk, so animals only spawn on real grass --
## not sand/snow/stone/water. Returns -1 if the chunk isn't loaded or no
## grass is found nearby (caller just retries next tick).
func _find_grass_surface_y(x: int, z: int) -> int:
	var cx = int(floor(float(x) / 16.0))
	var cz = int(floor(float(z) / 16.0))
	var cp = Vector2i(cx, cz)
	if not voxel_world.chunks.has(cp):
		return -1
	var chunk = voxel_world.chunks[cp]
	if chunk == null:
		return -1

	var lx = x - cx * 16
	var lz = z - cz * 16

	var approx_y = 64
	if voxel_world.noise:
		approx_y = int((voxel_world.noise.get_noise_2d(x, z) + 1) * 32) + 64

	var top = min(approx_y + 6, 255)
	var bottom = max(approx_y - 12, 0)
	for y in range(top, bottom, -1):
		var lp = Vector3i(lx, y, lz)
		if chunk.voxel_data.has(lp) and chunk.voxel_data[lp] == GRASS_BLOCK_ID:
			return y + 1 # Spawn just above the grass surface.
	return -1

func check_despawn():
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for child in get_children():
		if child.has_method("take_damage"):
			if child.global_position.distance_to(player.global_position) > despawn_range:
				child.queue_free()
