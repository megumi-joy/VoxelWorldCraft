extends Node3D

@onready var voxel_world = $VoxelWorld

func _ready():
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
			print("Player spawned and assigned to VoxelWorld")
	else:
		print("ERROR: Could not load Player scene")
