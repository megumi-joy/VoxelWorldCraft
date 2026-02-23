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

func setup(pos: Vector2i, _noise: FastNoiseLite, _material: StandardMaterial3D):
	chunk_position = pos
	noise = _noise
	material = _material
	world_node = get_parent()
	
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
		return "Forest"

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
						"Tundra": block_id = 43 # Snow
						"Forest": block_id = 2 # Grass
						_: block_id = 2
				elif y > visual_height - 4:
					match biome:
						"Desert": block_id = 42 # Sand
						"Tundra": block_id = 1 # Dirt under snow
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
					if r < 0.02: # Tree
						if r < 0.005:
							struct_gen.generate_birch(self, Vector3i(x, height, z))
						else:
							struct_gen.generate_tree(self, Vector3i(x, height, z))
					elif r < 0.15: # Flora
						if r < 0.05: set_block(surface_pos, 44) # Red Flower
						elif r < 0.10: set_block(surface_pos, 45) # Yellow Flower
						else: set_block(surface_pos, 46) # Tall Grass
				"Desert":
					if r < 0.01:
						struct_gen.generate_cactus(self, Vector3i(x, height, z))
				"Tundra":
					if r < 0.01:
						struct_gen.generate_pine(self, Vector3i(x, height, z))

	# Ore Generation (Deep)
	for x in range(16):
		for z in range(16):
			var height = int((noise.get_noise_2d(chunk_position.x*16+x, chunk_position.y*16+z)+1)*32)+64
			for y in range(1, height - 5):
				if rng.randf() < 0.005: 
					if y < 40 and rng.randf() < 0.2:
						voxel_data[Vector3i(x, y, z)] = 6 # Iron
					else:
						voxel_data[Vector3i(x, y, z)] = 5 # Coal

	struct_gen.free()
	is_generating = false

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
