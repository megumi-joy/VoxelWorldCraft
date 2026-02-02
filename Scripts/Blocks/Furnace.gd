extends Node
class_name Furnace

# Inventory slots: 0=Input, 1=Fuel, 2=Output
var inventory = [null, null, null]
var burn_time: float = 0.0 # Remaining fuel time
var max_burn_time: float = 0.0 # Initial fuel time
var cook_time: float = 0.0 # Progress on current smelt
const COOK_DURATION = 5.0 # Seconds to smelt one item

signal furnace_updated

func interact(player):
	var hud = player.get_node_or_null("HUD")
	if hud and hud.has_node("FurnaceUI"):
		var ui = hud.get_node("FurnaceUI")
		ui.set_furnace(self)
		ui.visible = not ui.visible
		if ui.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta):
	var updated = false
	
	if burn_time > 0:
		burn_time -= delta
		if burn_time <= 0:
			updated = true
			
		# Cooking
		if can_smelt():
			cook_time += delta
			if cook_time >= COOK_DURATION:
				smelt_item()
				cook_time = 0.0
				updated = true
		else:
			cook_time = 0.0
			
	else:
		# Try to consume fuel
		if can_smelt() and has_fuel():
			consume_fuel()
			updated = true
			
	if updated:
		furnace_updated.emit()

func can_smelt() -> bool:
	# Check input and output validity
	var input = inventory[0]
	if not input: return false
	
	# Check recipe (Hardcoded for now)
	var output_id = get_smelting_result(input.id)
	if output_id == 0: return false
	
	# Check output slot
	var output = inventory[2]
	if output:
		if output.id != output_id: return false
		if output.count >= 64: return false
	
	return true

func has_fuel() -> bool:
	var fuel = inventory[1]
	return fuel != null and get_fuel_time(fuel.id) > 0

func consume_fuel():
	var fuel = inventory[1]
	if fuel:
		max_burn_time = get_fuel_time(fuel.id)
		burn_time = max_burn_time
		fuel.count -= 1
		if fuel.count <= 0:
			inventory[1] = null

func smelt_item():
	var input = inventory[0]
	var output_id = get_smelting_result(input.id)
	
	input.count -= 1
	if input.count <= 0:
		inventory[0] = null
		
	var output = inventory[2]
	if not output:
		inventory[2] = {"id": output_id, "count": 1}
	else:
		output.count += 1

func get_smelting_result(input_id: int) -> int:
	# Iron Ore (6) -> Iron Ingot (7 - TODO)
	# For now: Iron Ore (6) -> Iron Block (8 - placeholder)
	# Coal Ore (5) -> Coal Item (5 - wait, ore drops coal. Block smelting?)
	# Let's say: Sand -> Glass.
	# Let's define Iron Item later.
	# For now return input_id (dummy)
	if input_id == 6: return 1 # Turn iron to dirt for test
	return 0

func get_fuel_time(fuel_id: int) -> float:
	if fuel_id == 4: return 10.0 # Wood
	if fuel_id == 5: return 80.0 # Coal
	return 0.0
