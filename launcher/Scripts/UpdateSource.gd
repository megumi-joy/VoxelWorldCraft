class_name UpdateSource
extends Node
## Interface for pluggable update sources for the VoxelWorldCraft launcher.
##
## The owner's ask was explicit: "local now, GitHub later" -- ship an MVP
## that pulls builds from a local folder today, but make the later switch
## to GitHub Releases a one-line change, not a rewrite. That's the whole
## reason this interface exists: Launcher.gd only ever talks to an
## `UpdateSource` through these signals/methods, never to
## LocalFolderSource or GithubReleasesSource directly. Swapping which
## concrete class backs `_update_source` (see `Launcher._make_update_source()`)
## is the entire migration.
##
## `Node` (not `RefCounted`) on purpose: GithubReleasesSource needs to own
## an HTTPRequest child to do network I/O, and giving both implementations
## the same base keeps the calling code uniform (`add_child(source)` always
## works, whether or not a given source actually needs the scene tree).
##
## All results are plain Dictionaries with an "ok" bool plus an "error"
## string (Russian, user-facing, empty when ok) so the UI layer never has
## to know which concrete source produced them.

## Emitted after request_latest_version(). Result: {ok, version, error}
signal latest_version_ready(result: Dictionary)

## Emitted after fetch_update() finishes (success or failure).
## Result: {ok, path, error} -- `path` is the install directory that now
## holds the fetched build when ok is true.
signal update_downloaded(result: Dictionary)

## Optional coarse progress, 0.0..1.0. Not all sources can report granular
## progress (LocalFolderSource's copy is effectively instant); emitting it
## is best-effort, not a contract callers must rely on.
signal update_progress(fraction: float)

## Ask the source what the newest available version is. Must eventually
## emit latest_version_ready exactly once per call (async-safe: emit via
## call_deferred or a real signal callback, never synchronously before the
## caller has connected -- see LocalFolderSource for the pattern).
func request_latest_version() -> void:
	push_error("UpdateSource.request_latest_version() not implemented")
	latest_version_ready.emit({"ok": false, "version": "", "error": "Источник обновлений не реализован."})

## Fetch/install `version` into `dest_dir`. Must eventually emit
## update_downloaded exactly once per call.
func fetch_update(version: String, dest_dir: String) -> void:
	push_error("UpdateSource.fetch_update() not implemented")
	update_downloaded.emit({"ok": false, "path": "", "error": "Источник обновлений не реализован."})
