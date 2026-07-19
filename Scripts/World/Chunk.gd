extends Node3D
class_name Chunk

# Chunk dimensions
const CHUNK_SIZE = Vector3(16, 256, 16)
# Atlas is 8x8 now
const TEXTURE_ATLAS_SIZE = Vector2(8, 8) 
const UV_SIZE = 1.0 / 8.0

# Data
var chunk_position: Vector2i
var voxel_data = {} 
var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D

var noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var material: StandardMaterial3D
var world_node: Node3D 

func setup(pos: Vector2i, _noise: FastNoiseLite, _material: StandardMaterial3D, _world_node: Node3D = null):
	chunk_position = pos
	noise = _noise
	material = _material
	# world_node used to be captured via get_parent() here, but setup() runs
	# before VoxelWorld.create_chunk() add_child()s this chunk (deliberately --
	# setup() has to run first so _ready() sees valid chunk_position/noise/
	# material when add_child() synchronously fires it), so get_parent() was
	# always null at this point. Every cross-chunk neighbor lookup in
	# has_voxel() therefore silently fell through to "no voxel", so every
	# chunk-border face got rendered as if the neighboring chunk were empty --
	# redundant/z-fighting double geometry at every chunk seam. Accept the
	# owning VoxelWorld explicitly instead of relying on tree-parenting
	# timing; get_parent() stays as a fallback for any other caller that
	# really does set up a chunk after parenting it.
	world_node = _world_node if _world_node else get_parent()

	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = noise.seed + 12345
	moisture_noise.frequency = 0.005 # Large biome patches

func _ready():
	mesh_instance = MeshInstance3D.new()
	mesh_instance.material_override = material
	add_child(mesh_instance)
	
	var static_body = StaticBody3D.new()
	mesh_instance.add_child(static_body)
	collision_shape = CollisionShape3D.new()
	static_body.add_child(collision_shape)
	
	generate_data()
	generate_mesh()

var is_generating: bool = false

func get_biome(temperature: float, moisture: float) -> String:
	if temperature < -0.2:
		return "Tundra"
	elif temperature > 0.4:
		if moisture < -0.1:
			return "Desert"
		else:
			return "Forest"
	else:
		# Moderate temperature band: split by moisture instead of always
		# defaulting to Forest, so open grassland (Plains) exists too.
		if moisture > 0.05:
			return "Forest"
		else:
			return "Plains"

func generate_data():
	is_generating = true
	if not voxel_data.is_empty():
		is_generating = false
		return

	# Terrain Pass
	for x in range(16):
		for z in range(16):
			var global_x = chunk_position.x * 16 + x
			var global_z = chunk_position.y * 16 + z
			
			var visual_height = int((noise.get_noise_2d(global_x, global_z) + 1) * 32) + 64
			var temp = noise.get_noise_2d(global_x * 0.5, global_z * 0.5) 
			var moisture = moisture_noise.get_noise_2d(global_x, global_z)
			var biome = get_biome(temp, moisture)
			
			for y in range(visual_height + 1):
				var pos = Vector3i(x, y, z)
				
				# Bedrock
				if y == 0:
					voxel_data[pos] = 3 # Stone/Bedrock
					continue
				
				var block_id = 1 # Default Dirt
				
				if y == visual_height:
					match biome:
						"Desert": block_id = 42 # Sand
						"Tundra":
							# Wetter cold patches freeze solid (Ice); drier
							# patches stay powder Snow. Reuses the same
							# continuous moisture value, so the Snow/Ice
							# boundary is smooth, not a hard random cut.
							if moisture > 0.2: block_id = 52 # Ice
							else: block_id = 43 # Snow
						"Forest", "Plains": block_id = 2 # Grass
						_: block_id = 2
				elif y > visual_height - 4:
					match biome:
						"Desert": block_id = 42 # Sand
						"Tundra": block_id = 1 # Dirt/permafrost under snow or ice
						_: block_id = 1 # Dirt
				else:
					block_id = 3 # Stone
				
				voxel_data[pos] = block_id
				
			# Water / Lava (Simple flat layer)
			# if visual_height < 60:
			# 	for y in range(visual_height + 1, 60):
			# 		voxel_data[Vector3i(x, y, z)] = 40 # Water

	# Structure & Decorator Pass
	var struct_gen = load("res://Scripts/World/StructureGenerator.gd").new()
	var rng = RandomNumberGenerator.new()
	rng.seed = chunk_position.x * 1000 + chunk_position.y
	
	# Only iterate inner area for structures to avoid boundary issues for now, or careful check
	for x in range(2, 14):
		for z in range(2, 14):
			var global_x = chunk_position.x * 16 + x
			var global_z = chunk_position.y * 16 + z
			var height = int((noise.get_noise_2d(global_x, global_z) + 1) * 32) + 64
			
			# Check if surface is valid (not water)
			if not voxel_data.has(Vector3i(x, height, z)): continue
			
			var temp = noise.get_noise_2d(global_x * 0.5, global_z * 0.5)
			var moisture = moisture_noise.get_noise_2d(global_x, global_z)
			var biome = get_biome(temp, moisture)
			
			var r = rng.randf()
			var surface_pos = Vector3i(x, height + 1, z)
			
			match biome:
				"Forest":
					if r < 0.02: # Tree (dense)
						if r < 0.005:
							struct_gen.generate_birch(self, Vector3i(x, height, z))
						else:
							struct_gen.generate_tree(self, Vector3i(x, height, z))
					elif r < 0.15: # Flora
						if r < 0.05: set_block(surface_pos, 44) # Red Flower
						elif r < 0.10: set_block(surface_pos, 45) # Yellow Flower
						else: set_block(surface_pos, 46) # Tall Grass
					elif r < 0.17: set_block(surface_pos, 55) # Berry Bush (food source; was id 52, reassigned -- see ItemDatabase.gd)
					elif r < 0.185: set_block(surface_pos, 53) # Blue Flower (decorative)
					elif r < 0.20: set_block(surface_pos, 54) # Pink Flower (decorative)
				"Plains":
					# Open grassland: light flora, almost no trees (this is
					# the main visual/feature difference from Forest even
					# though both share the grass+dirt palette).
					if r < 0.001: # Rare lone tree
						struct_gen.generate_tree(self, Vector3i(x, height, z))
					elif r < 0.06: # Sparse flora
						if r < 0.02: set_block(surface_pos, 44) # Red Flower
						elif r < 0.04: set_block(surface_pos, 45) # Yellow Flower
						else: set_block(surface_pos, 46) # Tall Grass
				"Desert":
					if r < 0.01:
						struct_gen.generate_cactus(self, Vector3i(x, height, z))
				"Tundra":
					if r < 0.01:
						struct_gen.generate_pine(self, Vector3i(x, height, z))

	# Ore Generation (Deep) -- depth- and (for a couple of minerals)
	# biome-gated. Rarer ores are checked first so they get first claim on a
	# candidate voxel before common Coal/Copper (checked last) usually wins
	# the roll; see ORE_TABLE below for the plausible-geology reasoning per
	# mineral.
	for x in range(16):
		for z in range(16):
			var global_x = chunk_position.x * 16 + x
			var global_z = chunk_position.y * 16 + z
			var height = int((noise.get_noise_2d(global_x, global_z)+1)*32)+64
			var temp = noise.get_noise_2d(global_x * 0.5, global_z * 0.5)
			var moisture = moisture_noise.get_noise_2d(global_x, global_z)
			var biome = get_biome(temp, moisture)

			for y in range(1, height - 5):
				var ore_id = pick_ore(y, biome, rng)
				if ore_id != 0:
					voxel_data[Vector3i(x, y, z)] = ore_id

	struct_gen.free()
	is_generating = false

# id, y_min/y_max (inclusive world depth), chance (rolled per eligible
# voxel), biomes (empty = spawns under any biome). Ordered rarest-first so a
# rare ore's low-probability roll gets first shot at a voxel before a common
# ore checked later in the list usually claims it.
const ORE_TABLE = [
	# Gold: very deep, very rare -- real gold veins form deep, at the
	# outer limit of what a shallow prototype world can represent.
	{"id": 81, "y_min": 1,  "y_max": 22,  "chance": 0.0006, "biomes": []},
	# Hematite (iron oxide): moderately rare, mid-deep; biome-gated to
	# Desert since its rust-red color is also what tints desert sand/rock.
	{"id": 83, "y_min": 20, "y_max": 55,  "chance": 0.0018, "biomes": ["Desert"]},
	# Quartz: fairly common, mid depth; gated to the two "hard ground"
	# biomes (Desert/Tundra) rather than soft Forest/Plains loam.
	{"id": 82, "y_min": 25, "y_max": 60,  "chance": 0.0025, "biomes": ["Desert", "Tundra"]},
	# Iron: deep, uncommon (kept from the original ore pass).
	{"id": 6,  "y_min": 1,  "y_max": 40,  "chance": 0.0015, "biomes": []},
	# Malachite (copper carbonate): shallow-mid, forms in oxidized zones
	# near the surface -- gated to Forest/Plains topsoil biomes.
	{"id": 84, "y_min": 40, "y_max": 75,  "chance": 0.002,  "biomes": ["Forest", "Plains"]},
	# Copper: shallow-mid, common, any biome.
	{"id": 80, "y_min": 35, "y_max": 70,  "chance": 0.0035, "biomes": []},
	# Coal: common, any depth/biome (kept from the original ore pass).
	{"id": 5,  "y_min": 1,  "y_max": 200, "chance": 0.004,  "biomes": []},
]

func pick_ore(y: int, biome: String, rng: RandomNumberGenerator) -> int:
	for ore in ORE_TABLE:
		if y < ore.y_min or y > ore.y_max:
			continue
		if ore.biomes.size() > 0 and not ore.biomes.has(biome):
			continue
		if rng.randf() < ore.chance:
			return ore.id
	return 0

func generate_mesh():
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for x in range(16):
		for y in range(256):
			for z in range(16):
				var pos = Vector3i(x, y, z)
				if voxel_data.has(pos):
					create_block_faces(surface_tool, pos)
	
	surface_tool.index()
	var mesh = surface_tool.commit()
	mesh_instance.mesh = mesh
	
	if mesh.get_surface_count() > 0:
		collision_shape.shape = mesh.create_trimesh_shape()

func has_voxel(pos: Vector3i) -> bool:
	# Local
	if pos.x >= 0 and pos.x < 16 and pos.y >= 0 and pos.y < 256 and pos.z >= 0 and pos.z < 16:
		return voxel_data.has(pos)
	
	# Global/Neighbor
	if not world_node: return false
	
	var global_x = chunk_position.x * 16 + pos.x
	var global_z = chunk_position.y * 16 + pos.z
	
	if pos.y < 0 or pos.y >= 256: return false
	
	var cx = int(floor(float(global_x) / 16.0))
	var cz = int(floor(float(global_z) / 16.0))
	var cpos = Vector2i(cx, cz)
	
	if world_node.chunks.has(cpos):
		var chunk = world_node.chunks[cpos]
		if chunk == null: return false # Loading/Placeholder
		var lx = global_x - cx * 16
		var lz = global_z - cz * 16
		return chunk.voxel_data.has(Vector3i(lx, pos.y, lz))
		
	return false

func create_block_faces(st: SurfaceTool, pos: Vector3i):
	# Cull faces
	if not has_voxel(pos + Vector3i.UP): create_face(st, pos, Vector3.UP)
	if not has_voxel(pos + Vector3i.DOWN): create_face(st, pos, Vector3.DOWN)
	if not has_voxel(pos + Vector3i.LEFT): create_face(st, pos, Vector3.LEFT)
	if not has_voxel(pos + Vector3i.RIGHT): create_face(st, pos, Vector3.RIGHT)
	if not has_voxel(pos + Vector3i.FORWARD): create_face(st, pos, Vector3.FORWARD)
	if not has_voxel(pos + Vector3i.BACK): create_face(st, pos, Vector3.BACK)

func create_face(st: SurfaceTool, pos: Vector3i, normal: Vector3):
	var vertices = []
	var pos_f = Vector3(pos.x, pos.y, pos.z)
	
	# CCW Winding
	if normal == Vector3.UP:
		vertices = [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)]
	elif normal == Vector3.DOWN:
		vertices = [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)]
	elif normal == Vector3.LEFT:
		vertices = [Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1)]
	elif normal == Vector3.RIGHT:
		vertices = [Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]
	elif normal == Vector3.FORWARD:
		vertices = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]
	elif normal == Vector3.BACK:
		vertices = [Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)]

	st.set_normal(normal)
	
	var type = voxel_data[pos]
	var atlas_idx = 0
	var atlas_row = 0
	
	# Mapping based on TextureGenerator.gd (8x8)
	# Row 0: Grass, Dirt, Stone, Bedrock, Wood
	if type == 2: # Grass
		if normal == Vector3.UP: atlas_idx = 0; atlas_row = 0
		elif normal == Vector3.DOWN: atlas_idx = 1; atlas_row = 0
		else: atlas_idx = 1; atlas_row = 0 # Simple dirt side for now? Or implement Grass Side
	elif type == 1: atlas_idx = 1; atlas_row = 0 # Dirt
	elif type == 3: atlas_idx = 2; atlas_row = 0 # Stone
	elif type == 4: # Oak Wood
		if normal.y != 0: atlas_idx = 4; atlas_row = 2 # Top/Bottom (Use leaves/logs logic?) Wait, Log top?
		else: atlas_idx = 4; atlas_row = 0
		
	# Row 1: Ores, Planks, Farm
	elif type == 5: atlas_idx = 0; atlas_row = 1 # Coal
	elif type == 6: atlas_idx = 1; atlas_row = 1 # Iron
	elif type == 13: atlas_idx = 2; atlas_row = 1 # Planks
	elif type == 14: atlas_idx = 3; atlas_row = 1 # Farmland
	
	# Row 2: Biomes
	elif type == 42: atlas_idx = 1; atlas_row = 2 # Sand
	elif type == 43: atlas_idx = 0; atlas_row = 2 # Snow
	elif type == 50: atlas_idx = 2; atlas_row = 2 # Leaves (Oak)
	elif type == 52: atlas_idx = 3; atlas_row = 2 # Ice (Tundra)
	
	# Row 3: Fluids, Wood Types
	elif type == 40: atlas_idx = 0; atlas_row = 3 # Water
	elif type == 41: atlas_idx = 1; atlas_row = 3 # Lava
	elif type == 48: atlas_idx = 2; atlas_row = 3 # Birch
	elif type == 49: atlas_idx = 3; atlas_row = 3 # Pine
	elif type == 51: atlas_idx = 2; atlas_row = 2 # Pine Leaves (Reuse Oak for now or specific?)
	
	# Row 4: Plants
	elif type == 44: atlas_idx = 0; atlas_row = 4 # Red Flower
	elif type == 45: atlas_idx = 1; atlas_row = 4 # Yellow Flower
	elif type == 46: atlas_idx = 2; atlas_row = 4 # Tall Grass
	elif type == 47: atlas_idx = 3; atlas_row = 4 # Cactus
	elif type == 55: atlas_idx = 4; atlas_row = 4 # Berry Bush (food source; was id 52, reassigned -- see ItemDatabase.gd)
	elif type == 53: atlas_idx = 5; atlas_row = 4 # Blue Flower
	elif type == 54: atlas_idx = 6; atlas_row = 4 # Pink Flower

	# Row 5 (cont.): Wave 2 mineral ores (see TextureGenerator.gd / ItemDatabase.gd)
	elif type == 80: atlas_idx = 2; atlas_row = 5 # Copper Ore
	elif type == 81: atlas_idx = 3; atlas_row = 5 # Gold Ore
	elif type == 82: atlas_idx = 4; atlas_row = 5 # Quartz
	elif type == 83: atlas_idx = 5; atlas_row = 5 # Hematite
	elif type == 84: atlas_idx = 6; atlas_row = 5 # Malachite Ore

	var u_start = atlas_idx * UV_SIZE
	var v_start = atlas_row * UV_SIZE
	
	var face_uvs = [
		Vector2(u_start, v_start + UV_SIZE),
		Vector2(u_start, v_start),
		Vector2(u_start + UV_SIZE, v_start),
		Vector2(u_start + UV_SIZE, v_start + UV_SIZE)
	]
	
	st.set_uv(face_uvs[0]); st.add_vertex(pos_f + vertices[0])
	st.set_uv(face_uvs[1]); st.add_vertex(pos_f + vertices[1])
	st.set_uv(face_uvs[2]); st.add_vertex(pos_f + vertices[2])
	
	st.set_uv(face_uvs[0]); st.add_vertex(pos_f + vertices[0])
	st.set_uv(face_uvs[2]); st.add_vertex(pos_f + vertices[2])
	st.set_uv(face_uvs[3]); st.add_vertex(pos_f + vertices[3])

func set_block(local_pos: Vector3i, type: int):
	if type == 0:
		if voxel_data.has(local_pos):
			voxel_data.erase(local_pos)
			if not is_generating: generate_mesh()
	else:
		voxel_data[local_pos] = type
		if not is_generating: generate_mesh()
