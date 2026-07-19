class_name LocalFolderSource
extends UpdateSource
## MVP update source: reads builds from a local folder instead of the
## network. Expected layout of `source_dir`:
##
##   builds/
##     0.2.0/           <- a full copy of the game's exported build
##       VoxelWorldCraft.exe (or .x86_64 on Linux)
##       VoxelWorldCraft.pck
##       ...
##     0.3.0/
##       ...
##
## Each subfolder's *name* is treated as its version string and compared
## with VersionUtil; the highest one wins. Installing/updating copies that
## whole subfolder's contents into the install directory.
##
## This is intentionally the simplest thing that works -- no manifests, no
## checksums, no delta-patching (explicitly out of scope for this MVP).
## Swapping to GithubReleasesSource later replaces this class wholesale;
## Launcher.gd doesn't need to change beyond the one line that constructs
## the source.

var source_dir: String = ""

func _init(p_source_dir: String = "") -> void:
	source_dir = p_source_dir

func request_latest_version() -> void:
	# Local filesystem scans are effectively synchronous, but we still
	# defer the emit so callers can always connect signals right after
	# constructing the source and get a real (deferred) callback, the same
	# way a network-backed source would behave. That keeps LocalFolderSource
	# and GithubReleasesSource interchangeable from the caller's point of
	# view -- no "oh, this one happens to answer instantly" special case.
	call_deferred("_do_request_latest_version")

func _do_request_latest_version() -> void:
	if source_dir.is_empty() or not DirAccess.dir_exists_absolute(source_dir):
		latest_version_ready.emit({
			"ok": false, "version": "",
			"error": "Папка со сборками не найдена: %s" % source_dir,
		})
		return

	var versions := _list_build_versions()
	if versions.is_empty():
		latest_version_ready.emit({
			"ok": false, "version": "",
			"error": "В папке со сборками нет ни одной версии игры: %s" % source_dir,
		})
		return

	latest_version_ready.emit({"ok": true, "version": versions[-1], "error": ""})

func fetch_update(version: String, dest_dir: String) -> void:
	call_deferred("_do_fetch_update", version, dest_dir)

func _do_fetch_update(version: String, dest_dir: String) -> void:
	if source_dir.is_empty() or not DirAccess.dir_exists_absolute(source_dir):
		update_downloaded.emit({
			"ok": false, "path": "",
			"error": "Папка со сборками не найдена: %s" % source_dir,
		})
		return

	var src := source_dir.path_join(version)
	if not DirAccess.dir_exists_absolute(src):
		update_downloaded.emit({
			"ok": false, "path": "",
			"error": "Сборка версии %s не найдена в %s" % [version, source_dir],
		})
		return

	update_progress.emit(0.0)
	var err := _copy_dir_recursive(src, dest_dir)
	if err != OK:
		update_downloaded.emit({
			"ok": false, "path": "",
			"error": "Ошибка копирования файлов игры (код %d)." % err,
		})
		return

	update_progress.emit(1.0)
	update_downloaded.emit({"ok": true, "path": dest_dir, "error": ""})

## Subfolder names of source_dir, sorted oldest -> newest by VersionUtil.
func _list_build_versions() -> Array:
	var out: Array = []
	var dir := DirAccess.open(source_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			out.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return VersionUtil.compare(a, b) < 0)
	return out

## Recursively copies every file/dir under `src` into `dest`, creating
## `dest` (and subdirectories) as needed. Returns the first error hit, or
## OK if the whole tree copied cleanly.
func _copy_dir_recursive(src: String, dest: String) -> int:
	if not DirAccess.dir_exists_absolute(dest):
		var mk_err := DirAccess.make_dir_recursive_absolute(dest)
		if mk_err != OK:
			return mk_err

	var dir := DirAccess.open(src)
	if dir == null:
		return ERR_CANT_OPEN

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var src_path := src.path_join(entry)
			var dest_path := dest.path_join(entry)
			var err: int
			if dir.current_is_dir():
				err = _copy_dir_recursive(src_path, dest_path)
			else:
				err = DirAccess.copy_absolute(src_path, dest_path)
				# DirAccess.copy_absolute does NOT preserve the source
				# file's permission bits on Linux (verified: a chmod +x
				# game binary comes out of the copy as plain 0644) --
				# without this, the copied VoxelWorldCraft.x86_64 would
				# silently fail to launch via OS.create_process after
				# every update. Re-apply the source's unix permissions on
				# every copied file; harmless no-op on Windows.
				if err == OK:
					FileAccess.set_unix_permissions(dest_path, FileAccess.get_unix_permissions(src_path))
			if err != OK:
				dir.list_dir_end()
				return err
		entry = dir.get_next()
	dir.list_dir_end()
	return OK
