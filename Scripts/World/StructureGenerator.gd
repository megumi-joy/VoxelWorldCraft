extends Node
class_name StructureGenerator

# Simple structure definitions
# List of (offset, block_type)
const TREE_STRUCTURE = [
	# Trunk
	[Vector3i(0, 0, 0), 4], # Wood
	[Vector3i(0, 1, 0), 4],
	[Vector3i(0, 2, 0), 4],
	# Leaves -- id 57 (Oak Leaves). Was id 5, which is Coal (ItemDatabase.gd /
	# Chunk.gd atlas), so oak trees rendered their canopy with the coal-ore
	# texture -- the owner's "листва/бревно не как надо" (mid=738). 57 is a
	# free id mapped to the real green oak-leaves atlas cell (2,2) in Chunk.gd.
	# NOT 56 -- that id is Torch on current main. Coal (id 5) is left untouched
	# so ore generation is unaffected.
	[Vector3i(0, 3, 0), 57], # Oak Leaves
	[Vector3i(1, 2, 0), 57],
	[Vector3i(-1, 2, 0), 57],
	[Vector3i(0, 2, 1), 57],
	[Vector3i(0, 2, -1), 57],
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

# Village Hut -- 3x3 footprint, flush with the terrain surface (same
# convention as the tree structures above: the offset-(_,0,_) layer sits AT
# the surface height passed in by the caller, replacing the natural grass/
# sand/snow block there, exactly like TREE_STRUCTURE's trunk base does).
# Planks(13)/Oak Wood(4) -- both pre-existing ids, no new atlas cell needed.
# South wall (z=-1) deliberately has NO center wall block at dy=1/2: that is
# the door gap (owner spec: "a few wood+planks blocks with a door-gap"), a
# 1-wide 2-tall opening a player can walk straight through.
const VILLAGE_HUT = [
	# Floor (Planks) 3x3
	[Vector3i(-1, 0, -1), 13], [Vector3i(0, 0, -1), 13], [Vector3i(1, 0, -1), 13],
	[Vector3i(-1, 0, 0), 13],  [Vector3i(0, 0, 0), 13],  [Vector3i(1, 0, 0), 13],
	[Vector3i(-1, 0, 1), 13],  [Vector3i(0, 0, 1), 13],  [Vector3i(1, 0, 1), 13],
	# Corner posts (Oak Wood), 2 blocks tall
	[Vector3i(-1, 1, -1), 4], [Vector3i(-1, 2, -1), 4],
	[Vector3i(1, 1, -1), 4],  [Vector3i(1, 2, -1), 4],
	[Vector3i(-1, 1, 1), 4],  [Vector3i(-1, 2, 1), 4],
	[Vector3i(1, 1, 1), 4],  [Vector3i(1, 2, 1), 4],
	# Walls (Planks) -- north (z=1) and east/west centers filled in; south
	# (z=-1) center is the door gap, see above.
	[Vector3i(0, 1, 1), 13],  [Vector3i(0, 2, 1), 13],  # north wall center
	[Vector3i(-1, 1, 0), 13], [Vector3i(-1, 2, 0), 13], # west wall center
	[Vector3i(1, 1, 0), 13],  [Vector3i(1, 2, 0), 13],  # east wall center
	# Roof (Planks), flat cap
	[Vector3i(-1, 3, -1), 13], [Vector3i(0, 3, -1), 13], [Vector3i(1, 3, -1), 13],
	[Vector3i(-1, 3, 0), 13],  [Vector3i(0, 3, 0), 13],  [Vector3i(1, 3, 0), 13],
	[Vector3i(-1, 3, 1), 13],  [Vector3i(0, 3, 1), 13],  [Vector3i(1, 3, 1), 13],
]

# Village Well -- 3x3 stone(3) ring, 2 courses tall, flush with the terrain
# surface, with a Water(40) pool set into the center. A second, visually
# distinct structure type (so "structures" in the world isn't just one
# repeated stamp) that reuses only pre-existing ids.
const VILLAGE_WELL = [
	[Vector3i(-1, 0, -1), 3], [Vector3i(0, 0, -1), 3], [Vector3i(1, 0, -1), 3],
	[Vector3i(-1, 0, 0), 3],                            [Vector3i(1, 0, 0), 3],
	[Vector3i(-1, 0, 1), 3],  [Vector3i(0, 0, 1), 3],  [Vector3i(1, 0, 1), 3],
	[Vector3i(-1, 1, -1), 3], [Vector3i(0, 1, -1), 3], [Vector3i(1, 1, -1), 3],
	[Vector3i(-1, 1, 0), 3],                            [Vector3i(1, 1, 0), 3],
	[Vector3i(-1, 1, 1), 3],  [Vector3i(0, 1, 1), 3],  [Vector3i(1, 1, 1), 3],
	[Vector3i(0, 0, 0), 40], [Vector3i(0, 1, 0), 40],
]

# Count of village structures actually stamped into the world this run --
# static so it survives across the many per-chunk StructureGenerator
# instances (Chunk.generate_data() does `load(...).new()` per chunk). Read by
# Scripts/Testing/WorldContentDemoDriver.gd to verify generation actually
# happened rather than assuming it from source alone. Starts at 0 each fresh
# process (headless run or real game launch); never persisted/saved.
static var placed_count: int = 0

func generate_tree(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, TREE_STRUCTURE)

func generate_birch(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, BIRCH_TREE)

func generate_pine(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, PINE_TREE)

func generate_cactus(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, CACTUS_STRUCTURE)

func generate_hut(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, VILLAGE_HUT)
	placed_count += 1

func generate_well(chunk, local_pos: Vector3i):
	place_structure(chunk, local_pos, VILLAGE_WELL)
	placed_count += 1

func place_structure(chunk, local_pos: Vector3i, structure: Array):
	for block in structure:
		var pos = local_pos + block[0]
		if is_in_chunk(pos): chunk.set_block(pos, block[1])

func is_in_chunk(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < 16 and \
		   pos.z >= 0 and pos.z < 16 and \
		   pos.y >= 0 and pos.y < 256
