extends Node3D

@onready var voxel_world = $VoxelWorld

func _ready():
	# Re-apply persisted graphics settings to THIS world's WorldEnvironment /
	# DirectionalLight3D / VoxelWorld -- they're fresh nodes from the .tscn
	# defaults, not the ones any previous world had settings applied to (see
	# GraphicsSettings.gd's "per-scene" tier comment). Safe to call before
	# children's own _ready() logic below: node group membership is set at
	# scene instancing time, and children _ready() before this parent
	# _ready(), so WorldEnvironment/DirectionalLight3D/VoxelWorld are already
	# in the tree and in their groups by now.
	GraphicsSettings.apply_scene_settings()

	# Simple Player Spawn for Single Player / Host
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		spawn_player()

func spawn_player():
	var player_scene = load("res://Scenes/Player.tscn")
	if player_scene:
		var player = player_scene.instantiate()
		player.name = "Player"
		add_child(player)
		
		# Assign player to VoxelWorld
		if voxel_world:
			voxel_world.player = player

			# Player.tscn hardcodes spawn at y=1.7, but terrain columns are
			# filled solid from y=0 up to the generated surface height
			# (Chunk.gd: int((noise+1)*32)+64, i.e. ~64-128). That leaves the
			# player embedded inside solid rock at spawn. Compute the actual
			# surface height at the spawn XZ using the same noise instance/
			# formula Chunk.gd uses, and spawn a couple blocks above it.
			if voxel_world.noise:
				var spawn_x = player.position.x
				var spawn_z = player.position.z
				var surface_height = int((voxel_world.noise.get_noise_2d(spawn_x, spawn_z) + 1) * 32) + 64
				player.position.y = surface_height + 2

			print("Player spawned and assigned to VoxelWorld")
	else:
		print("ERROR: Could not load Player scene")
