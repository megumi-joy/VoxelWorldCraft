extends Node3D
class_name Chunk

# Chunk dimensions
const CHUNK_SIZE = Vector3(16, 256, 16)
const TEXTURE_ATLAS_SIZE = Vector2(4, 4) # 4x4 atlas for now

# Data
var chunk_position: Vector2i
var voxel_data = {} # Dictionary for sparse storage, or use Array/PackedByteArray for dense
var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D

var noise: FastNoiseLite
var material: StandardMaterial3D

func _init(pos: Vector2i, _noise: FastNoiseLite, _material: StandardMaterial3D):
	chunk_position = pos
	noise = _noise
	material = _material
	
func _ready():
	mesh_instance = MeshInstance3D.new()
	mesh_instance.material_override = material
	add_child(mesh_instance)
	
	# Create static body for collision
	var static_body = StaticBody3D.new()
	mesh_instance.add_child(static_body)
	collision_shape = CollisionShape3D.new()
	static_body.add_child(collision_shape)
	
	generate_data()
	generate_mesh()

func generate_data():
	# If data is already loaded (e.g. from SaveSystem), skip generation
	if not voxel_data.is_empty():
		return

	# Simple terrain generation
	for x in range(CHUNK_SIZE.x):
		for z in range(CHUNK_SIZE.z):
			var global_x = chunk_position.x * CHUNK_SIZE.x + x
			var global_z = chunk_position.y * CHUNK_SIZE.z + z # chunk_position is 2D, so y is z index
			
			var height = int((noise.get_noise_2d(global_x, global_z) + 1) * 32) + 64 # Base height ~64, variation +/- 32
			
			for y in range(height):
				var block_type = 1 # Dirt
				if y == height - 1:
					block_type = 2 # Grass
				elif y < 60:
					block_type = 3 # Stone
				
				voxel_data[Vector3i(x, y, z)] = block_type
				
	# Generate Structures
	var struct_gen = StructureGenerator.new()
	struct_gen.generate_structures(self, noise)
	# Free generator mainly because it's stateless usage
	struct_gen.free()

func generate_mesh():
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Simple iteration for now (optimize later)
	for x in range(CHUNK_SIZE.x):
		for y in range(CHUNK_SIZE.y):
			for z in range(CHUNK_SIZE.z):
				var pos = Vector3i(x, y, z)
				if voxel_data.has(pos):
					create_block_faces(surface_tool, pos)
	
	surface_tool.index()
	var mesh = surface_tool.commit()
	mesh_instance.mesh = mesh
	
	# Create collision
	if mesh.get_surface_count() > 0:
		collision_shape.shape = mesh.create_trimesh_shape()

func create_block_faces(st: SurfaceTool, pos: Vector3i):
	# Check neighbors to cull faces
	# Top
	if not voxel_data.has(pos + Vector3i.UP):
		create_face(st, pos, Vector3.UP)
	# Bottom
	if not voxel_data.has(pos + Vector3i.DOWN):
		create_face(st, pos, Vector3.DOWN)
	# Left
	if not voxel_data.has(pos + Vector3i.LEFT):
		create_face(st, pos, Vector3.LEFT)
	# Right
	if not voxel_data.has(pos + Vector3i.RIGHT):
		create_face(st, pos, Vector3.RIGHT)
	# Forward
	if not voxel_data.has(pos + Vector3i.FORWARD):
		create_face(st, pos, Vector3.FORWARD)
	# Back
	if not voxel_data.has(pos + Vector3i.BACK):
		create_face(st, pos, Vector3.BACK)

func create_face(st: SurfaceTool, pos: Vector3i, normal: Vector3):
	var vertices = []
	var uv_offset = Vector2(0, 0) # Placeholder for atlas logic
	
	# Defined with Counter-Clockwise winding for Godot
	if normal == Vector3.UP:
		vertices = [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]
	elif normal == Vector3.DOWN:
		vertices = [Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]
	elif normal == Vector3.LEFT:
		vertices = [Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1)]
	elif normal == Vector3.RIGHT:
		vertices = [Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0)]
	elif normal == Vector3.FORWARD: # -Z
		vertices = [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 0)]
	elif normal == Vector3.BACK: # +Z
		vertices = [Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(1, 0, 1)]

	st.set_normal(normal)
	
	# Determine block type for UVs
	# We need the type at 'pos'. 
	var type = 1 # Default
	if voxel_data.has(pos):
		type = voxel_data[pos]
	
	# Mapping: 1=Grass(0,0), 2=Dirt(1,0), 3=Stone(2,0)
	# Actually TextureGenerator makes: 0=Grass, 1=Dirt, 2=Stone
	# My block types were: 1=Dirt, 2=Grass, 3=Stone.
	# Let's map: 
	# Block 1 (Dirt) -> Atlas 1
	# Block 2 (Grass) -> Atlas 0
	# Block 3 (Stone) -> Atlas 2
	
	var atlas_idx = 0
	var atlas_row = 0
	
	if type == 1: atlas_idx = 1 # Dirt
	elif type == 2: atlas_idx = 0 # Grass
	elif type == 3: atlas_idx = 2 # Stone
	elif type == 4: atlas_idx = 3 # Wood (assume Bedrock/Wood slot)
	elif type == 5:
		atlas_idx = 0
		atlas_row = 1 # Coal
	elif type == 6:
		atlas_idx = 1
		atlas_row = 1 # Iron
	
	var uv_size = 1.0 / 4.0 # 4x4 atlas
	var u_start = atlas_idx * uv_size
	var v_start = atlas_row * uv_size
	
	# UVs for the face (Simple box mapping section)
	# Vertices are: [0, 1, 2, 3] corresponding to quad corners
	# (0,1) -> (0,0) -> (1,0) -> (1,1) (roughly, dependent on vertex order)
	
	# Order used: v0 (TL/BL?), v1, v2, v3
	# Let's assign standard UVs
	var face_uvs = [
		Vector2(u_start, v_start + uv_size), # 0, 1 (Bottom Left)
		Vector2(u_start, v_start), # 0, 0 (Top Left)
		Vector2(u_start + uv_size, v_start), # 1, 0 (Top Right)
		Vector2(u_start + uv_size, v_start + uv_size) # 1, 1 (Bottom Right)
	]
	
	# But we need to match the vertex list order in `vertices`
	# vertices array order in previous code:
	# UP: [0,1,0], [0,1,1] ... 
	# This mapping depends on exactly how 'vertices' list matches a quad
	# Let's just create a generic unwrapped UV set for a face
	
	st.set_uv(face_uvs[0])
	st.add_vertex(pos + vertices[0])
	st.set_uv(face_uvs[1])
	st.add_vertex(pos + vertices[1])
	st.set_uv(face_uvs[2])
	st.add_vertex(pos + vertices[2])
	
	st.set_uv(face_uvs[0])
	st.add_vertex(pos + vertices[0])
	st.set_uv(face_uvs[2])
	st.add_vertex(pos + vertices[2])
	st.set_uv(face_uvs[3])
	st.add_vertex(pos + vertices[3])

func set_block(local_pos: Vector3i, type: int):
	# If type is 0 (Air), remove from dictionary
	if type == 0:
		if voxel_data.has(local_pos):
			voxel_data.erase(local_pos)
			generate_mesh()
	else:
		voxel_data[local_pos] = type
		generate_mesh()
