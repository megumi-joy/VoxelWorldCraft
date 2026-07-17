extends Node3D
# Root script for Scenes/Import/MCImportView.tscn -- a standalone render
# harness for the Minecraft importer prototype. Not part of normal
# gameplay: loads converted_blocks.json (produced by
# tools/mc_import/parse_and_map.py, OUTSIDE this repo -- see RAILS, no
# downloaded world data or large binaries get committed) and builds real
# Chunk nodes from it via Chunk.setup_import(), bypassing procedural
# generation entirely, then frames a camera on the imported area so
# tools/record_movie_maker.sh can capture a screenshot/clip headlessly.
#
# JSON path comes from a cmdline arg (passed after `--` per Godot's
# OS.get_cmdline_args() convention, same as AutoTester.gd's --run-tests
# flag and record_movie_maker.sh's EXTRA_ARGS):
#   godot --path . ... Scenes/Import/MCImportView.tscn -- --import-json=/output/converted_blocks.json
# Falls back to IMPORT_JSON_ENV ("MC_IMPORT_JSON") env var, then a default
# path, so it also runs conveniently from the Godot editor.

const ChunkScript = preload("res://Scripts/World/Chunk.gd")
const DEFAULT_JSON_PATH = "/import/converted_blocks.json"

var chunk_material: StandardMaterial3D
var chunks := {}

@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label3D = $StatusLabel3D

func _ready():
	var tex_gen = Node.new()
	tex_gen.set_script(load("res://Scripts/World/TextureGenerator.gd"))
	add_child(tex_gen) # TextureGenerator._ready() runs synchronously here and
	                    # sets chunk_material on `get_parent()` (this node).

	var json_path = _resolve_json_path()
	print("MCImportView: loading %s" % json_path)

	var result = MinecraftImporter.load_file(json_path)
	if not result.get("ok", false):
		push_error("MCImportView: import FAILED: %s" % result.get("error", "unknown error"))
		_set_status("IMPORT FAILED: %s" % result.get("error", "?"))
		# Non-zero exit so a headless CI/verification run visibly fails
		# instead of silently rendering an empty scene.
		get_tree().quit(1)
		return

	print("MCImportView: %d chunks, %d blocks, y_range=%s, source=%s" % [
		result["chunk_count"], result["block_count"], result["y_range"], result["source"]
	])

	var min_cx = 999999; var max_cx = -999999
	var min_cz = 999999; var max_cz = -999999

	for chunk_pos in result["chunks"].keys():
		var chunk = Node3D.new()
		chunk.set_script(ChunkScript)
		chunk.setup_import(chunk_pos, chunk_material, self, result["chunks"][chunk_pos])
		add_child(chunk)
		chunk.global_position = Vector3(chunk_pos.x * 16.0, 0, chunk_pos.y * 16.0)
		chunks[chunk_pos] = chunk

		min_cx = min(min_cx, chunk_pos.x); max_cx = max(max_cx, chunk_pos.x)
		min_cz = min(min_cz, chunk_pos.y); max_cz = max(max_cz, chunk_pos.y)

	if result["chunk_count"] == 0:
		push_error("MCImportView: 0 chunks imported")
		_set_status("IMPORT FAILED: 0 chunks")
		get_tree().quit(1)
		return

	# Frame the camera on the imported area's actual bounds.
	var world_x0 = min_cx * 16.0
	var world_x1 = (max_cx + 1) * 16.0
	var world_z0 = min_cz * 16.0
	var world_z1 = (max_cz + 1) * 16.0
	var y_lo = 0.0
	var y_hi = 127.0
	if result["y_range"].size() == 2 and result["y_range"][0] != null:
		y_lo = float(result["y_range"][0])
		y_hi = float(result["y_range"][1])

	var center = Vector3((world_x0 + world_x1) * 0.5, (y_lo + y_hi) * 0.5, (world_z0 + world_z1) * 0.5)
	var span = max(world_x1 - world_x0, world_z1 - world_z0)
	# Steep-ish aerial angle: a windowed import only has real neighbor data
	# INSIDE the sampled chunk range, so the outward-facing boundary of the
	# imported box renders as a solid wall (there's nothing beyond it to cull
	# against) -- more top-down keeps that "cut edge" artifact out of frame
	# and shows the actual terrain surface instead.
	camera.position = center + Vector3(span * 0.55, span * 1.7, span * 0.55)
	var look_target = Vector3(center.x, y_hi - (y_hi - y_lo) * 0.15, center.z)
	camera.look_at(look_target, Vector3.UP)

	# Per-block mapped/placeholder split isn't in this JSON -- that lives in
	# import_stats.json from the Python step (tools/mc_import/parse_and_map.py);
	# this view only needs to prove the render works.
	_set_status("MC import: %d chunks / %d blocks" % [result["chunk_count"], result["block_count"]])
	print("MCImportView: camera framed at %s looking at %s" % [camera.position, look_target])
	print("MCImportView: READY (0 errors)")

func _resolve_json_path() -> String:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--import-json="):
			return arg.substr("--import-json=".length())
	var env_path = OS.get_environment("MC_IMPORT_JSON")
	if env_path != "":
		return env_path
	return DEFAULT_JSON_PATH

func _set_status(text: String):
	if status_label:
		status_label.text = text
