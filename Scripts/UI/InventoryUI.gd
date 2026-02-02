extends Control

@onready var grid = $Panel/GridContainer
var inventory: Inventory

func _ready():
	# Find player inventory
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_node("Inventory"):
		inventory = player.get_node("Inventory")
		inventory.inventory_changed.connect(update_ui)
		update_ui()
	
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
		
	# Rebuild (inefficient but safe for now)
	for i in range(inventory.size):
		var slot = Panel.new()
		slot.custom_minimum_size = Vector2(50, 50)
		grid.add_child(slot)
		
		var item = inventory.items[i]
		if item:
			# Use get_node to avoid static access lint errors, assuming ItemDatabase is autoloaded as "ItemDatabase"
			var db = get_node("/root/ItemDatabase")
			if db:
				var item_data = db.get_item(item.id)
				if item_data:
					var label = Label.new()
					label.text = str(item_data.name) + "\n" + str(item.count)
					label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					label.autowrap_mode = TextServer.AUTOWRAP_WORD
					label.size = Vector2(50, 50)
					slot.add_child(label)
					# TODO: TextureRect if icon exists

# Hotbar updates can be handled here or in a separate script?
# Let's assume HotbarUI will be a separate node reading the same inventory.
