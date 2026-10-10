// The ward's glass orb. Invisible on its own: an invisible light shines on it from the
// mouse's side, so the side facing the mouse glows faintly and it fades out to nothing on
// the far side. A faint hex pattern and a bright rim show only where the light falls.
// Drawn on a square texture; one texel = one screen pixel, so it stays on the pixel grid.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 light_dir = vec2(1.0, 0.0);     // screen direction toward the mouse (y down)
uniform float strength = 1.0;                // 0..1, fade in / out
uniform float px = 64.0;                     // texture size in pixels
uniform vec4 tint : source_color = vec4(0.55, 0.8, 1.0, 1.0);
uniform vec4 flash_col : source_color = vec4(1.0);
uniform float flash = 0.0;                   // 0..1, a hit was just stopped
uniform float time = 0.0;

// distance to the nearest edge of a hex grid cell (0 on the line)
float hex_edge(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	g = abs(g);
	return 0.5 - max(dot(g, normalize(s)), g.x);
}

void fragment() {
	// pixel centres, -1..1 across the orb
	vec2 p = (floor(UV * px) + 0.5) / (px * 0.5) - 1.0;
	float r2 = dot(p, p);
	if (r2 > 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec3 n = vec3(p.x, p.y, sqrt(1.0 - r2));          // sphere surface normal
		vec3 l = normalize(vec3(light_dir, 0.45));         // light a little in front of the screen
		float d = dot(n, l);
		float lit = clamp((d + 0.25) / 1.25, 0.0, 1.0);    // 1 facing the mouse, 0 round the back
		lit = lit * lit * (3.0 - 2.0 * lit);
		float rim = pow(1.0 - n.z, 1.6);                   // glass is brighter at its edge
		// hex pattern wrapped on the sphere (bulges out in the middle), slowly drifting
		vec2 hp = p / (0.55 + 0.45 * n.z) * 3.2 + vec2(0.0, time * 0.15);
		float hex = 1.0 - smoothstep(0.0, 0.12, hex_edge(hp));
		float edge = smoothstep(0.86, 0.97, sqrt(r2));     // a thin bright outline
		float a = lit * (0.14 + 0.55 * rim + 0.35 * hex + 0.55 * edge);
		a += flash * (0.15 + 0.5 * rim) * (0.4 + 0.6 * lit);
		a = floor(a * 10.0 + 0.5) / 10.0;                 // a few flat steps, pixel-art style
		vec3 col = mix(tint.rgb, vec3(1.0), clamp(pow(lit, 4.0) * edge * 0.6, 0.0, 1.0));
		col = mix(col, flash_col.rgb, clamp(flash, 0.0, 1.0));
		COLOR = vec4(col, clamp(a, 0.0, 0.9) * strength);
	}
}
