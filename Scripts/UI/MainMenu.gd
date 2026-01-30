extends Control

@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinButton
@onready var address_entry = $VBoxContainer/AddressEntry

func _ready():
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

func _on_host_pressed():
	NetworkManager.host_game()

func _on_join_pressed():
	NetworkManager.join_game(address_entry.text)
