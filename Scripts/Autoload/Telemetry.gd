extends Node
# Lightweight, append-only gameplay telemetry -- JSON Lines under
# user://telemetry/, one file per session (timestamped filename so repeat
# runs/exports never clobber each other and nothing needs read-modify-
# write). Each line is one flat JSON object:
#   {"t": <unix_time>, "playtime_sec": <float>, "event": <string>, ...}
#
# Scope kept to exactly what was asked: session start, blocks broken/
# placed, deaths (+cause), and playtime -- not a general-purpose analytics
# bus. Hooked from Player.gd (block break/place, death) plus this file's
# own _ready()/_notification() (session start/end).
#
# Follows the same defensive user://-write pattern SaveSystem.gd already
# uses successfully in this project (ensure_dir() + `if file:` guard before
# every use) -- that pattern is already exercised by every headless
# --run-tests/--movement-demo/etc. run via World.tscn's chunk saving, so
# writing under user:// is known-safe in the podman/CI environment too.

const DIR := "user://telemetry"

var _file: FileAccess
var _session_start_msec: int

func _ready() -> void:
	_session_start_msec = Time.get_ticks_msec()
	_ensure_dir()

	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-").replace(" ", "_")
	var path := "%s/session_%s.jsonl" % [DIR, stamp]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if not _file:
		push_warning("Telemetry: could not open " + path + " -- telemetry disabled for this session")
		return

	log_event("session_start", {
		"version": str(ProjectSettings.get_setting("application/config/version", "?")),
	})

static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)

func get_playtime_sec() -> float:
	return float(Time.get_ticks_msec() - _session_start_msec) / 1000.0

## Appends one JSON-line event. `fields` is merged in on top of the
## standard t/playtime_sec/event keys -- e.g.
## Telemetry.log_event("death", {"cause": "mob"}).
func log_event(event_type: String, fields: Dictionary = {}) -> void:
	if not _file:
		return
	var entry := {
		"t": Time.get_unix_time_from_system(),
		"playtime_sec": get_playtime_sec(),
		"event": event_type,
	}
	for k in fields:
		entry[k] = fields[k]
	_file.store_line(JSON.stringify(entry))
	_file.flush()

func _notification(what: int) -> void:
	# NOTIFICATION_WM_CLOSE_REQUEST reaches every node's _notification(), not
	# just the root viewport -- this only logs a final "session_end" line
	# (with total playtime) before the engine's own default
	# auto_accept_quit handling proceeds; it does not call get_tree().quit()
	# itself, so normal window-close behavior is untouched.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		log_event("session_end", {})
		if _file:
			_file.close()
			_file = null
