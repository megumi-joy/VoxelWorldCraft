extends Node3D
class_name TorchBlock

# Placeable light source. Follows the Furnace/Bed block-entity pattern
# (spawned by VoxelWorld.set_voxel, removed automatically when something
# else is placed/mined at the same cell -- see set_voxel's block_entities
# cleanup at the top of the function).
#
# Unlike Furnace/Bed/CraftingTable, the torch is NOT also written into the
# chunk's voxel_data (VoxelWorld.set_voxel special-cases ITEM_ID to skip
# chunk.set_block). A torch is thin and shouldn't be a full solid cube --
# doing so would (a) double-render as a textured cube around this mesh and
# (b) block neighboring face culling incorrectly. All of its presence in
# the world is this entity: the mesh below + the light. No interact() --
# it's purely decorative/functional, nothing to click on it for.

const ITEM_ID = 56 # Matches ItemDatabase.gd's Torch entry (id == block_id).
