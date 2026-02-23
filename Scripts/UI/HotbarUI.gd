extends Control

@onready var grid = $HBoxContainer
var inventory
var slot_selected: int = 0

signal on_slot_selected(item_id)

func _ready():
	# Find player inventory
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_node("Inventory"):
		inventory = player.get_node("Inventory")
		inventory.inventory_changed.connect(update_ui)
		
		# Connect to stats for gold
		if player.has_node("PlayerStats"):
			player.get_node("PlayerStats").gold_changed.connect(func(_val): update_ui())
			
		update_ui()
	
	set_process_input(true)

func _input(event):
	if event is InputEventKey:
		if event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			slot_selected = event.keycode - KEY_1
			update_selection()
	
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				slot_selected = (slot_selected - 1 + 9) % 9
				update_selection()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				slot_selected = (slot_selected + 1) % 9
				update_selection()

func update_selection():
	# Visual update
	update_ui()
	# Notify player logic
	if inventory and inventory.items.size() > slot_selected:
		var item = inventory.items[slot_selected]
		if item:
			on_slot_selected.emit(item.id)
		else:
			on_slot_selected.emit(0) # 0 = Empty

func update_ui():
	if not inventory: return
	
	# Clear existing
	for child in grid.get_children():
		child.queue_free()
		
	# Display Gold (Simple Label in the corner or part of hotbar)
	var gold_label = get_node_or_null("GoldLabel")
	if not gold_label:
		gold_label = Label.new()
		gold_label.name = "GoldLabel"
		gold_label.position = Vector2(10, -40) # Higher above hotbar
		# Add a background or shadow if possible, but keep it simple
		add_child(gold_label)
	
	var world = get_tree().get_first_node_in_group("world")
	var stats_node = null
	var p = get_tree().get_first_node_in_group("player")
	if p and p.has_node("PlayerStats"):
		gold_label.text = "G: " + str(p.get_node("PlayerStats").gold)
	else:
		gold_label.text = "G: 0"
	
	# Build Hotbar (First 9 slots)
	for i in range(9):
		var slot = Panel.new()
		slot.custom_minimum_size = Vector2(50, 50)
		grid.add_child(slot)
		
		# Highlight selected
		if i == slot_selected:
			slot.modulate = Color(1, 1, 0) # Yellow highlight
		
		if i < inventory.size and inventory.items[i]:
			var item = inventory.items[i]
			# Access autoload directly via node path to avoid lint issues
			var db = get_node("/root/ItemDatabase")
			var item_data
			if db:
				item_data = db.get_item(item.id)
			
			if item_data:
				var label = Label.new()
				label.text = str(item_data.name) + "\n" + str(item.count)
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				label.autowrap_mode = TextServer.AUTOWRAP_WORD
				label.size = Vector2(50, 50)
				slot.add_child(label)
