// Céu de Maré de Vidro: gradiente frio, estrelas e um planeta crescente com
// o lado escuro visível (concept art 00).
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.031, 0.086, 0.125);
uniform vec3 mid_color : source_color = vec3(0.078, 0.212, 0.271);
uniform vec3 horizon_color : source_color = vec3(0.106, 0.259, 0.314);
uniform vec3 moon_dir = vec3(-0.45, 0.32, -0.83);
uniform vec3 moon_lit : source_color = vec3(0.91, 0.72, 0.47);
uniform vec3 moon_dark : source_color = vec3(0.094, 0.231, 0.290);
uniform float moon_size = 0.17;
uniform float star_amount = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 c = mix(horizon_color, mid_color, smoothstep(-0.05, 0.18, h));
	c = mix(c, top_color, smoothstep(0.18, 0.75, h));
	vec3 cell = floor(d * 180.0);
	float s = hash(cell);
	float star = step(0.9972, s) * smoothstep(0.02, 0.2, h) * star_amount;
	c += vec3(0.9, 0.85, 0.7) * star * (0.5 + 0.5 * hash(cell + 3.1));
	vec3 md = normalize(moon_dir);
	float ang = acos(clamp(dot(d, md), -1.0, 1.0));
	if (ang < moon_size) {
		vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
		vec3 up = cross(right, md);
		vec2 uv = vec2(dot(d, right), dot(d, up)) / sin(moon_size);
		float shadow = length(uv - vec2(0.32, 0.2)) - 0.93;
		float rim = smoothstep(1.0, 0.96, length(uv));
		c = mix(c, shadow < 0.0 ? moon_dark : moon_lit, rim);
	}
	COLOR = c;
}
