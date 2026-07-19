extends Control
# Proper start-screen main menu, shown at launch (see project.godot's
# run/main_scene). Title + version, "Играть / Play" (loads the world via
# NetworkManager.host_game() -> World.tscn), "Настройки / Settings"
# (toggles the same shared SettingsPanel Player.tscn uses under gameplay),
# "Обновления" (changelog + update-check panel, see below), and "Выход /
# Quit".
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
#
# ---- Visual polish + updates panel (this batch) ----
# Buttons get a bright/chunky themed StyleBoxFlat per button (fill + border
# + shadow + distinct hover/pressed shades), matching the palette already
# established in HUD.gd/SettingsPanel.gd rather than inventing a new one.
#
# All of it -- button styling, the new "Обновления" button, the changelog
# panel, the HTTPRequest used by "Проверить обновления" -- is built here in
# code rather than authored into MainMenu.tscn. That keeps this scene file's
# diff at zero, which matters because a concurrent branch
# (feat/loading-screen-progress) touches this same scene's Play -> world
# transition; a code-only UI addition can't conflict with a .tscn edit.
# _on_play_pressed() itself is untouched.
#
# The version/date label and the update-checker's "local version" both read
# res://build_info.json via BuildInfoLoader.gd, a small file CI (and
# optionally a local pre-commit hook) auto-regenerates from git on every
# build -- see scripts/stamp_build_info.sh + RELEASING.md. That's the fix
# for the version label having previously gone stale (it used to read
# project.godot's hand-maintained config/version directly, which nobody
# reliably bumped).

const COL_PANEL_BG := Color(1.0, 0.97, 0.88, 0.97)
const COL_PANEL_BORDER := Color(0.16, 0.09, 0.04, 1.0)
const COL_TEXT := Color(0.16, 0.09, 0.04, 1.0)
# Bright hypercasual palette, reusing/matching the colors HUD.gd and
# SettingsPanel.gd already established elsewhere in the project (AI-on
# green, AI-off/settings blue, close/quit red, slider-accent amber) so the
# menu reads as part of the same visual language, not a new one.
const COL_PLAY := Color(0.30, 0.80, 0.40, 1.0)
const COL_SETTINGS := Color(0.30, 0.55, 0.95, 1.0)
const COL_UPDATES := Color(1.0, 0.75, 0.05, 1.0)
const COL_QUIT := Color(0.95, 0.35, 0.28, 1.0)

const UPDATE_CHECK_URL := "https://api.github.com/repos/megumi-joy/VoxelWorldCraft/releases/latest"
const UPDATE_USER_AGENT := "VoxelWorldCraft-UpdateChecker"

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "updates"
const SETTINGS_KEY_AUTOCHECK := "auto_check_on_launch"

@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var button_column: VBoxContainer = $VBoxContainer
@onready var version_label: Label = $VersionLabel
@onready var settings_panel = $SettingsPanel

var _starting := false

# Loaded once in _ready() from res://build_info.json -- see BuildInfoLoader.gd.
var _build_info: Dictionary = {}

# Built in code in _ready() -- see _build_updates_button()/_build_updates_panel().
var _updates_button: Button
var _updates_dim: ColorRect
var _update_result_label: Label
var _check_updates_button: Button
var _autocheck_box: CheckBox
var _http_request: HTTPRequest

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Version + "last updated" shown on the menu itself, read from
	# res://build_info.json (see BuildInfoLoader.gd) -- a small committed
	# file that CI (authoritative) and an optional local pre-commit hook
	# regenerate from git, so this never silently goes stale the way a
	# hand-maintained project.godot version string previously did. See
	# RELEASING.md; _ready() below warns to the console if this ever
	# disagrees with ChangelogFeed.gd's newest entry.
	_build_info = BuildInfoLoader.load_info()
	var version := _current_version()
	version_label.text = "v%s · обновлено %s" % [version, _current_build_date()]
	_warn_if_version_drifted(version)

	_style_menu_buttons()
	_build_updates_button()
	_build_updates_panel()
	_build_http_request()

	if _load_autocheck_setting():
		_check_for_updates()

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

func _unhandled_input(event: InputEvent) -> void:
	if _updates_dim and _updates_dim.visible and event.is_action_pressed("ui_cancel"):
		_close_updates_panel()
		get_viewport().set_input_as_handled()

# ---- Version / build-info ----
# _build_info is loaded once in _ready() (see BuildInfoLoader.gd) and reused
# by both the version label and the update-check's "local version" compare,
# rather than re-reading/re-parsing build_info.json on every call.

func _current_version() -> String:
	return String(_build_info.get("version", "0.0.0"))

func _current_build_date() -> String:
	return String(_build_info.get("date", "?"))

func _warn_if_version_drifted(version: String) -> void:
	if ChangelogFeed.ENTRIES.is_empty():
		return
	var newest_entry_version: String = String(ChangelogFeed.ENTRIES[0].get("version", version))
	if newest_entry_version != version:
		push_warning(
			"MainMenu: build_info.json's version (%s) doesn't match ChangelogFeed.ENTRIES[0]'s version (%s) -- see RELEASING.md"
			% [version, newest_entry_version]
		)

# ---- Button theming ----
# Bright, chunky, rounded StyleBoxFlat per button with a fill color, a dark
# outline (matches the HUD's panel border), a drop shadow, and distinct
# hover (lightened) / pressed (darkened, flatter shadow) states -- the same
# StyleBoxFlat-per-state pattern HUD.gd/SettingsPanel.gd already use for the
# AI toggle / close button, just with real hover/pressed variance added.

func _style_menu_buttons() -> void:
	_style_button(play_button, COL_PLAY, 22)
	_style_button(settings_button, COL_SETTINGS, 18)
	_style_button(quit_button, COL_QUIT, 18)

func _make_button_style(bg: Color, shadow_size: int, shadow_offset_y: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(4)
	sb.border_color = COL_PANEL_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = shadow_size
	sb.shadow_offset = Vector2(0, shadow_offset_y)
	return sb

func _style_button(button: Button, bg: Color, font_size: int) -> void:
	var normal := _make_button_style(bg, 5, 3.0)
	var hover := _make_button_style(bg.lightened(0.15), 6, 3.0)
	var pressed := _make_button_style(bg.darkened(0.15), 2, 1.0)
	var disabled := _make_button_style(bg.lerp(Color(0.6, 0.6, 0.6), 0.55), 2, 1.0)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color(1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	button.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02))
	button.add_theme_constant_override("outline_size", 3)

# ---- "Обновления" button + panel ----
# Inserted into the existing VBoxContainer (fetched via button_column,
# unlike play/settings/quit this one has no matching .tscn node) between
# Settings and Quit, so Play stays the unambiguous first action and Quit
# stays last. Doesn't touch PlayButton/SettingsButton/QuitButton or their
# authored .tscn positions.

func _build_updates_button() -> void:
	_updates_button = Button.new()
	_updates_button.name = "UpdatesButton"
	_updates_button.text = "Обновления"
	_updates_button.custom_minimum_size = Vector2(0, 44)
	_updates_button.pressed.connect(_open_updates_panel)
	button_column.add_child(_updates_button)
	button_column.move_child(_updates_button, quit_button.get_index())
	_style_button(_updates_button, COL_UPDATES, 18)

# Same DimBackground(ColorRect) -> PanelBox(PanelContainer) -> Margin ->
# VBox structure Scenes/SettingsPanel.tscn already uses for its overlay, just
# built here in code instead of a second hand-authored .tscn.
func _build_updates_panel() -> void:
	_updates_dim = ColorRect.new()
	_updates_dim.name = "UpdatesDimBackground"
	_updates_dim.color = Color(0.05, 0.03, 0.02, 0.55)
	_updates_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_updates_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_updates_dim.visible = false
	add_child(_updates_dim)

	var panel_box := PanelContainer.new()
	panel_box.anchor_left = 0.5
	panel_box.anchor_top = 0.5
	panel_box.anchor_right = 0.5
	panel_box.anchor_bottom = 0.5
	panel_box.offset_left = -260.0
	panel_box.offset_top = -260.0
	panel_box.offset_right = 260.0
	panel_box.offset_bottom = 260.0
	panel_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_updates_dim.add_child(panel_box)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COL_PANEL_BG
	panel_style.set_corner_radius_all(20)
	panel_style.set_border_width_all(5)
	panel_style.border_color = COL_PANEL_BORDER
	panel_style.shadow_color = Color(0, 0, 0, 0.4)
	panel_style.shadow_size = 8
	panel_style.shadow_offset = Vector2(0, 5)
	panel_box.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel_box.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ЧТО НОВОГО"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COL_TEXT)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)

	# Newest first, straight from ChangelogFeed.ENTRIES' authored order.
	for entry in ChangelogFeed.ENTRIES:
		_add_changelog_entry(content, entry)

	vbox.add_child(HSeparator.new())

	var check_row := HBoxContainer.new()
	check_row.add_theme_constant_override("separation", 12)
	vbox.add_child(check_row)

	_check_updates_button = Button.new()
	_check_updates_button.text = "Проверить обновления"
	_check_updates_button.custom_minimum_size = Vector2(220, 46)
	_check_updates_button.pressed.connect(_on_check_updates_pressed)
	_style_button(_check_updates_button, COL_SETTINGS, 16)
	check_row.add_child(_check_updates_button)

	_update_result_label = Label.new()
	_update_result_label.text = "Нажмите, чтобы проверить обновление"
	_update_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_update_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_result_label.add_theme_font_size_override("font_size", 15)
	_update_result_label.add_theme_color_override("font_color", COL_TEXT)
	check_row.add_child(_update_result_label)

	_autocheck_box = CheckBox.new()
	_autocheck_box.text = "Автопроверка при запуске"
	_autocheck_box.button_pressed = _load_autocheck_setting()
	_autocheck_box.add_theme_color_override("font_color", COL_TEXT)
	_autocheck_box.add_theme_color_override("font_hover_color", COL_TEXT)
	_autocheck_box.add_theme_color_override("font_pressed_color", COL_TEXT)
	_autocheck_box.toggled.connect(_on_autocheck_toggled)
	vbox.add_child(_autocheck_box)

	var close_button := Button.new()
	close_button.text = "ЗАКРЫТЬ"
	close_button.custom_minimum_size = Vector2(140, 48)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(_close_updates_panel)
	_style_button(close_button, COL_QUIT, 16)
	vbox.add_child(close_button)

func _add_changelog_entry(parent: VBoxContainer, entry: Dictionary) -> void:
	var header := Label.new()
	header.text = "v%s — %s" % [entry.get("version", "?"), entry.get("date", "?")]
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", COL_PLAY.darkened(0.15))
	parent.add_child(header)

	for line in entry.get("lines", []):
		var line_label := Label.new()
		line_label.text = "•  " + String(line)
		line_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		line_label.add_theme_font_size_override("font_size", 15)
		line_label.add_theme_color_override("font_color", COL_TEXT)
		parent.add_child(line_label)

func _open_updates_panel() -> void:
	_updates_dim.visible = true

func _close_updates_panel() -> void:
	_updates_dim.visible = false

# ---- "Проверить обновления" ----
# Compares the local version (build_info.json's, via _current_version())
# against the latest published GitHub Release's tag. Handles both "no
# releases published yet" (404 -- true today for this repo: tags exist but
# no Release object does) and network errors without erroring out.

func _build_http_request() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "UpdateCheckRequest"
	add_child(_http_request)
	_http_request.request_completed.connect(_on_update_check_completed)

func _on_check_updates_pressed() -> void:
	_check_for_updates()

func _check_for_updates() -> void:
	if not _http_request:
		return
	_show_update_result("Проверка...")
	if _check_updates_button:
		_check_updates_button.disabled = true
	var headers := ["User-Agent: " + UPDATE_USER_AGENT]
	var err := _http_request.request(UPDATE_CHECK_URL, headers)
	if err != OK:
		_show_update_result("Не удалось проверить обновление")
		if _check_updates_button:
			_check_updates_button.disabled = false

func _on_update_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _check_updates_button:
		_check_updates_button.disabled = false

	if result != HTTPRequest.RESULT_SUCCESS:
		_show_update_result("Не удалось проверить обновление (нет сети)")
		return
	if response_code == 404:
		_show_update_result("Релизы ещё не опубликованы. У вас v%s" % _current_version())
		return
	if response_code != 200:
		_show_update_result("Не удалось проверить обновление (код %d)" % response_code)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_show_update_result("Не удалось разобрать ответ сервера")
		return
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY or not data.has("tag_name"):
		_show_update_result("Не удалось разобрать ответ сервера")
		return

	var remote_tag: String = String(data["tag_name"])
	var local_version := _current_version()
	if _compare_versions(remote_tag, local_version) > 0:
		_show_update_result("Доступна новая версия %s" % remote_tag)
	else:
		_show_update_result("У вас последняя версия v%s" % local_version)

func _show_update_result(text: String) -> void:
	if _update_result_label:
		_update_result_label.text = text

# ---- Version comparison ----
# Numeric, dot-separated compare ("v1.2.3" / "1.2.3" / "1.2" all accepted;
# missing trailing components treated as 0). Good enough for the semver-ish
# "vX.Y.Z" tags this repo actually uses -- not a full semver parser (no
# pre-release/build-metadata handling), which is fine for a simple "is a
# newer numbered release available" check.

static func _parse_version(v: String) -> Array:
	v = v.strip_edges()
	if v.begins_with("v") or v.begins_with("V"):
		v = v.substr(1)
	var nums: Array = []
	for part in v.split("."):
		nums.append(int(part) if part.is_valid_int() else 0)
	return nums

static func _compare_versions(a: String, b: String) -> int:
	var pa := _parse_version(a)
	var pb := _parse_version(b)
	var length: int = max(pa.size(), pb.size())
	for i in range(length):
		var xa: int = pa[i] if i < pa.size() else 0
		var xb: int = pb[i] if i < pb.size() else 0
		if xa != xb:
			return 1 if xa > xb else -1
	return 0

# ---- Autocheck-on-launch setting ----
# Persisted to the same user://settings.cfg document HudSettings.gd /
# GraphicsSettings.gd already share (own "updates" section), same
# load-merge-save pattern as HudSettings.gd's _load_from_disk()/
# _save_to_disk(). Defaults OFF: this menu can run in CI/offline contexts
# and an opt-in avoids ever firing a network request without the player
# having asked for it at least once.

func _load_autocheck_setting() -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return false
	return bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY_AUTOCHECK, false))

func _on_autocheck_toggled(pressed: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # best-effort merge -- keep HudSettings'/GraphicsSettings' sections intact
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY_AUTOCHECK, pressed)
	cfg.save(SETTINGS_PATH)
