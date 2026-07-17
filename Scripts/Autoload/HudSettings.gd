extends Node
# HudSettings -- persists + live-applies the player's chosen HUD size ("HUD
# Size" / "Размер интерфейса" slider in Scenes/SettingsPanel.tscn).
#
# Knob: get_tree().root.content_scale_factor (Godot 4's global GUI scale).
# Verified empirically (probe render, before/after frame comparison) that
# with content_scale_mode switched to CANVAS_ITEMS, content_scale_factor
# scales HUD Controls (they're laid out in "virtual" pixels relative to
# content_scale_size) while the 3D world's camera-driven framing is
# untouched -- block sizes/positions on screen are identical before/after,
# only the HUD panels/buttons/hotbar grow or shrink.
#
# ---- Orientation- and resolution-consistent absolute HUD size ----
# This project's project.godot declares NO [display] window/stretch section,
# but Godot 4 does NOT treat that as "no scaling": content_scale_size
# silently defaults to the project's window/size (1280x720) rather than to
# the actual window size, and content_scale_aspect defaults to KEEP. Verified
# empirically (render + measured PNG dimensions) that this combination
# actively LETTERBOXES non-16:9 windows: a --resolution 540x960 (portrait)
# run rendered a viewport texture of only 540x303 -- Godot fit the 1280x720
# base to the window's width and left the rest of the portrait window as
# dead space outside the captured canvas. That's a real, pre-existing bug
# independent of the slider (any portrait window loses ~68% of its height),
# and it's WHY content_scale_mode=CANVAS_ITEMS alone made the slider's
# effective pixel size orientation/resolution-dependent: the automatic ratio
# Godot derives from (window size) vs (content_scale_size, KEEP) is
# axis-dependent and does not reduce to a single swap-invariant number.
#
# The fix is to stop relying on those defaults and set both explicitly:
#   - content_scale_size = a SQUARE reference (BASE_SHORT_SIDE x
#     BASE_SHORT_SIDE). Because both dimensions of the reference are equal,
#     Godot's own scale computation collapses to
#     min(window_w, window_h) / BASE_SHORT_SIDE -- i.e. keyed on the
#     window's SHORT side, which is swap-invariant (a 540x960 phone and the
#     same phone rotated to 960x540 both have min(w,h) == 540, so rotating
#     does not change the ratio -- the orientation ask) and scales with
#     physical screen size across devices independent of raw pixel/DPI count
#     (a high-DPI "2K" phone at 1080x2400 has the same short side, 1080, as
#     a 1080p laptop at 1920x1080, so both get the same on-screen HUD
#     fraction even though the phone has far more raw pixels -- the
#     resolution ask). A non-square reference (e.g. leaving the default
#     1280x720) would NOT collapse this way -- it stays axis-dependent and
#     reintroduces the orientation jump.
#   - content_scale_aspect = EXPAND, so the window's full pixel area is used
#     (no KEEP-mode letterbox bars); Controls anchored to edges/corners
#     (HUD.tscn's AIButton/SettingsButton anchor_right, Crosshair centered,
#     MessageLabel full-width) resolve against the real window edges. EXPAND
#     preserves aspect (unlike IGNORE, which would non-uniformly stretch/
#     squash circular and square HUD elements).
# With content_scale_size square, content_scale_factor no longer needs any
# extra multiplier of our own -- the slider's own value can be handed to it
# directly, and Godot's engine-native ratio computation supplies the
# resolution/orientation term. At the authored base resolution (1280x720,
# short side 720 == BASE_SHORT_SIDE) this reproduces HUD.tscn's originally
# authored pixel sizes exactly at slider=1.0, and for any 16:9 window
# min(w,h)/BASE_SHORT_SIDE == h/BASE_SHORT_SIDE, so existing landscape/laptop
# behavior the owner already approved is unchanged bit-for-bit; only non-16:9
# windows (portrait, 4:3 tablets, ...) change -- from letterboxed/broken to
# correct.
signal hud_scale_changed(value: float)

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "ui"
const KEY := "hud_scale"
const MIN_SCALE := 0.5
const MAX_SCALE := 2.0
const DEFAULT_SCALE := 1.0

# HUD.tscn's layout (StatsPanel, buttons, ...) is authored in pixel offsets
# against this project's authored base canvas -- project.godot's
# window/size is 1280x720, so 720 (the SHORT side of that base canvas) is
# the reference screen size at which slider=1.0 reproduces the originally
# authored pixel sizes exactly. Used as BOTH dimensions of the square
# content_scale_size below -- see the file-level comment for why it must be
# square.
const BASE_SHORT_SIDE := 720

var hud_scale: float = DEFAULT_SCALE

func _ready() -> void:
	hud_scale = _load_from_disk()
	# Defensive: re-apply if anything else ever changes the root window size
	# (a real device rotating, a runtime resize). Godot recomputes the
	# actual scale transform continuously from content_scale_size/aspect vs.
	# live window size on its own -- this hook exists only in case something
	# else ever resets content_scale_mode/size/aspect themselves.
	get_tree().root.size_changed.connect(_on_root_size_changed)
	_apply(hud_scale)

func set_hud_scale(value: float) -> void:
	value = clamp(value, MIN_SCALE, MAX_SCALE)
	if is_equal_approx(value, hud_scale):
		return
	hud_scale = value
	_apply(hud_scale)
	_save_to_disk(hud_scale)
	hud_scale_changed.emit(hud_scale)

func _on_root_size_changed() -> void:
	_apply(hud_scale)

func _apply(value: float) -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(BASE_SHORT_SIDE, BASE_SHORT_SIDE)
	root.content_scale_factor = value

func _load_from_disk() -> float:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		return DEFAULT_SCALE
	return clamp(float(cfg.get_value(SECTION, KEY, DEFAULT_SCALE)), MIN_SCALE, MAX_SCALE)

func _save_to_disk(value: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # best-effort merge -- keep any other future settings in the same file
	cfg.set_value(SECTION, KEY, value)
	cfg.save(SETTINGS_PATH)
