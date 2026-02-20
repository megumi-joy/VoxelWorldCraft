extends Node
class_name TextureGenerator

const ATLAS_SIZE = 512
const CELL_SIZE = 128 # 4x4 grid fitting in 512

func _ready():
	var image = Image.create(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8)
	
	# Generate Grass (Top)
	generate_noise_texture(image, 0, 0, Color(0.2, 0.8, 0.2), Color(0.1, 0.6, 0.1))
	# Generate Dirt (Bottom/Side)
	generate_noise_texture(image, 1, 0, Color(0.4, 0.3, 0.2), Color(0.3, 0.2, 0.1))
	# Generate Stone
	generate_noise_texture(image, 2, 0, Color(0.5, 0.5, 0.5), Color(0.4, 0.4, 0.4))
	# Generate Bedrock/Other
	generate_noise_texture(image, 3, 0, Color(0.1, 0.1, 0.1), Color(0.0, 0.0, 0.0))
	
	# Generate Coal Ore (Atlas 1, 0 - wait, atlas mapping in Chunk.gd needs update too)
	# Chunk.gd uses single row? No, 4x4 atlas.
	# Let's put Coal at (0, 1) and Iron at (1, 1).
	
	# Coal Base (Stone) + Black spots
	generate_noise_texture(image, 0, 1, Color(0.5, 0.5, 0.5), Color(0.4, 0.4, 0.4))
	add_spots(image, 0, 1, Color(0.1, 0.1, 0.1))
	
	# Iron Base (Stone) + Orange spots
	generate_noise_texture(image, 1, 1, Color(0.5, 0.5, 0.5), Color(0.4, 0.4, 0.4))
	add_spots(image, 1, 1, Color(0.7, 0.5, 0.3))
	
	# Planks (2, 1) - Wood color with lines
	generate_noise_texture(image, 2, 1, Color(0.6, 0.45, 0.3), Color(0.5, 0.35, 0.2))
	add_lines(image, 2, 1, Color(0.3, 0.2, 0.1))
	
	# Farmland (3, 1) - Dark Dirt
	generate_noise_texture(image, 3, 1, Color(0.2, 0.15, 0.1), Color(0.1, 0.05, 0.0))
	
	# Snow (0, 2) - White
	generate_noise_texture(image, 0, 2, Color(0.95, 0.95, 1.0), Color(0.9, 0.9, 0.95))
	
	# Sand (1, 2) - Yellowish
	generate_noise_texture(image, 1, 2, Color(0.8, 0.7, 0.5), Color(0.75, 0.65, 0.45))
	
	# Seedling (2, 2) - Light Green sprouts
	generate_noise_texture(image, 2, 2, Color(0.1, 0.05, 0.0), Color(0.1, 0.05, 0.0)) # Dark background
	add_spots(image, 2, 2, Color(0.2, 0.9, 0.2)) # Green spots

	var texture = ImageTexture.create_from_image(image)
	# Save to disk mainly for debugging or if we want to use it in material
	# But we can also just assign it effectively. 
	# For this task, let's just make it available globally or save it.
	
	# We'll save it to the user:// or res:// if in editor
	# Since this is runtime, use it in a material.
	
	# But better: Just create a StandardMaterial3D and assign it.
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	
	# Assign to global VoxelWorld logic if needed, or just ResourceSaver if running in editor mode.
	# For simplicity, let's assume we use this script to setup the material for Chunk.gd
	
	# Let's emit or store it in a singleton or VoxelWorld.
	var world = get_parent()
	# Avoid static type check to prevent circular dependency
	if world.has_method("update_chunks"):
		world.chunk_material = mat

func generate_noise_texture(img: Image, cell_x: int, cell_y: int, color_a: Color, color_b: Color):
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.1
	
	for x in range(CELL_SIZE):
		for y in range(CELL_SIZE):
			var val = noise.get_noise_2d(x, y)
			var col = color_a.lerp(color_b, (val + 1.0) / 2.0)
			
			# Add some pixel noise
			if randf() > 0.9:
				col = col.darkened(0.1)
			
			img.set_pixel(cell_x * CELL_SIZE + x, cell_y * CELL_SIZE + y, col)

func add_spots(img: Image, cell_x: int, cell_y: int, spot_color: Color):
	for i in range(20):
		var rx = randi() % CELL_SIZE
		var ry = randi() % CELL_SIZE
		var radius = randi() % 5 + 2
		
		for x in range(rx - radius, rx + radius):
			for y in range(ry - radius, ry + radius):
				if x >= 0 and x < CELL_SIZE and y >= 0 and y < CELL_SIZE:
					img.set_pixel(cell_x * CELL_SIZE + x, cell_y * CELL_SIZE + y, spot_color)

func add_lines(img: Image, cell_x: int, cell_y: int, line_color: Color):
	for y_off in [32, 64, 96]:
		for x in range(CELL_SIZE):
			img.set_pixel(cell_x * CELL_SIZE + x, cell_y * CELL_SIZE + y_off, line_color)
