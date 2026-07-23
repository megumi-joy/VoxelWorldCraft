extends Control
class_name FieldJournalUI
# Field Journal / Codex panel: the naturalist-fantasy core-loop payoff --
# observe -> identify -> catalog. Lists two categories (Plants, Minerals)
# from CodexDatabase.gd; each entry is locked ("??? -- undiscovered") until
# PlayerStats.discovered_species has it (see Player.gd's discovery wiring).
#
# Toggle with the "field_journal" action (J by default), same convention as
# InventoryUI's "inventory" (E). Also exposes open()/close()/toggle()/
# refresh() as a public API independent of the keypress, so a headless demo
# driver (see Scripts/Testing/Wave2DemoDriver.gd) can open it without
# simulating input -- Godot's --write-movie capture has no real keyboard.
#
# Bright/chunky hypercasual style matching HUD.gd -- NOT the old dark
# "glassmorphism" InventoryUI look.

const COL_PANEL_BG := Color(1.0, 0.97, 0.88, 0.97)
const COL_PANEL_BORDER := Color(0.16, 0.09, 0.04, 1.0)
const COL_HEADER_PLANT := Color(0.30, 0.70, 0.32)
const COL_HEADER_MINERAL := Color(0.55, 0.42, 0.75)
const COL_CARD_LOCKED_BG := Color(0.78, 0.76, 0.72, 0.9)
const COL_CARD_UNLOCKED_BG := Color(1.0, 1.0, 0.96, 0.98)
const COL_TEXT_DARK := Color(0.16, 0.09, 0.04)
const COL_TEXT_LOCKED := Color(0.42, 0.40, 0.38)

@onready var journal_panel: PanelContainer = $JournalPanel
@onready var dim_bg: ColorRect = $DimBG
@onready var title_label: Label = $JournalPanel/Margin/OuterVBox/TitleLabel
@onready var hint_label: Label = $JournalPanel/Margin/OuterVBox/HintLabel
# Two side-by-side columns (not one stacked scrolling list) -- with 3 plant
# + 5 mineral entries, a single column needs real scrolling to reach the
# second category at all, which meant a screenshot/video frame taken right
# after opening could show only Plants with the Minerals header cut off at
# the bottom edge and zero mineral entries visible. Two columns put both
# categories on-screen simultaneously.
@onready var plants_vbox: VBoxContainer = $JournalPanel/Margin/OuterVBox/ColumnsHBox/PlantsScroll/PlantsVBox
@onready var minerals_vbox: VBoxContainer = $JournalPanel/Margin/OuterVBox/ColumnsHBox/MineralsScroll/MineralsVBox

func _ready() -> void:
	if not InputMap.has_action("field_journal"):
		InputMap.add_action("field_journal")
		var ev = InputEventKey.new()
		ev.physical_keycode = KEY_J
		InputMap.action_add_event("field_journal", ev)

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_panel()
	_style_title()
	visible = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("field_journal"):
		toggle()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	refresh()

func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _find_stats():
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_node("PlayerStats"):
		return player.get_node("PlayerStats")
	return null

func refresh() -> void:
	if not plants_vbox or not minerals_vbox:
		return
	for child in plants_vbox.get_children():
		child.queue_free()
	for child in minerals_vbox.get_children():
		child.queue_free()

	var stats = _find_stats()

	_add_category_header(plants_vbox, "РАСТЕНИЯ", COL_HEADER_PLANT)
	for entry in CodexDatabase.get_entries_by_category(CodexDatabase.Category.PLANT):
		_add_entry_card(plants_vbox, entry, stats)

	_add_category_header(minerals_vbox, "МИНЕРАЛЫ", COL_HEADER_MINERAL)
	for entry in CodexDatabase.get_entries_by_category(CodexDatabase.Category.MINERAL):
		_add_entry_card(minerals_vbox, entry, stats)

func _style_panel() -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = COL_PANEL_BG
	sb.set_corner_radius_all(22)
	sb.set_border_width_all(6)
	sb.border_color = COL_PANEL_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 5)
	journal_panel.add_theme_stylebox_override("panel", sb)

func _style_title() -> void:
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", COL_TEXT_DARK)
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(0.16, 0.09, 0.04, 0.65))

func _add_category_header(column: VBoxContainer, text: String, accent: Color) -> void:
	var header = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = accent
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	header.add_theme_stylebox_override("panel", style)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3))
	label.add_theme_constant_override("outline_size", 2)
	header.add_child(label)

	column.add_child(header)

func _add_entry_card(column: VBoxContainer, entry: Dictionary, stats) -> void:
	var species_key: String = entry.key
	var discovered: bool = stats != null and stats.is_discovered(species_key)

	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = COL_CARD_UNLOCKED_BG if discovered else COL_CARD_LOCKED_BG
	style.set_corner_radius_all(14)
	style.set_border_width_all(3)
	style.border_color = COL_PANEL_BORDER if discovered else Color(0.35, 0.33, 0.30)
	card.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	var name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(name_label)

	if discovered:
		name_label.text = entry.name
		name_label.add_theme_color_override("font_color", COL_TEXT_DARK)
		for fact_key in entry.facts:
			var fact_label = Label.new()
			fact_label.text = "%s: %s" % [fact_key, entry.facts[fact_key]]
			fact_label.add_theme_font_size_override("font_size", 14)
			fact_label.add_theme_color_override("font_color", COL_TEXT_DARK)
			fact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(fact_label)
	else:
		name_label.text = "??? -- не открыто"
		name_label.add_theme_color_override("font_color", COL_TEXT_LOCKED)
		var hint = Label.new()
		hint.text = "Найдите и соберите, чтобы определить."
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", COL_TEXT_LOCKED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(hint)

	column.add_child(card)
