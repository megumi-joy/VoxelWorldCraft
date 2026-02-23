extends Control

var ai_button: Button

func _ready():
	# Create AI Toggle Button
	ai_button = Button.new()
	ai_button.name = "AIToggleButton"
	ai_button.text = "AI DISABLED"
	ai_button.position = Vector2(20, 20)
	ai_button.size = Vector2(120, 40)
	
	# Style
	update_ai_button(false)
	
	ai_button.pressed.connect(_on_ai_button_pressed)
	add_child(ai_button)

func _on_ai_button_pressed():
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("toggle_ai"):
		player.toggle_ai()

func update_ai_button(enabled: bool):
	if not ai_button: return
	
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_right = 5
	style.corner_radius_bottom_left = 5
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	
	if enabled:
		ai_button.text = "AI ENABLED"
		style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
		style.border_color = Color(1.0, 0.5, 0.0) # Orange
		ai_button.add_theme_color_override("font_color", Color.WHITE)
	else:
		ai_button.text = "AI DISABLED"
		style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
		style.border_color = Color(0.5, 0.5, 0.5) # Gray
		ai_button.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		
	ai_button.add_theme_stylebox_override("normal", style)
	ai_button.add_theme_stylebox_override("hover", style)
	ai_button.add_theme_stylebox_override("pressed", style)
