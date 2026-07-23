extends Control

@onready var grid = $Panel/GridContainer
@onready var title_label = $Panel/TitleLabel
var inventory

# Click-to-pick-up / click-to-place: first click on a non-empty slot "picks
# up" that slot (remembered here, slot gets a highlight border); a second
# click on any slot (including the same one, which cancels) calls
# Inventory.move_item(selected, target) and clears the selection. Two clicks
# instead of drag-and-drop because Godot's built-in drag-and-drop needs a
# _get_drag_data/_can_drop_data/_drop_data trio wired per-control -- click
# selection reuses the same Button.pressed signal every other menu here
# (ChestUI, CraftingUI) already relies on.
var _selected_slot: int = -1

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

	if title_label:
		title_label.text = "Инвентарь"

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

const SLOT_SIZE := 56.0

func update_ui():
	if not inventory: return

	# Clear existing
	for child in grid.get_children():
		child.queue_free()

	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)

	if _selected_slot >= inventory.size:
		_selected_slot = -1

	# Rebuild -- Buttons (not bare Panels) so slots are clickable, same
	# convention ChestUI.gd/CraftingUI.gd already use for their slot grids.
	# Slot visual (icon + count badge + hover tooltip) comes from the shared
	# ItemIcon helper (see Scripts/UI/ItemIcon.gd) so all 4 menus render
	# slots identically -- only the picked-up/empty highlight below is
	# specific to this menu's click-to-move interaction.
	var db = get_node_or_null("/root/ItemDatabase")
	for i in range(inventory.size):
		var slot = Button.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.toggle_mode = false

		var slot_style = StyleBoxFlat.new()
		slot_style.corner_radius_top_left = 8
		slot_style.corner_radius_top_right = 8
		slot_style.corner_radius_bottom_right = 8
		slot_style.corner_radius_bottom_left = 8
		slot_style.border_width_left = 1
		slot_style.border_width_top = 1
		slot_style.border_width_right = 1
		slot_style.border_width_bottom = 1
		if i == _selected_slot:
			# Picked-up slot: highlighted so it's obvious a second click will
			# place/merge/swap onto whatever slot is clicked next.
			slot_style.bg_color = Color(1.0, 0.85, 0.2, 0.35)
			slot_style.border_color = Color(1.0, 0.85, 0.2, 0.9)
		else:
			slot_style.bg_color = Color(1, 1, 1, 0.07) # Subtle, but visible enough that an empty slot still reads as a slot
			slot_style.border_color = Color(1, 1, 1, 0.18)
		slot.add_theme_stylebox_override("normal", slot_style)
		slot.add_theme_stylebox_override("hover", slot_style)
		slot.add_theme_stylebox_override("pressed", slot_style)
		slot.add_theme_stylebox_override("focus", slot_style)

		grid.add_child(slot)

		var item = inventory.items[i]
		var item_data = null
		if item and db:
			item_data = db.get_item(item.id)
		ItemIcon.populate_slot(slot, item_data, item.count if item else 0, SLOT_SIZE)

		slot.pressed.connect(_on_slot_pressed.bind(i))

## Click-to-pick-up / click-to-place, see `_selected_slot` doc above.
func _on_slot_pressed(i: int) -> void:
	if not inventory:
		return

	if _selected_slot < 0:
		# Nothing picked up yet: only start a pick-up on a non-empty slot.
		if inventory.items[i]:
			_selected_slot = i
			update_ui()
		return

	if _selected_slot == i:
		# Clicking the already-picked-up slot again cancels the pick-up.
		_selected_slot = -1
		update_ui()
		return

	var from = _selected_slot
	_selected_slot = -1
	inventory.move_item(from, i)
	# move_item() emits inventory_changed (Inventory.gd), which this UI is
	# connected to (see _wire_inventory_deferred), so update_ui() also runs
	# from that signal -- calling it again here is a harmless no-op re-render
	# that keeps the UI in sync even in the (from == i, no-op) case above.
	update_ui()
