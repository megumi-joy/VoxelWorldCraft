extends Control

var simulator: Node
var cell_size = 40.0
var offset = Vector2(400, 300)

func _ready():
	# Find simulator
	var world = get_node_or_null("/root/World/VoxelWorld")
	if world and world.get("simulator"):
		simulator = world.simulator
	
	set_process(true)

func _process(_delta):
	queue_redraw() # Continuous redraw for real-time visualization

func _draw():
	if not simulator: return
	
	# Draw background grid
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.1, 0.1, 0.15, 0.8))
	
	var nodes = simulator.nodes
	var drawn_lines = {}
	
	for pos in nodes.keys():
		var n = nodes[pos]
		# Only draw X/Z plane (ignore Y height for schematic flattening)
		# Or maybe map X to screen X, Y to screen Y, and ignore Z?
		# Let's map X->X, Y->Y for vertical schematics.
		var screen_pos = offset + Vector2(pos.x, -pos.y) * cell_size
		
		# Draw connections to neighbors
		var neighbors = [
			pos + Vector3i.RIGHT, pos + Vector3i.LEFT,
			pos + Vector3i.UP, pos + Vector3i.DOWN
		]
		for np in neighbors:
			if nodes.has(np):
				var n_pos = offset + Vector2(np.x, -np.y) * cell_size
				var line_hash = str(min(pos.x, np.x)) + "_" + str(max(pos.x, np.x)) + "_" + str(min(pos.y, np.y)) + "_" + str(max(pos.y, np.y))
				if not drawn_lines.has(line_hash):
					draw_line(screen_pos, n_pos, Color(0.4, 0.4, 0.4, 1.0), 2.0)
					drawn_lines[line_hash] = true
		
		# Draw Symbol based on type
		match n.type:
			"n-type":
				draw_circle(screen_pos, 10, Color.BLUE)
				draw_string(ThemeDB.fallback_font, screen_pos + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)
			"p-type":
				draw_circle(screen_pos, 10, Color.RED)
				draw_string(ThemeDB.fallback_font, screen_pos + Vector2(-5, 5), "P", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)
			"inductor":
				# Draw a coil (zig-zag or loops)
				for i in range(3):
					draw_arc(screen_pos + Vector2((i-1)*8, 0), 6, PI, 0, 10, Color.ORANGE, 2.0)
			"source-pos":
				draw_line(screen_pos + Vector2(-10, -5), screen_pos + Vector2(10, -5), Color.GREEN, 3.0)
				draw_string(ThemeDB.fallback_font, screen_pos + Vector2(-15, 0), "+", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.GREEN)
			"source-neg":
				draw_line(screen_pos + Vector2(-5, 5), screen_pos + Vector2(5, 5), Color.BLACK, 3.0)
				draw_string(ThemeDB.fallback_font, screen_pos + Vector2(-15, 10), "-", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.BLACK)
			"wire":
				draw_circle(screen_pos, 4, Color.GRAY)
				
		# Draw current / electrons density
		if n.e > 0:
			draw_circle(screen_pos + Vector2(12, 12), log(n.e + 1) * 2, Color(0, 1, 1, 0.5))
		if abs(n.momentum) > 0.5:
			draw_line(screen_pos, screen_pos + Vector2(0, -n.momentum * 5), Color.YELLOW, 2.0)
