shader_type spatial;
// Subtle dithered/stippled darkening near each block face's edge -- a
// stylized "screen-print" outline on block boundaries, not a full
// retexture. Runs as a `next_pass` on the shared chunk material (see
// Scripts/World/TextureGenerator.gd) so the base StandardMaterial3D pass
// (atlas texture, alpha-scissor, vertex color) is completely untouched by
// this file; this pass only adds a soft, ordered-dither darkening within
// `edge_width` of each face's border. An ordered (Bayer) dither pattern in
// screen space is used instead of a smooth alpha gradient, which is what
// gives the stippled/hand-screen-printed look rather than a blurry
// vignette.
//
// Kept deliberately cheap for Potato-tier hardware: no texture samples, one
// small constant-array lookup, no loops/branches beyond two early discards.
// Not benchmarked on real low-end hardware (no GPU in the dev sandbox this
// was written in) -- if it ever turns out to cost more than expected, the
// fix is a one-line revert: drop the `next_pass` assignment in
// TextureGenerator.gd, this file doesn't need touching.
render_mode blend_mix, unshaded, cull_back, depth_draw_never;

// Chunk.gd's atlas is a fixed 8x8 grid (TEXTURE_ATLAS_SIZE / UV_SIZE there)
// and every mesh face's UV spans exactly one atlas cell (create_face()
// maps a single quad to [u_start, u_start+UV_SIZE] x [v_start,
// v_start+UV_SIZE]) -- so dividing by UV_SIZE and taking the fractional
// part recovers 0..1 face-local UV regardless of which atlas cell that
// particular face happens to sample, with no extra per-vertex data needed.
const float UV_SIZE = 1.0 / 8.0;

uniform float edge_width : hint_range(0.0, 0.5) = 0.07;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.35;
uniform vec3 edge_color : source_color = vec3(0.02, 0.02, 0.02);

const int BAYER_4X4[16] = int[16](
	0,  8,  2,  10,
	12, 4,  14, 6,
	3,  11, 1,  9,
	15, 7,  13, 5
);

void fragment() {
	vec2 local_uv = fract(UV / UV_SIZE);
	float edge_dist = min(min(local_uv.x, 1.0 - local_uv.x), min(local_uv.y, 1.0 - local_uv.y));
	float edge_factor = 1.0 - smoothstep(0.0, edge_width, edge_dist);
	if (edge_factor <= 0.001) {
		discard;
	}

	ivec2 pix = ivec2(mod(FRAGCOORD.xy, 4.0));
	float threshold = float(BAYER_4X4[pix.y * 4 + pix.x]) / 16.0;
	if (threshold > edge_factor) {
		discard;
	}

	ALBEDO = edge_color;
	ALPHA = edge_alpha;
}
