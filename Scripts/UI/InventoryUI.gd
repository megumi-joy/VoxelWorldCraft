extends Control

@onready var grid = $Panel/GridContainer
var inventory

func _ready():
	# Style the main panel for Glassmorphism
	var panel = $Panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1, 1, 1, 0.2)
	panel.add_theme_stylebox_override("panel", style)
	
	# Find player inventory
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_node("Inventory"):
		inventory = player.get_node("Inventory")
		inventory.inventory_changed.connect(update_ui)
		update_ui()
	
	# Ensure Input Map exists
	if not InputMap.has_action("inventory"):
		InputMap.add_action("inventory")
		var ev = InputEventKey.new()
		ev.physical_keycode = KEY_E
		InputMap.action_add_event("inventory", ev)
	
	set_process_input(true)

func _input(event):
	if event.is_action_pressed("inventory"):
		visible = not visible
		if visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			update_ui()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func update_ui():
	if not inventory: return
	
	# Clear existing
	for child in grid.get_children():
		child.queue_free()
		
	# Rebuild
	for i in range(inventory.size):
		var slot = PanelContainer.new()
		slot.custom_minimum_size = Vector2(60, 60)
		
		# Slot Style
		var slot_style = StyleBoxFlat.new()
		slot_style.bg_color = Color(0.2, 0.2, 0.2, 0.6)
		slot_style.corner_radius_top_left = 5
		slot_style.corner_radius_top_right = 5
		slot_style.corner_radius_bottom_right = 5
		slot_style.corner_radius_bottom_left = 5
		slot.add_theme_stylebox_override("panel", slot_style)
		
		grid.add_child(slot)
		
		var item = inventory.items[i]
		if item:
			var db = get_node("/root/ItemDatabase")
			if db:
				var item_data = db.get_item(item.id)
				if item_data:
					var vbox = VBoxContainer.new()
					slot.add_child(vbox)
					
					# Name
					var label = Label.new()
					label.text = item_data.name
					label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					label.add_theme_font_size_override("font_size", 10)
					vbox.add_child(label)
					
					# Count
					var count_lbl = Label.new()
					count_lbl.text = "x" + str(item.count)
					count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
					count_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
					vbox.add_child(count_lbl)
