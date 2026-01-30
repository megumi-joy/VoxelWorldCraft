extends Node

const PORT = 7777
const DEFAULT_IP = "127.0.0.1"

var peer = ENetMultiplayerPeer.new()

func host_game():
	var error = peer.create_server(PORT)
	if error != OK:
		printerr("Cannot host: " + str(error))
		return
	
	multiplayer.multiplayer_peer = peer
	print("Hosting on port " + str(PORT))
	load_world()

func join_game(address):
	if address == "":
		address = DEFAULT_IP
	
	var error = peer.create_client(address, PORT)
	if error != OK:
		printerr("Cannot join: " + str(error))
		return
	
	multiplayer.multiplayer_peer = peer
	print("Joining " + address + ":" + str(PORT))
	# Level loading will be handled by spawner or manual scene change?
	# For simplicity, client also loads the world scene, but sync happens via Spawner.
	# Actually, usually server tells client to load level.
	# But in Godot 4, if we just switch scene locally, we need to ensure nodes match.
	pass

func load_world():
	get_tree().change_scene_to_file("res://Scenes/World.tscn")
