extends Control

@onready var chat_box = $ChatBox
@onready var rich_text_label = $ChatBox/RichTextLabel
@onready var line_edit = $ChatBox/LineEdit

func _ready():
	line_edit.text_submitted.connect(_on_text_submitted)

func _input(event):
	if event.is_action_pressed("ui_accept"): # Enter key
		if line_edit.visible:
			_on_text_submitted(line_edit.text)
		else:
			open_chat()
	elif event.is_action_pressed("ui_cancel"):
		close_chat()

func open_chat():
	line_edit.visible = true
	line_edit.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_chat():
	line_edit.visible = false
	line_edit.clear()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_text_submitted(text: String):
	if text.strip_edges() == "":
		close_chat()
		return
		
	# command check
	if text.begins_with("/"):
		process_command(text)
	else:
		add_message("Player: " + text)
		
	close_chat()

func add_message(text: String):
	rich_text_label.append_text(text + "\n")

func process_command(text: String):
	var parts = text.split(" ")
	var cmd = parts[0]
	
	if cmd == "/give":
		# /give ID Amount
		if parts.size() >= 3:
			var id = int(parts[1])
			var amount = int(parts[2])
			var player = get_tree().get_first_node_in_group("player")
			if player:
				var inv = player.get_node_or_null("Inventory")
				if inv:
					inv.add_item(id, amount)
					add_message("Gave " + str(amount) + " of item " + str(id))
	elif cmd == "/time":
		# /time value
		if parts.size() >= 2:
			var time = float(parts[1])
			# Set time logic if available via NetworkManager or VoxelWorld
			add_message("Time set to " + str(time))
	else:
		add_message("Unknown command: " + cmd)
