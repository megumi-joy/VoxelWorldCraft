extends Node
class_name StructureGenerator

# Simple structure definitions
# List of (offset, block_type)
const TREE_STRUCTURE = [
	# Trunk
	[Vector3i(0, 0, 0), 4], # Wood
	[Vector3i(0, 1, 0), 4],
	[Vector3i(0, 2, 0), 4],
	# Leaves
	[Vector3i(0, 3, 0), 5], # Leaves
	[Vector3i(1, 2, 0), 5],
	[Vector3i(-1, 2, 0), 5],
	[Vector3i(0, 2, 1), 5],
	[Vector3i(0, 2, -1), 5],
]

const BIRCH_TREE = [
	[Vector3i(0, 0, 0), 48], [Vector3i(0, 1, 0), 48], [Vector3i(0, 2, 0), 48], # Trunk
	[Vector3i(0, 3, 0), 50], [Vector3i(1, 3, 0), 50], [Vector3i(-1, 3, 0), 50], [Vector3i(0, 3, 1), 50], [Vector3i(0, 3, -1), 50], # Leaves
	[Vector3i(0, 4, 0), 50] # Top
]

const PINE_TREE = [
	[Vector3i(0, 0, 0), 49], [Vector3i(0, 1, 0), 49], [Vector3i(0, 2, 0), 49], [Vector3i(0, 3, 0), 49], # Trunk
	[Vector3i(0, 2, 1), 51], [Vector3i(0, 2, -1), 51], [Vector3i(1, 2, 0), 51], [Vector3i(-1, 2, 0), 51], # Base Leaves
	[Vector3i(0, 4, 0), 51], [Vector3i(0, 5, 0), 51] # Top
]

const CACTUS_STRUCTURE = [
	[Vector3i(0, 0, 0), 47], [Vector3i(0, 1, 0), 47], [Vector3i(0, 2, 0), 47]
]

const HOUSE_STRUCTURE = [
	# Floor (Woods) 3x3
	[Vector3i(-1, 0, -1), 4], [Vector3i(0, 0, -1), 4], [Vector3i(1, 0, -1), 4],
	[Vector3i(-1, 0, 0), 4], [Vector3i(0, 0, 0), 4], [Vector3i(1, 0, 0), 4],
	[Vector3i(-1, 0, 1), 4], [Vector3i(0, 0, 1), 4], [Vector3i(1, 0, 1), 4],
	# Walls (Stone/Planks)
	[Vector3i(-1, 1, -1), 4], [Vector3i(1, 1, -1), 4], [Vector3i(-1, 1, 1), 4], [Vector3i(1, 1, 1), 4],
	[Vector3i(-1, 2, -1), 4], [Vector3i(1, 2, -1), 4], [Vector3i(-1, 2, 1), 4], [Vector3i(1, 2, 1), 4],
	# Roof (Stone)
	[Vector3i(0, 3, 0), 3], [Vector3i(-1, 3, 0), 3], [Vector3i(1, 3, 0), 3], [Vector3i(0, 3, 1), 3], [Vector3i(0, 3, -1), 3]
]

func generate_tree(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, TREE_STRUCTURE)

func generate_birch(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, BIRCH_TREE)

func generate_pine(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, PINE_TREE)

func generate_cactus(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, CACTUS_STRUCTURE)

func generate_house(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, HOUSE_STRUCTURE)

func place_structure(chunk, local_pos: Vector3i, structure: Array):
	for block in structure:
		var pos = local_pos + block[0]
		if is_in_chunk(pos): chunk.set_block(pos, block[1])

func is_in_chunk(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < 16 and \
		   pos.z >= 0 and pos.z < 16 and \
		   pos.y >= 0 and pos.y < 256
    # Hardcoded size to avoid Chunk.CHUNK_SIZE dependency if needed, 
    # but constants usually work. Let's try removing just function type hints first.
    # Actually, accessing Chunk.CHUNK_SIZE also causes dependency.
    # Let's see if we can access it dynamically or just hardcode/pass size.
    # Safe bet: Removing type hints `chunk: Chunk` usually fixes "Could not resolve class".
    # Accessing static constants might still be issues if the script fails to parse.
    # Let's replace Chunk.CHUNK_SIZE with the passed chunk reference values if possible, or just hardcode 16/256 for now 
    # OR assume Chunk is loaded.
    
    # Let's stick to simple type removal first.

func generate_structures(chunk, noise: FastNoiseLite):
	# Random trees and houses
	var rng = RandomNumberGenerator.new()
	rng.seed = chunk.chunk_position.x + chunk.chunk_position.y * 1000
	
	for x in range(4, 16 - 4): # Padding for structures
		for z in range(4, 16 - 4):
			# Get surface height
			var global_x = chunk.chunk_position.x * 16 + x
			var global_z = chunk.chunk_position.y * 16 + z
			var height = int((noise.get_noise_2d(global_x, global_z) + 1) * 32) + 64
			
			if height < 60: continue
			
			var r = rng.randf()
			if r < 0.01: # 1% Tree
				generate_tree(chunk, Vector3i(x, height, z))
			elif r < 0.012: # 0.2% House (Very rare per block, but decent per chunk)
				generate_house(chunk, Vector3i(x, height, z))

	# Generate Ores
	# Iterate volume below surface
	for x in range(16):
		for z in range(16):
			var global_x = chunk.chunk_position.x * 16 + x
			var global_z = chunk.chunk_position.y * 16 + z
			var height = int((noise.get_noise_2d(global_x, global_z) + 1) * 32) + 64
			
			for y in range(height - 1): # Only replace natural blocks
				var r_ore = rng.randf()
				# Coal: Common, found up to near surface
				if r_ore < 0.005 and y < 60:
					chunk.set_block(Vector3i(x, y, z), 5)
				# Iron: Rarer, deeper
				elif r_ore < 0.002 and y < 50:
					chunk.set_block(Vector3i(x, y, z), 6)
