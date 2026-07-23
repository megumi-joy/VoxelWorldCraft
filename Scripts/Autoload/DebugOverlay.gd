extends CanvasLayer
## Minecraft-style F3 debug overlay (owner ask mid=772: "дев нужен и типа на
## кнопку f3 как координаты и прочее"). Toggle with F3. Shows player position,
## block/chunk coords, facing compass, FPS, on-floor, held item and the block
## currently looked at. Off by default; self-contained autoload so it works in
## every world without wiring into any scene.
##
## Auto-shown (no keypress) when launched with --debug-overlay or --showcase-demo
## so recordings/verification can capture it.

const CHUNK_SIZE := 16

var _label: Label
var _panel: ColorRect
var _shown := false

func _ready() -> void:
	layer = 128 # draw above the HUD
	_panel = ColorRect.new()
	_panel.color = Color(0, 0, 0, 0.45)
	_panel.position = Vector2(10, 140)
	_panel.size = Vector2(360, 220)
	add_child(_panel)

	_label = Label.new()
	_label.position = Vector2(20, 148)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.95))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

	if not InputMap.has_action("debug_overlay"):
		InputMap.add_action("debug_overlay")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F3
		InputMap.action_add_event("debug_overlay", ev)

	# Auto-show for recordings/verification.
	var args := OS.get_cmdline_user_args()
	_shown = args.has("--debug-overlay") or args.has("--showcase-demo")
	visible = _shown
	set_process(true)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F3:
		_shown = not _shown
		visible = _shown
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not visible:
		return
	var p := get_tree().get_first_node_in_group("player")
	var lines := PackedStringArray()
	lines.append("VoxelWorldCraft -- ОТЛАДКА (F3)")
	lines.append("FPS: %d" % Engine.get_frames_per_second())
	if p == null:
		lines.append("игрок: (не заспавнен)")
		_label.text = "\n".join(lines)
		return

	var pos: Vector3 = p.global_position
	lines.append("XYZ: %.2f / %.2f / %.2f" % [pos.x, pos.y, pos.z])
	lines.append("Блок: %d %d %d" % [floori(pos.x), floori(pos.y), floori(pos.z)])
	lines.append("Чанк: %d, %d" % [floori(pos.x / CHUNK_SIZE), floori(pos.z / CHUNK_SIZE)])
	lines.append("Направление: %s" % _facing(p))
	if p.has_method("is_on_floor"):
		lines.append("на земле: %s   скор.y: %.1f" % [str(p.is_on_floor()), p.velocity.y if ("velocity" in p) else 0.0])
	if "selected_block_id" in p:
		var item = ItemDatabase.get_item(p.selected_block_id) if get_node_or_null("/root/ItemDatabase") else null
		lines.append("В руке: %s (id %d)" % [item.name if item else "-", p.selected_block_id])
	lines.append("Смотрит на: %s" % _looking_at(p))
	_label.text = "\n".join(lines)

## Compass from the camera's world-space forward vector (Minecraft convention:
## -Z = North, +Z = South, +X = East, -X = West).
func _facing(p) -> String:
	var cam = p.camera if ("camera" in p) else null
	if cam == null:
		return "?"
	var f: Vector3 = -cam.global_transform.basis.z
	if abs(f.z) >= abs(f.x):
		return "Север (-Z)" if f.z < 0.0 else "Юг (+Z)"
	return "Восток (+X)" if f.x > 0.0 else "Запад (-X)"

## The block cell the player's aim raycast currently hits, if any.
func _looking_at(p) -> String:
	var rc = p.raycast if ("raycast" in p) else null
	if rc == null or not rc.is_colliding():
		return "-"
	var point: Vector3 = rc.get_collision_point()
	var normal: Vector3 = rc.get_collision_normal()
	var cell := point - normal * 0.5
	return "%d %d %d" % [floori(cell.x), floori(cell.y), floori(cell.z)]
