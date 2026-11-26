// Água luminosa de Maré de Vidro: faixas de luz quebradas (concept art),
// cáusticas suaves e brilho de energia. Usada no oceano, bacias e pontes.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 deep : source_color = vec4(0.055, 0.227, 0.278, 1.0);
uniform vec4 shallow : source_color = vec4(0.118, 0.4, 0.44, 1.0);
uniform vec4 glow_color : source_color = vec4(0.486, 0.957, 0.863, 1.0);
uniform float opacity = 0.85;
uniform float streaks = 1.0;
uniform float scale = 1.0;
uniform vec2 flow = vec2(0.0);
uniform float energy = 0.15;
uniform float wave = 0.03;

varying vec3 wpos;

float h1(float n) { return fract(sin(n * 91.345) * 47453.5453); }

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(w.x * 0.35 + TIME * 0.9) * wave + cos(w.z * 0.27 + TIME * 0.7) * wave;
	wpos = w;
}

void fragment() {
	vec2 q = wpos.xz * scale + flow * TIME;
	float row = floor(q.y * 1.6);
	float r = h1(row);
	float x = q.x * (0.25 + r * 0.25) + TIME * (0.08 + r * 0.25) + r * 37.0;
	float dash = step(0.62 + r * 0.25, fract(x));
	float thin = smoothstep(0.16, 0.0, abs(fract(q.y * 1.6) - 0.5));
	float streak = dash * thin * streaks;
	float caust = 0.5 + 0.5 * sin(q.x * 1.7 + TIME * 1.3) * sin(q.y * 1.3 - TIME * 1.1);
	vec3 col = mix(deep.rgb, shallow.rgb, 0.35 + 0.3 * caust);
	col += glow_color.rgb * (streak * 0.9 + energy * (0.25 + 0.35 * caust));
	ALBEDO = col;
	ALPHA = opacity;
}
