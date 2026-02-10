extends Control

@onready var single_player_button = $VBoxContainer/SinglePlayerButton
@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinButton
@onready var address_entry = $VBoxContainer/AddressEntry

var auto_start_timer = 0.5 # Fast Start
var auto_started = false
var counting_down = true
var started_game = false

func _ready():
	printerr("MainMenu READY (Fixed v2).")
	printerr("SinglePlayerButton: ", single_player_button)
	if single_player_button:
		single_player_button.pressed.connect(_on_single_player_pressed)
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
	if join_button:
		join_button.pressed.connect(_on_join_pressed)
	
	# Initial check for command line args
	if "--auto-host" in OS.get_cmdline_args():
		auto_start_timer = 0.1

func _process(delta):
	if auto_started or started_game: return
	
	if counting_down and single_player_button:
		auto_start_timer -= delta
		if int(auto_start_timer * 10) % 5 == 0:
			printerr("Timer: ", auto_start_timer)
		single_player_button.text = "Single Player (Auto: %.1f)" % auto_start_timer
		
		# Auto-Start Trigger
		if auto_start_timer <= 0.0:
			printerr("Auto-Starting Single Player NOW...")
			counting_down = false
			started_game = true
			_on_single_player_pressed()
	elif single_player_button:
		single_player_button.text = "Single Player"

func _input(event):
	pass
	# Stop countdown on user interaction (Clicks or Keys only)
	# if counting_down and (event is InputEventMouseButton or event is InputEventKey):
		# print("User Interaction Detected. Cancelling Auto-Start.") # Debug Log
		# counting_down = false
		# if single_player_button:
			# single_player_button.text = "Single Player"
func _on_single_player_pressed():
	printerr("BUTTON PRESSED (Manual or Auto)")
	if started_game and not counting_down: return
	started_game = true
	print("Starting Single Player...")
	NetworkManager.host_game()

func _on_host_pressed():
	NetworkManager.host_game()

func _on_join_pressed():
	NetworkManager.join_game(address_entry.text)
