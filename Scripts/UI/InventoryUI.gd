extends Control

@onready var grid = $Panel/GridContainer
var inventory

func _ready():
	# Style the main panel for Glassmorphism
	var panel = $Panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.7) # Darker glass
	style.corner_radius_top_left = 15
	style.corner_radius_top_right = 15
	style.corner_radius_bottom_right = 15
	style.corner_radius_bottom_left = 15
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.15) # Subtle border
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", style)
	
	# Find player inventory. ROOT CAUSE of "инвентарь не видно только панель"
	# (owner mid=733): this UI's _ready() fires before the player's "Inventory"
	# child exists -- Player.setup() creates that node at runtime, and on 182
	# the HUD/panel loads first, so the one-shot lookup here found nothing,
	# inventory stayed null, and update_ui() bailed out leaving an empty panel.
	# Confirmed by telemetry (inventory_ui_ready found_inventory:false in the
	# podman verify runs). Fix: retry across frames until the player and its
	# Inventory node both exist, then wire up once.
	if get_node_or_null("/root/Telemetry"):
		Telemetry.log_event("inventory_ui_ready", {"found_inventory": inventory != null})
	print("[InventoryUI] ready -- inventory=", inventory != null, " visible=", visible)
	_wire_inventory_deferred()

	# Ensure Input Map exists
	if not InputMap.has_action("inventory"):
		InputMap.add_action("inventory")
		var ev = InputEventKey.new()
		ev.physical_keycode = KEY_E
		InputMap.action_add_event("inventory", ev)

	set_process_input(true)

## Retry wiring the UI to the player's live Inventory across frames, because
## the player (and its "Inventory" child) may not exist yet when _ready()
## fires -- see the note in _ready(). Gives up quietly after ~2s so a stripped
## test scene without a player never spins forever. Idempotent: returns as soon
## as it has connected once.
func _wire_inventory_deferred() -> void:
	if inventory:
		return
	for _attempt in range(120): # ~2s at 60fps
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_node("Inventory"):
			inventory = player.get_node("Inventory")
			inventory.inventory_changed.connect(update_ui)
			update_ui()
			if get_node_or_null("/root/Telemetry"):
				Telemetry.log_event("inventory_ui_wired", {"attempt": _attempt})
			print("[InventoryUI] inventory wired after ", _attempt, " frame(s)")
			return
		await get_tree().process_frame

func _input(event):
	if event.is_action_pressed("inventory"):
		visible = not visible
		# Diagnostic (see _ready): confirms the E press actually reached this
		# handler and flipped visibility -- so a 182 log shows whether the bug
		# is "toggle never fires" vs. "toggles but renders nothing".
		if get_node_or_null("/root/Telemetry"):
			Telemetry.log_event("inventory_ui_toggled", {"visible": visible})
		print("[InventoryUI] toggled -- visible=", visible)
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
		slot_style.bg_color = Color(1, 1, 1, 0.05) # Very subtle
		slot_style.corner_radius_top_left = 8
		slot_style.corner_radius_top_right = 8
		slot_style.corner_radius_bottom_right = 8
		slot_style.corner_radius_bottom_left = 8
		slot_style.border_width_left = 1
		slot_style.border_width_top = 1
		slot_style.border_width_right = 1
		slot_style.border_width_bottom = 1
		slot_style.border_color = Color(1, 1, 1, 0.1)
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
