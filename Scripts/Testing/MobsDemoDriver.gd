extends Node
## Headless verification driver for the creatures/mobs content batch: two
## new passive animals (Pig.gd/Cow.gd, added alongside the pre-existing
## Sheep.gd) and the pre-existing hostile Mob.gd/MobSpawner.gd night-spawn +
## player-damage wiring. Mirrors TorchSheepDemoDriver.gd/WorldContentDemoDriver.gd's
## conventions: pure content self-check first, then a scripted scene-tree
## timeline with explicit PASS/FAIL CHECK lines, no rendering required.
##
## Only active with --mobs-demo on the command line (see
## Scripts/Tools/LaunchTest.gd).
##
## IMPORTANT on night-forcing: TimeCycle._process() recomputes
## sun.light_energy from `time` every single frame, so forcing
## sun.light_energy directly (as TorchSheepDemoDriver does, purely for
## visual contrast in its recorded clip) gets silently overwritten the very
## next frame. To actually flip MobSpawner's is_night gate
## (`time_cycle.sun.light_energy < 0.1`) we have to drive the underlying
## `time` value itself into the night window (day_length*0.25 .. *0.75,
## see TimeCycle.gd's sun_angle formula) and hold it there every frame for
## the duration of this test, or the outer day/night gate reads day again
## a few frames later and despawn_all_mobs() would pull the hostile back out
## from under the damage assertion.

var player: CharacterBody3D = null
var voxel_world = null
var mob_spawner = null
var animal_spawner = null
var time_cycle = null
var _t: float = 0.0
var _done_steps: Dictionary = {}

var _pig_ref: Node = null
var _raw_meat_before: int = -1
var _hostile_ref: Node = null
var _player_health_before: float = -1.0
var _hold_night: bool = false

func _ready():
	if not OS.get_cmdline_user_args().has("--mobs-demo"):
		queue_free()
		return
	print("[MobsDemo] driver active")
	_self_check()
	_find_world()

func _find_world():
	player = get_tree().get_first_node_in_group("player")
	voxel_world = get_node_or_null("/root/World/VoxelWorld")
	mob_spawner = get_node_or_null("/root/World/MobSpawner")
	animal_spawner = get_node_or_null("/root/World/AnimalSpawner")
	time_cycle = get_node_or_null("/root/World/TimeCycle")
	if not player or not voxel_world or not mob_spawner or not time_cycle:
		await get_tree().create_timer(0.2).timeout
		_find_world()
		return
	player.ai_enabled = false
	print("[MobsDemo] player + world nodes found, starting scripted timeline")

func _process(delta):
	if not player or not voxel_world or not mob_spawner:
		return
	_t += delta

	if _hold_night and time_cycle:
		# Pin the cycle at midnight every frame so MobSpawner's is_night gate
		# stays true (and despawn_all_mobs() stays inert) for the whole
		# hostile-mob section of this test -- see header comment.
		time_cycle.time = time_cycle.day_length * 0.5

	if _t >= 0.5 and not _done_steps.has("spawn_pig"):
		_done_steps["spawn_pig"] = true
		_spawn_pig()

	if _t >= 0.8 and not _done_steps.has("check_pig_spawned"):
		_done_steps["check_pig_spawned"] = true
		_check_pig_spawned()

	if _t >= 1.0 and not _done_steps.has("kill_pig"):
		_done_steps["kill_pig"] = true
		_kill_pig_and_record_before()

	if _t >= 1.3 and not _done_steps.has("check_pig_drop"):
		_done_steps["check_pig_drop"] = true
		_check_pig_drop()

	if _t >= 1.6 and not _done_steps.has("force_night"):
		_done_steps["force_night"] = true
		_force_night()

	if _t >= 1.9 and not _done_steps.has("check_night_gate"):
		_done_steps["check_night_gate"] = true
		_check_night_gate()

	if _t >= 2.1 and not _done_steps.has("spawn_hostile"):
		_done_steps["spawn_hostile"] = true
		_spawn_hostile_adjacent()

	if _t >= 2.4 and not _done_steps.has("check_hostile_spawned"):
		_done_steps["check_hostile_spawned"] = true
		_check_hostile_spawned()

	if _t >= 3.6 and not _done_steps.has("check_player_damage"):
		_done_steps["check_player_damage"] = true
		_check_player_damage()

	if _t >= 4.0 and not _done_steps.has("quit"):
		_done_steps["quit"] = true
		print("[MobsDemo] t=", String.num(_t, 2), " all steps done, quitting")
		get_tree().quit()

	# Safety self-terminate well beyond the scripted timeline above.
	if _t >= 40.0 and not _done_steps.has("safety_quit"):
		_done_steps["safety_quit"] = true
		print("[MobsDemo] t=", String.num(_t, 2), " safety timeout, quitting")
		get_tree().quit()

# --- Step 1: passive animal (Pig) spawns, exists, drops on death ----------

func _spawn_pig() -> void:
	var scene = load("res://Scenes/Pig.tscn")
	if not scene:
		print("[MobsDemo] WARNING: could not load Pig.tscn")
		return
	var pig = scene.instantiate()
	pig.position = player.global_position + Vector3(0, -1.0, -3.0)
	get_tree().current_scene.add_child(pig)
	_pig_ref = pig
	print("[MobsDemo] t=", String.num(_t, 2), " spawned Pig at ", pig.position)

func _check_pig_spawned() -> void:
	var animals = get_tree().get_nodes_in_group("animals")
	var ok = animals.size() > 0 and is_instance_valid(_pig_ref)
	print("[MobsDemo] CHECK passive animal (Pig) spawned + present in 'animals' group (count=",
		animals.size(), "): ", "PASS" if ok else "FAIL")
	if is_instance_valid(_pig_ref):
		print("[MobsDemo] CHECK Pig has take_damage(): ",
			"PASS" if _pig_ref.has_method("take_damage") else "FAIL",
			" health=", _pig_ref.health if "health" in _pig_ref else "n/a")

func _kill_pig_and_record_before() -> void:
	_raw_meat_before = _count_item(94) # Raw Meat
	if is_instance_valid(_pig_ref):
		_pig_ref.take_damage(9999.0, "test")
		print("[MobsDemo] t=", String.num(_t, 2), " dealt lethal damage to Pig, raw_meat_before=", _raw_meat_before)
	else:
		print("[MobsDemo] WARNING: Pig ref invalid before kill")

func _check_pig_drop() -> void:
	var raw_meat_after = _count_item(94)
	var pig_gone = not is_instance_valid(_pig_ref) or _pig_ref.is_queued_for_deletion()
	var ok_drop = raw_meat_after > _raw_meat_before
	print("[MobsDemo] CHECK Pig died (removed from tree): ", "PASS" if pig_gone else "FAIL")
	print("[MobsDemo] CHECK Pig drop -- Raw Meat count ", _raw_meat_before, " -> ", raw_meat_after,
		": ", "PASS" if ok_drop else "FAIL")

# --- Step 2: force night, hostile mob spawns ------------------------------

func _force_night() -> void:
	_hold_night = true
	if time_cycle:
		time_cycle.time = time_cycle.day_length * 0.5 # Midnight, see header comment.
	print("[MobsDemo] t=", String.num(_t, 2), " forced TimeCycle.time to midnight (day_length*0.5)")

func _check_night_gate() -> void:
	var light_energy = time_cycle.sun.light_energy if (time_cycle and time_cycle.sun) else 1.0
	# Exact expression MobSpawner._process() uses to gate hostile spawning.
	var is_night = light_energy < 0.1
	print("[MobsDemo] CHECK MobSpawner's is_night gate (sun.light_energy=", light_energy,
		" < 0.1): ", "PASS" if is_night else "FAIL")

func _spawn_hostile_adjacent() -> void:
	# Capture health BEFORE the hostile even exists, so the delta assertion
	# in _check_player_damage() can't be clipped by an attack landing in the
	# gap between spawn and the next scripted check (that gap is a couple
	# of frames -- easily enough for Mob.gd's first attack, since it's
	# already in attack_range the instant it spawns adjacent).
	if player and player.stats:
		_player_health_before = player.stats.health
		print("[MobsDemo] player health before hostile contact: ", _player_health_before)

	# Deterministic spawn via the real production entry point
	# (MobSpawner.spawn_mob_at), rather than waiting on try_spawn_mob()'s
	# randf()<0.02-per-tick timer -- avoids a flaky, probabilistic test
	# while still exercising the exact function the timer-driven path calls.
	var pos = player.global_position + Vector3(1.0, 0, 0)
	if mob_spawner and mob_spawner.has_method("spawn_mob_at"):
		mob_spawner.spawn_mob_at(pos, "res://Scenes/Mob.tscn")
		var mobs = get_tree().get_nodes_in_group("mobs")
		if mobs.size() > 0:
			_hostile_ref = mobs[mobs.size() - 1]
		print("[MobsDemo] t=", String.num(_t, 2), " spawned hostile Mob adjacent to player at ", pos)
	else:
		print("[MobsDemo] WARNING: MobSpawner.spawn_mob_at not found")

func _check_hostile_spawned() -> void:
	var mobs = get_tree().get_nodes_in_group("mobs")
	var ok = mobs.size() > 0
	print("[MobsDemo] CHECK hostile mob spawned at night, present in 'mobs' group (count=",
		mobs.size(), "): ", "PASS" if ok else "FAIL")

# --- Step 3: hostile mob damages the player on contact --------------------

func _check_player_damage() -> void:
	if not player or not player.stats:
		print("[MobsDemo] CHECK hostile mob damages player: FAIL (no player/stats)")
		return
	var health_after = player.stats.health
	var delta = _player_health_before - health_after
	var ok = delta > 0.0
	print("[MobsDemo] CHECK hostile mob damages player on contact -- health ",
		_player_health_before, " -> ", health_after, " (delta=", delta, "): ",
		"PASS" if ok else "FAIL")

# --- Helpers ---------------------------------------------------------------

func _count_item(item_id: int) -> int:
	if not player:
		return 0
	var inv = player.get_node_or_null("Inventory")
	if not inv:
		return 0
	var total = 0
	for slot in inv.items:
		if slot and slot.id == item_id:
			total += slot.count
	return total

# Pure ItemDatabase/scene self-check -- no world/player needed, runs
# immediately (same idiom as TorchSheepDemoDriver.gd's _self_check).
func _self_check() -> void:
	var checks = {
		"Raw Meat (94) registered": ItemDatabase.get_item(94) != null,
		"Leather (99) registered as RESOURCE": ItemDatabase.get_item(99) != null
			and ItemDatabase.get_item(99).name == "Leather",
	}
	var pass_count = 0
	for label in checks:
		var ok = checks[label]
		if ok: pass_count += 1
		print("[MobsDemo] CHECK ", label, ": ", "PASS" if ok else "FAIL")

	var pig_scene = load("res://Scenes/Pig.tscn")
	var pig_inst = pig_scene.instantiate() if pig_scene else null
	var pig_ok = pig_inst != null and pig_inst.has_method("take_damage")
	print("[MobsDemo] CHECK Pig.tscn instantiates with take_damage(): ", "PASS" if pig_ok else "FAIL")
	if pig_ok: pass_count += 1
	if pig_inst: pig_inst.queue_free()

	var cow_scene = load("res://Scenes/Cow.tscn")
	var cow_inst = cow_scene.instantiate() if cow_scene else null
	var cow_ok = cow_inst != null and cow_inst.has_method("take_damage")
	print("[MobsDemo] CHECK Cow.tscn instantiates with take_damage(): ", "PASS" if cow_ok else "FAIL")
	if cow_ok: pass_count += 1
	if cow_inst: cow_inst.queue_free()

	var mob_scene = load("res://Scenes/Mob.tscn")
	var mob_inst = mob_scene.instantiate() if mob_scene else null
	var mob_ok = mob_inst != null and mob_inst.has_method("attack_player") and mob_inst.has_method("take_damage")
	print("[MobsDemo] CHECK Mob.tscn (hostile) instantiates with attack_player()+take_damage(): ",
		"PASS" if mob_ok else "FAIL")
	if mob_ok: pass_count += 1
	if mob_inst: mob_inst.queue_free()

	print("[MobsDemo] self-check: ", pass_count, "/", checks.size() + 3, " passed")
