extends Node
class_name PerformanceProfiler

@export var duration: float = 25.0 # Longer to allow bot actions
@export var log_interval: float = 1.0

var time_elapsed: float = 0.0
var time_since_log: float = 0.0

func _ready():
	print("--- PERFORMANCE PROFILER STARTED ---")
	print("------------------------------------")
	
	var world_node = get_tree().current_scene
	var voxel_world = world_node.get_node_or_null("VoxelWorld")
	
	if voxel_world:
		# Spawn REAL Player for interaction test
		var player_scene = load("res://Scenes/Player.tscn")
		var player = player_scene.instantiate()
		player.name = "Player"
		world_node.call_deferred("add_child", player)
		player.global_position = Vector3(0, 100, 0)
		
		# Assign to VoxelWorld
		voxel_world.call_deferred("set", "player", player)
		print("Spawned Real Player and assigned to VoxelWorld")
		
		# Add AutoTester to the spawned player
		var tester_script = load("res://Scripts/Testing/AutoTester.gd")
		var tester = Node.new()
		tester.name = "AutoTester"
		tester.set_script(tester_script)
		player.call_deferred("add_child", tester)
		print("AutoTester attached to Player")

func _process(delta):
	time_elapsed += delta
	time_since_log += delta
	
	if time_since_log >= log_interval:
		time_since_log = 0.0
		log_performance()
		
	if time_elapsed >= duration:
		pass # Logic handled by AutoTester

func log_performance():
	var fps = Engine.get_frames_per_second()
	var memory_static = OS.get_static_memory_usage() / 1024 / 1024
	var draw_calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	
	var world_node = get_tree().current_scene
	var voxel_world = world_node.get_node_or_null("VoxelWorld")
	var chunk_count = voxel_world.chunks.size() if voxel_world and voxel_world.get("chunks") else 0
	
	print("METRICS: FPS=%d | RAM=%dMB | DrawCalls=%d | Polys=%d | Chunks=%d" % [fps, memory_static, draw_calls, primitives, chunk_count])
