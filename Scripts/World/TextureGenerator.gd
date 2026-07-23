extends Node
class_name TextureGenerator

var noise = FastNoiseLite.new()

# Atlas Settings: 8x8 Grid
# 512x512 total size, 64px cells
const ATLAS_WIDTH = 8
const ATLAS_HEIGHT = 8
const CELL_SIZE = 64
const ATLAS_SIZE_PX = Vector2i(ATLAS_WIDTH * CELL_SIZE, ATLAS_HEIGHT * CELL_SIZE)

func _ready():
	noise.seed = randi()
	noise.frequency = 0.1
	
	var image = Image.create(ATLAS_SIZE_PX.x, ATLAS_SIZE_PX.y, false, Image.FORMAT_RGBA8)
	
	# --- Row 0: Basic Blocks ---
	generate_texture(image, 0, 0, Color(0.2, 0.8, 0.2), 0.1) # ID 1: Grass Top (Approx)
	generate_texture(image, 1, 0, Color(0.4, 0.3, 0.2), 0.2) # ID 1: Dirt (Side/Bottom)
	generate_texture(image, 2, 0, Color(0.5, 0.5, 0.5), 0.3) # ID 3: Stone
	generate_texture(image, 3, 0, Color(0.2, 0.2, 0.2), 0.5) # Bedrock?
	generate_texture(image, 4, 0, Color(0.4, 0.25, 0.1), 0.1) # ID 4: Oak Wood
	add_lines(image, 4, 0, Color(0.3, 0.2, 0.05))
	# Storage Chest (ID 73) -- a plank-like crate face with a darker
	# horizontal banding so it reads as a chest instead of plain wood.
	generate_texture(image, 5, 0, Color(0.5, 0.32, 0.14), 0.1)
	add_lines(image, 5, 0, Color(0.25, 0.15, 0.05))

	# --- Row 1: Ores & Resources ---
	# Coal (ID 5)
	generate_texture(image, 0, 1, Color(0.5, 0.5, 0.5), 0.1)
	add_spots(image, 0, 1, Color(0.1, 0.1, 0.1), 12)
	# Iron (ID 6)
	generate_texture(image, 1, 1, Color(0.5, 0.5, 0.5), 0.1)
	add_spots(image, 1, 1, Color(0.8, 0.6, 0.4), 10)
	# Planks (ID 13)
	generate_texture(image, 2, 1, Color(0.6, 0.4, 0.2), 0.05)
	add_lines(image, 2, 1, Color(0.5, 0.3, 0.1))
	# Farmland (ID 14)
	generate_texture(image, 3, 1, Color(0.3, 0.2, 0.1), 0.2)
	# Wheat Stage 0-3 (Reuse logic or placeholders)
	# ...

	# Clay (ID 96, new shallow ORE_TABLE entry -- see Chunk.gd): muted
	# grey-brown wet sediment.
	generate_texture(image, 4, 1, Color(0.55, 0.5, 0.45), 0.1)
	# Glass (ID 97, smelted from Sand): pale, low-noise so it reads as
	# smooth/reflective rather than a rough natural block.
	generate_texture(image, 5, 1, Color(0.75, 0.9, 0.95), 0.05)
	# Brick (ID 98, smelted from Clay): red-brown fired clay + mortar lines.
	generate_texture(image, 6, 1, Color(0.55, 0.25, 0.2), 0.1)
	add_lines(image, 6, 1, Color(0.75, 0.75, 0.7))
	
	# --- Row 2: Nature (Biomes) ---
	# Snow (ID 43)
	generate_texture(image, 0, 2, Color(0.95, 0.95, 1.0), 0.05)
	# Sand (ID 42)
	generate_texture(image, 1, 2, Color(0.9, 0.85, 0.6), 0.1)
	# Oak Leaves (ID 5? No, ID 5 is Coal in DB... wait ItemDB says 5 is Coal. StructureGen says 5 is Leaves in old code.)
	# We need to align with ItemDatabase. Let's assume ItemDB IDs:
	# 40=Water, 41=Lava, 42=Sand, 43=Snow, 44=FlowerRed, 45=FlowerYel, 46=Grass, 47=Cactus, 48=Birch, 49=Pine, 50=BirchLeaves, 51=PineLeaves
	# Leaves (Generic Oak)
	generate_texture(image, 2, 2, Color(0.1, 0.4, 0.1), 0.4)
	# Ice (ID 52) - frozen patches inside the Tundra biome
	generate_texture(image, 3, 2, Color(0.65, 0.85, 0.95), 0.15)
	add_lines(image, 3, 2, Color(0.8, 0.93, 1.0), false) # Vertical crack highlights
	
	# --- Row 3: Fluids & More Wood ---
	# Water (ID 40)
	generate_texture(image, 0, 3, Color(0.2, 0.4, 0.9, 0.8), 0.1)
	# Lava (ID 41)
	generate_texture(image, 1, 3, Color(1.0, 0.3, 0.0), 0.2)
	# Birch Log (ID 48)
	generate_texture(image, 2, 3, Color(0.9, 0.9, 0.8), 0.1)
	add_spots(image, 2, 3, Color(0.2, 0.2, 0.2), 6) # Black spots
	# Pine Log (ID 49)
	generate_texture(image, 3, 3, Color(0.3, 0.2, 0.1), 0.2)
	
	# --- Row 4: Plants ---
	# Red Flower (ID 44)
	generate_texture(image, 0, 4, Color(0,0,0,0), 0)
	add_flower(image, 0, 4, Color(0.9, 0, 0))
	# Yellow Flower (ID 45)
	generate_texture(image, 1, 4, Color(0,0,0,0), 0)
	add_flower(image, 1, 4, Color(1, 1, 0))
	# Tall Grass (ID 46)
	generate_texture(image, 2, 4, Color(0,0,0,0), 0)
	add_grass_stalks(image, 2, 4, Color(0.2, 0.7, 0.2))
	# Cactus (ID 47)
	generate_texture(image, 3, 4, Color(0.2, 0.6, 0.2), 0.1)
	add_lines(image, 3, 4, Color(0.1, 0.5, 0.1), false) # Veritcal stripes

	# Berry Bush (ID 55) - opaque leafy bush with red berries (food source)
	generate_texture(image, 4, 4, Color(0.15, 0.45, 0.15), 0.15)
	add_spots(image, 4, 4, Color(0.8, 0.05, 0.1), 14)
	# Blue Flower (ID 53)
	generate_texture(image, 5, 4, Color(0,0,0,0), 0)
	add_flower(image, 5, 4, Color(0.2, 0.4, 0.95))
	# Pink Flower (ID 54)
	generate_texture(image, 6, 4, Color(0,0,0,0), 0)
	add_flower(image, 6, 4, Color(0.95, 0.4, 0.75))

	# --- Row 5: Elements/Minerals (Generic bases for now) ---
	# We have 100+ elements.
	# We can't fit them all unique. We'll use a generic "Mineral" texture and tint it in shader?
	# Or just generate a few common ones here.
	# Gold (Let's put at 5,0) -- pre-existing placeholder, left as-is and
	# unreferenced by any block (see idx 3 below for the real Gold Ore block).
	generate_texture(image, 0, 5, Color(0.5, 0.5, 0.5), 0.1)
	add_spots(image, 0, 5, Color(1.0, 0.8, 0.0), 10)
	# Diamond/Crystal -- pre-existing placeholder, also unreferenced.
	generate_texture(image, 1, 5, Color(0.5, 0.5, 0.5), 0.1)
	add_spots(image, 1, 5, Color(0.2, 0.9, 1.0), 8)

	# --- Row 5 (cont.): Wave 2 mineral ore blocks (IDs 80-84, see
	# ItemDatabase.gd / Chunk.gd's ORE_TABLE / CodexDatabase.gd) ---
	# Copper Ore (ID 80): grey host rock + warm orange-copper flecks and a
	# few oxidized teal (verdigris) spots.
	generate_texture(image, 2, 5, Color(0.5, 0.5, 0.5), 0.1)
	add_spots(image, 2, 5, Color(0.85, 0.45, 0.15), 10)
	add_spots(image, 2, 5, Color(0.25, 0.65, 0.55), 6)
	# Gold Ore (ID 81): dark host rock + dense bright-gold flecks.
	generate_texture(image, 3, 5, Color(0.45, 0.45, 0.48), 0.1)
	add_spots(image, 3, 5, Color(1.0, 0.84, 0.0), 14)
	# Quartz (ID 82): near-white crystalline base + faceted vertical streaks
	# and a few bright sparkle points.
	generate_texture(image, 4, 5, Color(0.88, 0.88, 0.92), 0.12)
	add_lines(image, 4, 5, Color(0.7, 0.7, 0.78), false)
	add_spots(image, 4, 5, Color(1.0, 1.0, 1.0), 6)
	# Hematite (ID 83): dark red-brown iron-oxide base + metallic black-grey
	# luster flecks.
	generate_texture(image, 5, 5, Color(0.35, 0.12, 0.1), 0.15)
	add_spots(image, 5, 5, Color(0.15, 0.12, 0.12), 10)
	# Malachite Ore (ID 84): grey host rock + vivid green banded spots
	# (copper carbonate's characteristic banding).
	generate_texture(image, 6, 5, Color(0.5, 0.5, 0.5), 0.1)
	add_lines(image, 6, 5, Color(0.03, 0.35, 0.15))
	add_spots(image, 6, 5, Color(0.05, 0.55, 0.25), 14)
	# Amethyst Ore (ID 85): violet crystal base + brighter lilac facet
	# spots -- grey host rock would undersell "gem", so this one skips the
	# usual neutral base and goes straight to purple.
	generate_texture(image, 7, 5, Color(0.5, 0.32, 0.68), 0.15)
	add_spots(image, 7, 5, Color(0.78, 0.55, 0.95), 12)

	# Save and Apply
	var texture = ImageTexture.create_from_image(image)
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = texture
	# NEAREST without mipmaps: mipmaps on a texture ATLAS blend neighbouring
	# atlas cells at distance, showing as thin see-through seams/gaps between
	# blocks ("просвет блоков", owner mid=777). Plain NEAREST samples one texel
	# with no cross-cell interpolation -- standard for blocky/voxel games.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.vertex_color_use_as_albedo = true # Allow tinting too?

	# Block-edge dithering: a subtle stippled darkening near each face's UV
	# edge (see Shaders/BlockEdgeDither.gdshader for the actual pattern).
	# Layered on as a `next_pass` rather than folded into `mat` itself, so
	# the StandardMaterial3D setup above stays exactly as it was and the
	# whole effect is removable by deleting just this one assignment.
	var dither_shader = load("res://Shaders/BlockEdgeDither.gdshader")
	if dither_shader:
		var dither_mat = ShaderMaterial.new()
		dither_mat.shader = dither_shader
		mat.next_pass = dither_mat

	var world = get_parent()
	if world:
		world.chunk_material = mat
		print("Texture Atlas Generated (8x8)")

func generate_texture(image: Image, x_idx: int, y_idx: int, base_color: Color, noise_intensity: float):
	var start_x = x_idx * CELL_SIZE
	var start_y = y_idx * CELL_SIZE
	
	for x in range(CELL_SIZE):
		for y in range(CELL_SIZE):
			var n = noise.get_noise_2d(start_x + x, start_y + y)
			var color = base_color.lightened(n * noise_intensity)
			image.set_pixel(start_x + x, start_y + y, color)

func add_spots(image: Image, x_idx: int, y_idx: int, color: Color, count: int):
	var start_x = x_idx * CELL_SIZE
	var start_y = y_idx * CELL_SIZE
	
	for i in range(count):
		var rx = randi() % (CELL_SIZE - 4) + 2
		var ry = randi() % (CELL_SIZE - 4) + 2
		image.set_pixel(start_x + rx, start_y + ry, color)
		image.set_pixel(start_x + rx + 1, start_y + ry, color)
		image.set_pixel(start_x + rx, start_y + ry + 1, color)
		image.set_pixel(start_x + rx + 1, start_y + ry + 1, color)

func add_lines(image: Image, x_idx: int, y_idx: int, color: Color, horizontal: bool = true):
	var start_x = x_idx * CELL_SIZE
	var start_y = y_idx * CELL_SIZE
	
	if horizontal:
		for y in range(0, CELL_SIZE, 8):
			for x in range(CELL_SIZE):
				image.set_pixel(start_x + x, start_y + y, color)
	else:
		for x in range(0, CELL_SIZE, 8):
			for y in range(CELL_SIZE):
				image.set_pixel(start_x + x, start_y + y, color)

func add_flower(image: Image, x_idx: int, y_idx: int, color: Color):
	var start_x = x_idx * CELL_SIZE
	var start_y = y_idx * CELL_SIZE
	var cx = start_x + CELL_SIZE / 2
	var cy = start_y + CELL_SIZE / 2
	
	# Stem
	for y in range(cy, start_y + CELL_SIZE):
		image.set_pixel(cx, y, Color(0, 0.4, 0))
		image.set_pixel(cx+1, y, Color(0, 0.4, 0))
		
	# Petals
	for i in range(-5, 6):
		for j in range(-5, 6):
			if i*i + j*j < 16:
				image.set_pixel(cx + i, cy - 6 + j, color)
				
func add_grass_stalks(image: Image, x_idx: int, y_idx: int, color: Color):
	var start_x = x_idx * CELL_SIZE
	var start_y = y_idx * CELL_SIZE
	
	# Draw a few stalks
	for i in range(5):
		var x = start_x + 10 + i * 10 + (randi() % 5)
		var height = 20 + (randi() % 20)
		for h in range(height):
			image.set_pixel(x, start_y + CELL_SIZE - 1 - h, color)
			image.set_pixel(x+1, start_y + CELL_SIZE - 1 - h, color)
