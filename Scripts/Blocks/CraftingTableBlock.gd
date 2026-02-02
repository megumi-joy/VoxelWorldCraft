extends Node3D

func interact(player):
	# Open Crafting UI
	# Assuming Player has a HUD where we can show this.
	# Or the player spawns a UI window.
	# Let's check if player has "CraftingUI" inside HUD.
	var hud = player.get_node_or_null("HUD")
	if hud and hud.has_node("CraftingUI"):
		var ui = hud.get_node("CraftingUI")
		ui.visible = not ui.visible
		if ui.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		print("Player has no Crafting UI")
