shader_type spatial;
// Cheap vertex-only wind sway for the grass tuft MultiMesh (FoliageRenderer.gd).
// No fragment-shader cost beyond reading the per-instance MultiMesh color as
// albedo (grass tufts have no texture -- flat-shaded like the rest of this
// project's chunky/hypercasual look).
//
// unshaded, not diffuse_lambert: a lit blade under this world's default
// DirectionalLight3D/ambient came out visibly darker than the bright block
// palette it's meant to match (confirmed via the podman/Xvfb capture in
// tools/verify_headless.sh -- a lit tuft was a dark, hard-to-read blob
// against the grass block underneath it). Unshaded keeps the exact
// GRASS_COLORS/LEAF_COLORS/PETAL_COLORS values on screen regardless of
// time-of-day, matching the owner's "bright/chunky, reads clearly" art
// direction instead of "subtle, mood-lit".
render_mode cull_disabled, unshaded, blend_mix;

uniform float wind_strength : hint_range(0.0, 1.0) = 0.18;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.6;

void vertex() {
	// Blade mesh is authored with its base at local y=0 and tip at local
	// y=BLADE_HEIGHT (see FoliageRenderer._build_blade_mesh), so VERTEX.y
	// itself is the "how close to the tip" weight -- the base never moves
	// (stays planted), the tip sways the most.
	float sway_weight = VERTEX.y;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Phase offset by world position so neighboring tufts don't sway in
	// lockstep -- reads as a wind field instead of a single spring.
	float phase = world_pos.x * 0.35 + world_pos.z * 0.35;
	float sway = sin(TIME * wind_speed + phase) * wind_strength * sway_weight;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
