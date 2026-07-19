class_name BuildInfoLoader
extends RefCounted
# Reads the committed/stamped res://build_info.json -- version + short
# commit hash + last-updated date -- that MainMenu.gd shows in its version
# label and uses as the "local version" for the update-check button.
#
# build_info.json ships committed with a static snapshot (so a fresh clone
# that's never run the stamping step/hook/CI still shows something sane),
# but is meant to be REGENERATED, not hand-edited:
#   - scripts/stamp_build_info.sh -- the generator, run by...
#   - .github/workflows/ci.yml's export-desktop job (AUTHORITATIVE --
#     every real shipped build embeds a fresh stamp), and optionally...
#   - the local pre-commit hook from scripts/install-hooks.sh (dev
#     convenience, keeps the editor-run label from going stale between
#     CI-triggering pushes).
# See RELEASING.md.
#
# Falls back to project.godot's config/version (and "unknown"/"?" for
# commit/date) if the file is missing or fails to parse, so a corrupt or
# absent build_info.json degrades gracefully instead of erroring the menu.

const PATH := "res://build_info.json"

static func load_info() -> Dictionary:
	var fallback := {
		"version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"commit": "unknown",
		"date": "?",
	}
	if not FileAccess.file_exists(PATH):
		return fallback

	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return fallback
	var text := file.get_as_text()

	var json := JSON.new()
	if json.parse(text) != OK:
		return fallback
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return fallback

	return {
		"version": String(data.get("version", fallback["version"])),
		"commit": String(data.get("commit", fallback["commit"])),
		"date": String(data.get("date", fallback["date"])),
	}
