extends Control
# Proper start-screen main menu, shown at launch (see project.godot's
# run/main_scene). Title + version, "Играть / Play" (loads the world via
# NetworkManager.host_game() -> World.tscn), "Настройки / Settings"
# (toggles the same shared SettingsPanel Player.tscn uses under gameplay),
# and "Выход / Quit".
#
# Replaces the old prototype menu, which auto-started Single Player after a
# 0.5s countdown -- in practice that meant the game always "booted straight
# into the world" no matter what the menu showed, regardless of what was on
# screen. That's exactly what the owner asked to fix ("версии лаунчер в
# меню" -- a real launcher-style menu with the version visible). The old
# Host/Join network-address UI is dropped too: NetworkManager.host_game()
# (what Play calls) still opens a local ENet server under the hood for the
# existing multiplayer scaffolding, so nothing about that layer changes --
# only the menu's own UI surface simplifies down to what a single-player
# prototype actually needs.
#
# Note this menu is NOT in the path of any headless test/demo run:
# --run-tests / --movement-demo / --wave2-demo / etc. all load
# Scenes/LaunchTest.tscn directly as the CLI scene argument (see
# Scripts/Tools/LaunchTest.gd), which bypasses project.godot's
# run/main_scene entirely and calls NetworkManager.host_game() itself. So
# this menu only ever shows up in real, manually-launched play.

@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var version_label: Label = $VersionLabel
@onready var settings_panel = $SettingsPanel

var _starting := false

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Version shown on the menu itself, read straight from project.godot's
	# config/version (application/config/version) so it can never drift out
	# of sync with a separately-maintained constant -- bump the one place
	# (project.godot, or Project > Project Settings > Application > Config >
	# Version in the editor) and both the title bar and this label follow.
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	version_label.text = "v" + version

func _on_play_pressed() -> void:
	if _starting:
		return # guard against a double-click firing host_game() twice
	_starting = true
	play_button.disabled = true
	NetworkManager.host_game()

func _on_settings_pressed() -> void:
	if settings_panel and settings_panel.has_method("toggle"):
		settings_panel.toggle()

func _on_quit_pressed() -> void:
	get_tree().quit()
