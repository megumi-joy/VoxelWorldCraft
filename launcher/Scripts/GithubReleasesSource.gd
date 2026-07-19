class_name GithubReleasesSource
extends UpdateSource
## STUB, per the owner's "local now, GitHub later" plan -- NOT wired up as
## the active source (see Launcher._make_update_source(), which still
## constructs LocalFolderSource). This exists so the eventual switch is a
## one-line change in that one function, not new plumbing.
##
## request_latest_version() is implemented for real: it hits GitHub's
## "latest release" API and parses the tag name into a version string.
## That part only needs network access and is safe to exercise any time.
##
## fetch_update() is intentionally left UNIMPLEMENTED. Downloading is easy
## (HTTPRequest to the matched asset's browser_download_url), but there is
## no released asset format yet to design against -- this repo has zero
## GitHub Releases published as of this writing, and the game project
## doesn't have an "upload the desktop export as a release asset" step
## yet either (its CI just uploads workflow artifacts, not releases; see
## ../.github/workflows/ci.yml). Whatever asset format that step lands on
## (zip vs tar, single-arch vs matrix, folder layout inside the archive)
## determines the extraction logic here, so writing it now would be
## guessing. Wiring it up is future work, not a "make it robust" TODO.
##
## NOT exercised by this PR's local verification (podman godot-ci headless
## import-check has no network egress guarantee and there's nothing to
## download yet). Review/test for real before flipping the launcher over
## to this source.

const API_URL := "https://api.github.com/repos/megumi-joy/VoxelWorldCraft/releases/latest"
const REQUEST_TIMEOUT_SEC := 15.0

var _http: HTTPRequest
var _timeout_timer: Timer

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.timeout = REQUEST_TIMEOUT_SEC
	_http.request_completed.connect(_on_request_completed)

func request_latest_version() -> void:
	var err := _http.request(API_URL, ["User-Agent: VoxelWorldCraft-Launcher"])
	if err != OK:
		latest_version_ready.emit({
			"ok": false, "version": "",
			"error": "Не удалось обратиться к GitHub (код %d). Проверьте подключение к интернету." % err,
		})

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		latest_version_ready.emit({
			"ok": false, "version": "",
			"error": "Сетевая ошибка при обращении к GitHub (код %d). Проверьте подключение к интернету." % result,
		})
		return

	if response_code != 200:
		latest_version_ready.emit({
			"ok": false, "version": "",
			"error": "GitHub вернул ошибку (HTTP %d) при запросе последнего релиза." % response_code,
		})
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("tag_name"):
		latest_version_ready.emit({
			"ok": false, "version": "",
			"error": "Не удалось разобрать ответ GitHub о последнем релизе.",
		})
		return

	var tag: String = str(parsed["tag_name"])
	var version: String = tag.substr(1) if tag.begins_with("v") else tag
	latest_version_ready.emit({"ok": true, "version": version, "error": ""})

## STUB: not implemented (see class doc comment above for why). Fails
## loudly and explicitly rather than silently doing nothing, so anyone who
## flips the launcher over to this source before this is built gets an
## immediate, obvious error instead of a mysterious no-op.
func fetch_update(_version: String, _dest_dir: String) -> void:
	update_downloaded.emit({
		"ok": false, "path": "",
		"error": "Обновление с GitHub пока не реализовано в этой версии лаунчера.",
	})
