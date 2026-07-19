extends Control
## VoxelWorldCraft desktop launcher (pre-Steam distribution path).
##
## Owner's ask (mid=656/657): "нам лучше лаунчер типа до стимов и локал
## удобно" / "можно нам тянуть типа локал а потом сделаем с гитхаба" --
## a Steam-like launcher, pulling updates from a local folder for now,
## GitHub later. This script is the UI + orchestration layer; it never
## talks to a build source directly, only through the UpdateSource
## interface (see UpdateSource.gd) so that later swap is one line, in
## _make_update_source() below.
##
## Config is a small ConfigFile at user://launcher.cfg with two sections:
##   [paths] install_dir, source_dir      -- both configurable via the
##                                           in-app Settings popup
##   [state] installed_version, installed_date -- written by this script
##                                                 after every successful
##                                                 update, never hand-edited

const CONFIG_PATH := "user://launcher.cfg"

const GAME_EXE_NAME_WINDOWS := "VoxelWorldCraft.exe"
const GAME_EXE_NAME_LINUX := "VoxelWorldCraft.x86_64"

@onready var _installed_version_label: Label = $CenterContainer/Card/VBox/InstalledVersionLabel
@onready var _updated_date_label: Label = $CenterContainer/Card/VBox/UpdatedDateLabel
@onready var _status_label: Label = $CenterContainer/Card/VBox/StatusLabel
@onready var _progress: ProgressBar = $CenterContainer/Card/VBox/Progress
@onready var _play_button: Button = $CenterContainer/Card/VBox/ButtonsRow/PlayButton
@onready var _update_button: Button = $CenterContainer/Card/VBox/ButtonsRow/UpdateButton
@onready var _settings_button: Button = $CenterContainer/Card/VBox/SettingsButton

@onready var _settings_popup: PopupPanel = $SettingsPopup
@onready var _install_dir_edit: LineEdit = $SettingsPopup/SettingsVBox/InstallDirRow/InstallDirEdit
@onready var _install_dir_browse: Button = $SettingsPopup/SettingsVBox/InstallDirRow/InstallDirBrowseButton
@onready var _source_dir_edit: LineEdit = $SettingsPopup/SettingsVBox/SourceDirRow/SourceDirEdit
@onready var _source_dir_browse: Button = $SettingsPopup/SettingsVBox/SourceDirRow/SourceDirBrowseButton
@onready var _settings_save: Button = $SettingsPopup/SettingsVBox/SettingsButtonsRow/SettingsSaveButton
@onready var _settings_cancel: Button = $SettingsPopup/SettingsVBox/SettingsButtonsRow/SettingsCancelButton

@onready var _dir_dialog: FileDialog = $DirDialog

var _config := ConfigFile.new()
var _update_source: UpdateSource
var _latest_known_version: String = ""
var _busy := false
## Which LineEdit the currently-open DirDialog should fill in when the
## user picks a folder -- set right before popup_centered().
var _dir_dialog_target: LineEdit = null

func _ready() -> void:
	_load_config()
	_make_update_source()

	_play_button.pressed.connect(_on_play_pressed)
	_update_button.pressed.connect(_on_update_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_settings_save.pressed.connect(_on_settings_save_pressed)
	_settings_cancel.pressed.connect(_on_settings_cancel_pressed)
	_install_dir_browse.pressed.connect(_on_browse_pressed.bind(_install_dir_edit))
	_source_dir_browse.pressed.connect(_on_browse_pressed.bind(_source_dir_edit))
	_dir_dialog.dir_selected.connect(_on_dir_selected)

	_refresh_installed_labels()
	_check_for_updates()

# ---------------------------------------------------------------------
# UpdateSource wiring -- this is the ONE function to change to switch the
# launcher from local-folder builds to GitHub Releases later. Everything
# else in this script only depends on the UpdateSource interface.
# ---------------------------------------------------------------------
func _make_update_source() -> void:
	if _update_source != null:
		_update_source.latest_version_ready.disconnect(_on_latest_version_ready)
		_update_source.update_downloaded.disconnect(_on_update_downloaded)
		_update_source.update_progress.disconnect(_on_update_progress)
		_update_source.queue_free()

	_update_source = LocalFolderSource.new(_get_source_dir())
	# _update_source = GithubReleasesSource.new()  # <- swap to this later

	add_child(_update_source)
	_update_source.latest_version_ready.connect(_on_latest_version_ready)
	_update_source.update_downloaded.connect(_on_update_downloaded)
	_update_source.update_progress.connect(_on_update_progress)

# ---------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------
func _load_config() -> void:
	_config.load(CONFIG_PATH) # ignore error: defaults below cover a missing/fresh file

func _save_config() -> void:
	var err := _config.save(CONFIG_PATH)
	if err != OK:
		push_warning("Launcher: failed to save %s (code %d)" % [CONFIG_PATH, err])

func _default_install_dir() -> String:
	return OS.get_executable_path().get_base_dir().path_join("game")

func _default_source_dir() -> String:
	return OS.get_executable_path().get_base_dir().path_join("builds")

func _get_install_dir() -> String:
	return _config.get_value("paths", "install_dir", _default_install_dir())

func _get_source_dir() -> String:
	return _config.get_value("paths", "source_dir", _default_source_dir())

func _get_installed_version() -> String:
	return _config.get_value("state", "installed_version", "")

func _get_installed_date() -> String:
	return _config.get_value("state", "installed_date", "")

func _set_installed_version(version: String) -> void:
	_config.set_value("state", "installed_version", version)
	_config.set_value("state", "installed_date", Time.get_date_string_from_system())
	_save_config()

# ---------------------------------------------------------------------
# Play
# ---------------------------------------------------------------------
func _game_exe_name() -> String:
	return GAME_EXE_NAME_WINDOWS if OS.get_name() == "Windows" else GAME_EXE_NAME_LINUX

func _game_exe_path() -> String:
	return _get_install_dir().path_join(_game_exe_name())

func _on_play_pressed() -> void:
	var exe_path := _game_exe_path()
	if not FileAccess.file_exists(exe_path):
		_set_status("Игра не установлена. Нажмите «⬇ Обновить», чтобы установить.", true)
		return

	var pid := OS.create_process(exe_path, [])
	if pid <= 0:
		_set_status("Не удалось запустить игру (файл повреждён или не запускается).", true)
	else:
		_set_status("Игра запущена.", false)

# ---------------------------------------------------------------------
# Update check / install flow
# ---------------------------------------------------------------------
func _check_for_updates() -> void:
	if _busy:
		return
	_set_status("Проверка обновлений…", false)
	_update_source.request_latest_version()

func _on_latest_version_ready(result: Dictionary) -> void:
	if not result.get("ok", false):
		_set_status(String(result.get("error", "Не удалось проверить обновления.")), true)
		return

	_latest_known_version = String(result.get("version", ""))
	var installed := _get_installed_version()

	if installed == "":
		_update_button.text = "⬇ Установить"
		_set_status("Игра не установлена. Доступна версия v%s." % _latest_known_version, false)
	elif VersionUtil.is_newer(_latest_known_version, installed):
		_update_button.text = "⬇ Обновить"
		_set_status("Доступно обновление v%s" % _latest_known_version, false)
	else:
		_update_button.text = "⬇ Обновить"
		_set_status("Установлена последняя версия.", false)

func _on_update_pressed() -> void:
	if _busy:
		return
	if _latest_known_version == "":
		_check_for_updates()
		return

	_busy = true
	_update_button.disabled = true
	_play_button.disabled = true
	_progress.visible = true
	_progress.value = 0.0
	_set_status("Загрузка…", false)
	_update_source.fetch_update(_latest_known_version, _get_install_dir())

func _on_update_progress(fraction: float) -> void:
	_progress.value = clampf(fraction, 0.0, 1.0) * 100.0

func _on_update_downloaded(result: Dictionary) -> void:
	_busy = false
	_update_button.disabled = false
	_play_button.disabled = false
	_progress.visible = false

	if not result.get("ok", false):
		_set_status(String(result.get("error", "Не удалось установить обновление.")), true)
		return

	_set_installed_version(_latest_known_version)
	_refresh_installed_labels()
	_set_status("Установлена v%s" % _latest_known_version, false)

# ---------------------------------------------------------------------
# Status / labels
# ---------------------------------------------------------------------
func _set_status(text: String, is_error: bool) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15) if is_error else Color(0.2, 0.35, 0.5))

func _refresh_installed_labels() -> void:
	var installed := _get_installed_version()
	if installed == "":
		_installed_version_label.text = "Игра не установлена"
		_updated_date_label.text = ""
	else:
		_installed_version_label.text = "Установлена v%s" % installed
		var date := _get_installed_date()
		_updated_date_label.text = ("обновлено: %s" % date) if date != "" else ""

# ---------------------------------------------------------------------
# Settings popup
# ---------------------------------------------------------------------
func _on_settings_pressed() -> void:
	_install_dir_edit.text = _get_install_dir()
	_source_dir_edit.text = _get_source_dir()
	_settings_popup.popup_centered()

func _on_settings_save_pressed() -> void:
	var new_install_dir := _install_dir_edit.text.strip_edges()
	var new_source_dir := _source_dir_edit.text.strip_edges()
	_config.set_value("paths", "install_dir", new_install_dir if new_install_dir != "" else _default_install_dir())
	_config.set_value("paths", "source_dir", new_source_dir if new_source_dir != "" else _default_source_dir())
	_save_config()
	_settings_popup.hide()

	_make_update_source() # source_dir may have changed
	_refresh_installed_labels()
	_check_for_updates()

func _on_settings_cancel_pressed() -> void:
	_settings_popup.hide()

func _on_browse_pressed(target_edit: LineEdit) -> void:
	_dir_dialog_target = target_edit
	var current := target_edit.text.strip_edges()
	if current != "" and DirAccess.dir_exists_absolute(current):
		_dir_dialog.current_dir = current
	_dir_dialog.popup_centered()

func _on_dir_selected(dir: String) -> void:
	if _dir_dialog_target != null:
		_dir_dialog_target.text = dir
	_dir_dialog_target = null
