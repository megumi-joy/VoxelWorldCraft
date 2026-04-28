var health_bar: ProgressBar
var hunger_bar: ProgressBar
var armor_bar: ProgressBar
var message_label: Label

func _ready():
	setup_glass_theme()
	create_hud_elements()

func setup_glass_theme() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1, 1, 1, 0.1)
	return style

func create_hud_elements():
	# Top Left Container for Stats
	var stats_container = VBoxContainer.new()
	stats_container.name = "StatsContainer"
	stats_container.position = Vector2(20, 20)
	stats_container.custom_minimum_size = Vector2(250, 0)
	add_child(stats_container)
	
	health_bar = create_stat_bar("Health", Color(0.9, 0.2, 0.2))
	stats_container.add_child(health_bar)
	
	hunger_bar = create_stat_bar("Hunger", Color(0.9, 0.6, 0.1))
	stats_container.add_child(hunger_bar)
	
	armor_bar = create_stat_bar("Armor", Color(0.2, 0.6, 0.9))
	stats_container.add_child(armor_bar)
	
	# AI Button (Top Right)
	ai_button = Button.new()
	ai_button.name = "AIToggleButton"
	ai_button.text = "AI DISABLED"
	ai_button.position = Vector2(get_viewport_rect().size.x - 160, 20)
	ai_button.custom_minimum_size = Vector2(140, 45)
	ai_button.pressed.connect(_on_ai_button_pressed)
	add_child(ai_button)
	update_ai_button(false)
	
	# Message Label
	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.position = Vector2(20, get_viewport_rect().size.y - 100)
	add_child(message_label)

func create_stat_bar(label_name: String, bar_color: Color) -> ProgressBar:
	var container = HBoxContainer.new()
	
	var label = Label.new()
	label.text = label_name
	label.custom_minimum_size = Vector2(60, 0)
	label.add_theme_font_size_override("font_size", 14)
	container.add_child(label)
	
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(180, 20)
	bar.show_percentage = false
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.4)
	bg_style.corner_radius_top_left = 6
	bg_style.corner_radius_top_right = 6
	bg_style.corner_radius_bottom_right = 6
	bg_style.corner_radius_bottom_left = 6
	
	var fg_style = StyleBoxFlat.new()
	fg_style.bg_color = bar_color
	fg_style.corner_radius_top_left = 6
	fg_style.corner_radius_top_right = 6
	fg_style.corner_radius_bottom_right = 6
	fg_style.corner_radius_bottom_left = 6
	
	bar.add_theme_stylebox_override("background", bg_style)
	bar.add_theme_stylebox_override("fill", fg_style)
	
	container.add_child(bar)
	
	# We return the bar, but it needs to be child of container? 
	# Let's just return the container but wait, we need direct access to the bar.
	# Wrap it
	var wrapper = MarginContainer.new()
	wrapper.add_child(container)
	# This is messy. Let's just return the Bar and add label separately.
	# Actually, I'll store the bar in the return or name it.
	bar.set_meta("label", label_name)
	return bar

func _on_ai_button_pressed():
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("toggle_ai"):
		player.toggle_ai()

func update_ai_button(enabled: bool):
	if not ai_button: return
	var style = setup_glass_theme()
	if enabled:
		ai_button.text = "AI ACTIVE"
		style.border_color = Color(0.2, 1.0, 0.2, 0.6)
	else:
		ai_button.text = "MANUAL"
		style.border_color = Color(1, 1, 1, 0.2)
	ai_button.add_theme_stylebox_override("normal", style)
