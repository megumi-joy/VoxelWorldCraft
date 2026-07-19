extends CanvasLayer
# Full-screen overlay shown while VoxelWorld builds its initial ring of
# chunks (Scenes/World.tscn only). Owner feedback (mid=644): "мир долго
# грузится -- можно прогресс-линии и мб размер и скорость и текст на экране
# загрузки" (world takes a long time to load -- progress bar, size/speed
# stats, and text on the loading screen).
#
# Progress is driven entirely by VoxelWorld's real
# initial_load_progress(loaded, total) / initial_load_complete() signals (see
# Scripts/World/VoxelWorld.gd) -- NOT a fake timer. VoxelWorld also paces the
# initial chunk build across frames now (a few chunks per _process() tick
# instead of the whole render_distance box in one frame), which is the other
# half of the "loads for a long time" complaint: previously the entire
# multi-second build happened inside a single frozen frame, so a progress bar
# would never have had a chance to animate regardless of what drove it.
#
# Owner feedback (mid=646): he didn't know things like the inventory/bed
# already exist. The rotating tip line below doubles as control-discovery
# text -- the real key bindings from Player.gd's add_input_mapping() /
# manual_interaction_check(), not made-up ones.

@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var progress_bar: ProgressBar = $CenterContainer/Panel/Margin/VBox/ProgressBar
@onready var percent_label: Label = $CenterContainer/Panel/Margin/VBox/PercentLabel
@onready var status_label: Label = $CenterContainer/Panel/Margin/VBox/StatusLabel
@onready var stats_label: Label = $CenterContainer/Panel/Margin/VBox/StatsLabel
@onready var tip_label: Label = $CenterContainer/Panel/Margin/VBox/TipLabel

# ---- Bright hypercasual palette (matches Scripts/UI/HUD.gd) ----
const COL_PANEL_BG := Color(1.0, 0.97, 0.88, 0.95)
const COL_PANEL_BORDER := Color(0.16, 0.09, 0.04, 1.0)
const COL_TEXT := Color(0.16, 0.09, 0.04, 1.0)
const COL_BAR_BG := Color(0.35, 0.32, 0.28)
const COL_BAR_FILL := Color(0.30, 0.65, 0.95)

# Decorative-only stage text keyed off overall progress fraction. Chunk.gd
# actually does terrain+structures+ore+mesh all in one pass per chunk (there
# isn't a real discrete "phase" spanning the whole world to report), so this
# is an honest approximation of what's *roughly* happening, not a literal
# readout of the current instruction.
const STAGE_TEXT := [
	{"until": 0.15, "text": "Генерация рельефа…"},
	{"until": 0.45, "text": "Расстановка биомов и растений…"},
	{"until": 0.75, "text": "Расчёт залежей руды…"},
	{"until": 1.00, "text": "Построение геометрии чанков…"},
]

# Rotating tips: real control hints (owner mid=646 -- players didn't know
# inventory/bed/crafting already exist), sourced from Player.gd's
# add_input_mapping() (WASD/SPACE/SHIFT/E/J) and manual_interaction_check()
# (LMB/RMB + bed/crafting-table interact()).
const TIPS := [
	"Совет: WASD — движение, ПРОБЕЛ — прыжок, SHIFT — бег",
	"Совет: E — открыть инвентарь",
	"Совет: J — полевой журнал",
	"Совет: ЛКМ — сломать блок, ПКМ — поставить или использовать",
	"Совет: ПКМ по кровати ночью — пропустить время до утра",
	"Совет: ПКМ по верстаку — крафт предметов",
]

var _voxel_world: Node = null
var _start_msec := 0
var _tip_index := 0
var _tip_timer: Timer

func _ready() -> void:
	# Headless (automated tests/demo drivers -- see LaunchTest.gd) never need
	# this: VoxelWorld drains its whole initial batch in one call when
	# headless, so there's nothing to visibly animate, and no point paying
	# for a Timer / signal hookup on the CI path.
	#
	# NOTE: OS.has_feature("headless") reads false even under `godot
	# --headless` in this project's build/runner -- see AutoTester.gd's
	# take_screenshot() for the documented finding. DisplayServer.get_name()
	# == "headless" is the reliable signal it settled on; matched here.
	if DisplayServer.get_name() == "headless":
		visible = false
		set_process(false)
		return

	_style()
	_start_msec = Time.get_ticks_msec()
	_tip_index = randi() % TIPS.size()
	tip_label.text = TIPS[_tip_index]
	status_label.text = STAGE_TEXT[0]["text"]
	progress_bar.value = 0
	percent_label.text = "0%"

	_tip_timer = Timer.new()
	_tip_timer.wait_time = 3.5
	_tip_timer.autostart = true
	_tip_timer.timeout.connect(_rotate_tip)
	add_child(_tip_timer)

	_voxel_world = get_tree().get_first_node_in_group("voxel_world")
	if _voxel_world and _voxel_world.has_signal("initial_load_progress"):
		_voxel_world.initial_load_progress.connect(_on_progress)
		_voxel_world.initial_load_complete.connect(_on_complete)
		# Edge case: initial load already finished before this screen's
		# _ready() ran (e.g. render_distance so small the whole thing fit in
		# one budgeted frame). Don't get stuck showing a finished bar.
		if "initial_load_done" in _voxel_world and _voxel_world.initial_load_done:
			_on_complete()
	else:
		# No VoxelWorld in this scene (shouldn't happen for World.tscn, but
		# never block on a screen with nothing driving it).
		_on_complete()

func _on_progress(loaded: int, total: int) -> void:
	if total <= 0:
		return

	# Display-only clamp: nothing here stops the player moving during the
	# load (this overlay is visual-only -- see the script header / PR notes
	# on why WASD/mouse-look can't be gated from here without touching
	# Player.gd). If they walk during the paced fill, center_chunk shifts
	# and VoxelWorld can report `loaded` past the latched initial `total`
	# (new chunks entering range count too). Clamp what's DISPLAYED so the
	# bar/percent/count never read past 100%/total; the real signal value
	# is left untouched.
	var loaded_display: int = min(loaded, total)
	progress_bar.max_value = total
	progress_bar.value = loaded_display

	var frac := float(loaded_display) / float(total)
	percent_label.text = "%d%%" % int(round(frac * 100.0))

	var elapsed_sec: float = max(0.05, (Time.get_ticks_msec() - _start_msec) / 1000.0)
	var chunks_per_sec := loaded_display / elapsed_sec
	var pct_per_sec := (frac * 100.0) / elapsed_sec

	# Owner asked for "размер и скорость" -- gen size (total chunks in the
	# current render distance) and live load speed.
	stats_label.text = "Чанков: %d / %d   •   Скорость: %.1f чанк/с (%.0f%%/с)" % [
		loaded_display, total, chunks_per_sec, pct_per_sec
	]

	status_label.text = _stage_text(frac)

func _stage_text(frac: float) -> String:
	for stage in STAGE_TEXT:
		if frac <= stage["until"]:
			return stage["text"]
	return STAGE_TEXT[-1]["text"]

func _on_complete() -> void:
	status_label.text = "Мир готов!"
	if progress_bar.max_value > 0:
		progress_bar.value = progress_bar.max_value
	percent_label.text = "100%"
	if _tip_timer:
		_tip_timer.stop()
	visible = false

func _rotate_tip() -> void:
	_tip_index = (_tip_index + 1) % TIPS.size()
	tip_label.text = TIPS[_tip_index]

func _style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COL_PANEL_BG
	panel_style.set_corner_radius_all(18)
	panel_style.set_border_width_all(5)
	panel_style.border_color = COL_PANEL_BORDER
	panel_style.shadow_color = Color(0, 0, 0, 0.35)
	panel_style.shadow_size = 5
	panel_style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", panel_style)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = COL_BAR_BG
	bar_bg.set_corner_radius_all(10)
	bar_bg.set_border_width_all(3)
	bar_bg.border_color = COL_PANEL_BORDER

	# Same "only round the leading edge" trick as HUD.gd's health/hunger
	# bars -- rounding the trailing edge clips a crescent of background
	# color out of the fill at partial values.
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = COL_BAR_FILL
	bar_fill.corner_radius_top_left = 8
	bar_fill.corner_radius_bottom_left = 8

	progress_bar.add_theme_stylebox_override("background", bar_bg)
	progress_bar.add_theme_stylebox_override("fill", bar_fill)
	progress_bar.show_percentage = false

	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_color", COL_TEXT)

	percent_label.add_theme_font_size_override("font_size", 18)
	percent_label.add_theme_color_override("font_color", COL_TEXT)

	stats_label.add_theme_font_size_override("font_size", 15)
	stats_label.add_theme_color_override("font_color", Color(0.16, 0.09, 0.04, 0.75))

	tip_label.add_theme_font_size_override("font_size", 15)
	tip_label.add_theme_color_override("font_color", Color(0.16, 0.09, 0.04, 0.65))
