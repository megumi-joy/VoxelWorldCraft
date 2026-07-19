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
	# Raw Iron (62, dropped by mining Iron Ore -- see Player.gd's
	# _process_mining and ItemDatabase.gd) -> Iron Ingot (63).
	if input_id == 62: return 63
	# Gold Ore (81) -> Gold Ingot (64); Copper Ore (80) -> Copper Ingot
	# (65). These smelt the existing ore item directly rather than a
	# separate "Raw Gold"/"Raw Copper" drop -- see ItemDatabase.gd's ID
	# 64-65 comment for why (preserves existing collectible/Field Journal
	# discovery behavior on items 80/81).
	if input_id == 81: return 64
	if input_id == 80: return 65
	return 0

func get_fuel_time(fuel_id: int) -> float:
	if fuel_id == 4: return 10.0 # Wood
	if fuel_id == 5: return 80.0 # Coal
	return 0.0
