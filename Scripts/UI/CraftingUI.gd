extends Control

@onready var container = $Panel/RecipeList
var crafting_manager
var inventory

func _ready():
	var cm_script = load("res://Scripts/Crafting/CraftingManager.gd")
	crafting_manager = cm_script.new()
	add_child(crafting_manager)
	
	# Find player inv
	var player = get_tree().get_first_node_in_group("player")
	if player:
		inventory = player.get_node("Inventory")
		if inventory:
			inventory.inventory_changed.connect(update_ui)
			
	update_ui()

func update_ui():
	# Clear list
	for child in container.get_children():
		child.queue_free()
		
	# List recipes
	for i in range(crafting_manager.recipes.size()):
		var recipe = crafting_manager.recipes[i]
		
		var can_make = inventory and crafting_manager.can_craft(i, inventory)
		
		# Button per recipe
		var btn = Button.new()
		# Simple text: Output Name xCount
		var output_id = recipe.output.id
		var db = get_node("/root/ItemDatabase")
		var name = "Unknown"
		if db:
			var data = db.get_item(output_id)
			if data: name = data.name
			
		btn.text = name + " x" + str(recipe.output.count)
		if not can_make:
			btn.disabled = true
			btn.text += " (Missing Materials)"
			
		btn.pressed.connect(func(): on_craft(i))
		container.add_child(btn)

func on_craft(index: int):
	if inventory:
		crafting_manager.craft(index, inventory)
		update_ui() # Refresh
