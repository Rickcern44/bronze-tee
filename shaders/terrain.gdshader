shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Terrain surfaces, classified per fragment. This mirrors Surface/_surface_at in
// scripts/main.gd (same order: water, green, collar, path, tee, fairway, first
// cut, second cut, deep rough). main.gd's _update_terrain_uniforms feeds every
// parameter below on each hole load, so geometry numbers live only in GDScript.
// Textures are albedo-only, so no low-frequency noise is applied.

uniform sampler2D green_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D collar_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D fairway_light_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D fairway_dark_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D first_cut_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D second_cut_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D deep_rough_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D water_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D path_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;

// Baked surface map (.srf), used instead of the parametric shapes when
// use_surface_map is set. Both samplers get the same FORMAT_LA8 texture, which
// samples as (L, L, L, A): the surface ID is in .r and the boundary distance
// (0.1 m units, 255 = 25.5 m) in .a. Never read the distance from .g.
uniform bool use_surface_map = false;
uniform sampler2D surface_ids : filter_nearest, repeat_disable;
uniform sampler2D surface_distances : filter_linear, repeat_disable;
uniform vec2 surface_origin; // world x/z of sample (0, 0): min X, max Z
uniform vec2 surface_dimensions; // samples (columns, rows); rows advance toward -Z
uniform float surface_spacing = 0.5;
// .srf surface IDs. These must equal enum Surface in scripts/main.gd;
// tests/surface_map_check.gd fails if they differ.
const int SRF_DEEP_ROUGH = 0;
const int SRF_SECOND_CUT = 1;
const int SRF_FIRST_CUT = 2;
const int SRF_FAIRWAY = 3;
const int SRF_GREEN = 4;
const int SRF_COLLAR = 5;
const int SRF_TEE = 6;
const int SRF_PATH = 7;
const int SRF_WATER = 8;
const int SRF_BUNKER = 9;
const int SRF_COUNT = 10;

// Geometry (metres, world x/z), set from main.gd.
uniform vec4 water_ellipses[4]; // x, z centre; x, z radii
uniform int water_count = 0;
uniform vec2 cup = vec2(0.0);
uniform vec2 green_radii = vec2(15.5, 14.5);
uniform float collar_ratio = 1.15;
uniform vec4 tee_ellipse = vec4(0.0, -2.0, 7.0, 6.0);
uniform vec4 extra_tees[2];
uniform int extra_tee_count = 0;
uniform float path_center_x = 27.0;
uniform float path_sway = 2.0;
uniform float path_sway_frequency = 0.012;
uniform float path_half_width = 1.8;
uniform vec2 path_z_range = vec2(-340.0, 4.0); // min z, max z
uniform float fairway_sway = 0.8;
uniform float fairway_sway_frequency = 0.012;
uniform float dogleg_offset = 0.0;
uniform float dogleg_start = 210.0;
uniform float dogleg_end = 370.0;
uniform vec2 fairway_centerline[4];
uniform int fairway_centerline_count = 0;
uniform float fairway_base_width = 15.5;
uniform float fairway_bulge = 2.0;
uniform float fairway_tee_end_z = -22.0;
uniform float fairway_green_end_offset = 4.0;
uniform float first_cut_width = 3.0;
uniform float second_cut_width = 6.0;
uniform float mow_band_length = 24.0;

// Texture tile sizes in metres (the cart path tile spans the path width).
uniform float grass_tile = 4.0;
uniform float water_tile = 6.0;

// Edge styling. Colours are defined only here.
uniform float step_shadow = 0.30;       // inner shadow on the shorter cut
uniform float step_shadow_width = 0.5;  // metres
uniform float green_shadow = 0.22;
uniform vec4 bank_color : source_color = vec4(0.07, 0.22, 0.06, 1.0);
uniform float bank_strength = 0.5;
uniform float bank_width = 1.2;
uniform vec4 shallow_color : source_color = vec4(0.62, 0.92, 0.98, 1.0);
uniform float shallow_strength = 0.55;
uniform float shallow_width = 1.1;
uniform float path_edge_dark = 0.18;
uniform float path_edge_width = 0.25;
uniform float water_roughness = 0.12;
uniform float albedo_gain = 0.75; // compensates the scene's bright sun + ambient so albedo does not clip

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// Approximate signed distance (metres, negative inside) to an axis-aligned ellipse.
float ellipse_sdf(vec2 p, vec2 centre, vec2 radii) {
	vec2 q = (p - centre) / radii;
	float len = max(length(q), 1e-4);
	return (len - 1.0) * len / max(length(q / radii), 1e-5);
}

// Antialiased inside-mask for a signed distance.
float inside(float d) {
	float aa = max(fwidth(d) * 0.75, 1e-4);
	return 1.0 - smoothstep(-aa, aa, d);
}

// 1 at the boundary, fading to 0 across `width` metres inside (d < 0).
float inner_band(float d, float width) {
	return 1.0 - smoothstep(0.0, width, -d);
}

// 1 at the boundary, fading to 0 across `width` metres outside (d > 0).
float outer_band(float d, float width) {
	return 1.0 - smoothstep(0.0, width, d);
}

// Surface ID of one map sample; outside the map, or unknown, is deep rough.
int mapped_id(vec2 cell) {
	if (any(lessThan(cell, vec2(0.0))) || any(greaterThanEqual(cell, surface_dimensions))) return SRF_DEEP_ROUGH;
	int id = int(floor(texelFetch(surface_ids, ivec2(cell), 0).r * 255.0 + 0.5));
	return id < SRF_COUNT ? id : SRF_DEEP_ROUGH;
}

void fragment() {
	vec2 p = world_xz;

	// Signed distances, negative inside each surface.
	float fairway_width = fairway_base_width + fairway_bulge * sin(clamp(p.y / cup.y, 0.0, 1.0) * 3.14159265);
	float dogleg_shift = dogleg_offset * smoothstep(dogleg_start, dogleg_end, -p.y);
	if (fairway_centerline_count >= 2) {
		dogleg_shift = fairway_centerline[fairway_centerline_count - 1].x;
		for (int i = 0; i < 3; i++) {
			if (i + 1 >= fairway_centerline_count) break;
			vec2 a = fairway_centerline[i];
			vec2 b = fairway_centerline[i + 1];
			if (p.y >= b.y) {
				dogleg_shift = mix(a.x, b.x, clamp((a.y - p.y) / (a.y - b.y), 0.0, 1.0));
				break;
			}
		}
	}
	float fairway_center = fairway_sway * sin(-p.y * fairway_sway_frequency) + dogleg_shift;
	float end_distance = max(max(p.y - fairway_tee_end_z, cup.y - fairway_green_end_offset - p.y), 0.0);
	float edge = length(vec2(p.x - fairway_center, end_distance)) - fairway_width;
	float d_first = edge - first_cut_width;
	float d_second = edge - first_cut_width - second_cut_width;
	float d_green = ellipse_sdf(p, cup, green_radii);
	float d_collar = ellipse_sdf(p, cup, green_radii * collar_ratio);
	float d_tee = ellipse_sdf(p, tee_ellipse.xy, tee_ellipse.zw);
	for (int i = 0; i < 2; i++) {
		if (i < extra_tee_count) d_tee = min(d_tee, ellipse_sdf(p, extra_tees[i].xy, extra_tees[i].zw));
	}
	float path_x = path_center_x + path_sway * sin(p.y * path_sway_frequency) + dogleg_shift;
	float d_path = max(abs(p.x - path_x) - path_half_width, max(p.y - path_z_range.y, path_z_range.x - p.y));
	float d_water = 1e4;
	for (int i = 0; i < 4; i++) {
		if (i < water_count) {
			d_water = min(d_water, ellipse_sdf(p, water_ellipses[i].xy, water_ellipses[i].zw));
		}
	}

	// Textures (all sampled unconditionally to keep derivatives uniform).
	vec2 guv = p / grass_tile;
	vec3 t_green = texture(green_texture, guv).rgb;
	vec3 t_collar = texture(collar_texture, guv).rgb;
	vec3 t_fw_light = texture(fairway_light_texture, guv).rgb;
	vec3 t_fw_dark = texture(fairway_dark_texture, guv).rgb;
	vec3 t_first = texture(first_cut_texture, guv).rgb;
	vec3 t_second = texture(second_cut_texture, guv).rgb;
	vec3 t_deep = texture(deep_rough_texture, guv).rgb;
	// Path: u runs across the path, v along it, so the joint repeats every path width.
	float path_width = path_half_width * 2.0;
	vec3 t_path = texture(path_texture, vec2((p.x - path_x) / path_width + 0.5, p.y / path_width)).rgb;
	// Water drifts in two slightly different directions and the layers are blended.
	vec2 wuv = p / water_tile;
	vec3 t_water = 0.5 * (texture(water_texture, wuv + TIME * vec2(0.012, 0.005)).rgb
			+ texture(water_texture, wuv * 1.17 + vec2(0.37, 0.61) - TIME * vec2(0.007, 0.010)).rgb);

	// Mow bands: same 24 m period as before (light for half, dark for half).
	float band = -p.y / mow_band_length;
	float wave = sin(6.28318531 * band);
	float dark = 1.0 - smoothstep(-max(fwidth(wave), 1e-4), max(fwidth(wave), 1e-4), wave);
	vec3 t_fairway = mix(t_fw_light, t_fw_dark, dark);

	// Painter's order: lowest priority first. Each shorter surface carries an
	// inner shadow just inside its boundary against the longer cut around it.
	vec3 col = t_deep;
	col = mix(col, t_second * (1.0 - step_shadow * inner_band(d_second, step_shadow_width)), inside(d_second));
	col = mix(col, t_first * (1.0 - step_shadow * inner_band(d_first, step_shadow_width)), inside(d_first));
	col = mix(col, t_fairway * (1.0 - step_shadow * inner_band(edge, step_shadow_width)), inside(edge));
	col = mix(col, t_fw_light * (1.0 - step_shadow * inner_band(d_tee, step_shadow_width)), inside(d_tee));
	vec3 path_col = t_path * (1.0 - path_edge_dark * inner_band(d_path, path_edge_width));
	col = mix(col, path_col, inside(d_path));
	col = mix(col, t_collar * (1.0 - step_shadow * 0.8 * inner_band(d_collar, step_shadow_width)), inside(d_collar));
	col = mix(col, t_green * (1.0 - green_shadow * inner_band(d_green, step_shadow_width)), inside(d_green));

	// Water: dark bank outside the edge, pale shallow band just inside.
	float water_mask = inside(d_water);
	float bank = outer_band(d_water, bank_width) * (1.0 - water_mask) * bank_strength;
	col = mix(col, bank_color.rgb, bank);
	vec3 water_col = mix(t_water, shallow_color.rgb, inner_band(d_water, shallow_width) * shallow_strength);
	col = mix(col, water_col, water_mask);
	if (use_surface_map) {
		// Map grid coordinates: sample (i, j) sits at integer (i, j).
		vec2 grid = vec2(p.x - surface_origin.x, surface_origin.y - p.y) / surface_spacing;
		float dist = texture(surface_distances, (grid + vec2(0.5)) / surface_dimensions).a * 25.5;
		float shadow = 1.0 - step_shadow * (1.0 - smoothstep(0.0, step_shadow_width, dist));
		// Palette indexed by surface ID. Colours, never the numeric IDs, are
		// blended between the four surrounding samples to smooth sub-texel edges.
		vec3 palette[SRF_COUNT];
		palette[SRF_DEEP_ROUGH] = t_deep;
		palette[SRF_SECOND_CUT] = t_second * shadow;
		palette[SRF_FIRST_CUT] = t_first * shadow;
		palette[SRF_FAIRWAY] = t_fairway * shadow;
		palette[SRF_GREEN] = t_green * shadow;
		palette[SRF_COLLAR] = t_collar * shadow;
		palette[SRF_TEE] = t_fw_light * shadow;
		palette[SRF_PATH] = t_path;
		palette[SRF_WATER] = mix(t_water, shallow_color.rgb, (1.0 - smoothstep(0.0, shallow_width, dist)) * shallow_strength);
		palette[SRF_BUNKER] = vec3(0.66, 0.59, 0.43); // Flat sand until RCE-170 adds a texture.
		vec2 cell = floor(grid);
		vec2 fraction = grid - cell;
		int id00 = mapped_id(cell);
		int id10 = mapped_id(cell + vec2(1.0, 0.0));
		int id01 = mapped_id(cell + vec2(0.0, 1.0));
		int id11 = mapped_id(cell + vec2(1.0, 1.0));
		col = mix(mix(palette[id00], palette[id10], fraction.x), mix(palette[id01], palette[id11], fraction.x), fraction.y);
		float wet00 = id00 == SRF_WATER ? 1.0 : 0.0;
		float wet10 = id10 == SRF_WATER ? 1.0 : 0.0;
		float wet01 = id01 == SRF_WATER ? 1.0 : 0.0;
		float wet11 = id11 == SRF_WATER ? 1.0 : 0.0;
		water_mask = mix(mix(wet00, wet10, fraction.x), mix(wet01, wet11, fraction.x), fraction.y);
		// Dark bank on dry ground within bank_width of water.
		vec2 nearest = floor(grid + vec2(0.5));
		float reach = ceil(bank_width / surface_spacing);
		bool water_nearby = mapped_id(nearest + vec2(reach, 0.0)) == SRF_WATER || mapped_id(nearest - vec2(reach, 0.0)) == SRF_WATER
				|| mapped_id(nearest + vec2(0.0, reach)) == SRF_WATER || mapped_id(nearest - vec2(0.0, reach)) == SRF_WATER;
		if (mapped_id(nearest) != SRF_WATER && water_nearby) {
			col = mix(col, bank_color.rgb, (1.0 - smoothstep(0.0, bank_width, dist)) * bank_strength * (1.0 - water_mask));
		}
	}

	ALBEDO = col * albedo_gain;
	ROUGHNESS = mix(1.0, water_roughness, water_mask);
	SPECULAR = mix(0.5, 0.9, water_mask);
}
