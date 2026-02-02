extends Control

var furnace # : Furnace (Loose typing to fix lint)
@onready var input_slot = $Panel/InputSlot
@onready var fuel_slot = $Panel/FuelSlot
@onready var output_slot = $Panel/OutputSlot
@onready var burn_bar = $Panel/BurnBar
@onready var cook_bar = $Panel/CookBar

func set_furnace(f: Node):
	furnace = f
	furnace.furnace_updated.connect(update_ui)
	update_ui()

func _process(_delta):
	if visible and furnace:
		update_bars()

func update_bars():
	if furnace.max_burn_time > 0:
		burn_bar.value = (furnace.burn_time / furnace.max_burn_time) * 100
	else:
		burn_bar.value = 0
		
	cook_bar.value = (furnace.cook_time / 5.0) * 100

func update_ui():
	# Update slots text similar to inventory
	update_slot_visual(input_slot, furnace.inventory[0])
	update_slot_visual(fuel_slot, furnace.inventory[1])
	update_slot_visual(output_slot, furnace.inventory[2])

func update_slot_visual(slot: Panel, item):
	for child in slot.get_children():
		child.queue_free()
		
	if item:
		var db = get_node("/root/ItemDatabase")
		var data = db.get_item(item.id)
		if data:
			var label = Label.new()
			label.text = str(data.name) + "\n" + str(item.count)
			label.size = Vector2(50, 50)
			slot.add_child(label)
