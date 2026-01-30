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

func _init(pos: Vector2i, _noise: FastNoiseLite):
	chunk_position = pos
	noise = _noise
	
func _ready():
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	# Create static body for collision
	var static_body = StaticBody3D.new()
	mesh_instance.add_child(static_body)
	collision_shape = CollisionShape3D.new()
	static_body.add_child(collision_shape)
	
	generate_data()
	generate_mesh()

func generate_data():
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
	# st.set_uv(...)
	
	# Add two triangles (0-1-2) and (0-2-3)
	st.add_vertex(pos + vertices[0])
	st.add_vertex(pos + vertices[1])
	st.add_vertex(pos + vertices[2])
	
	st.add_vertex(pos + vertices[0])
	st.add_vertex(pos + vertices[2])
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
