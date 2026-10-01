shader_type canvas_item;
// Animated shoreline foam and drifting glints over a pond. The sprite's texture
// is a distance map (R = distance to shore in half-art-pixels, 0 = not water).
// Technique follows Hearthlight's water shader (MIT, see THIRD_PARTY_NOTICES.md).
uniform vec3 tint = vec3(1.0);

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 info = texture(TEXTURE, UV);
	float d = info.r * 255.0;
	if (info.a < 0.5 || d < 0.5) discard;
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE / 2.0);   // work on a 2x2 art-pixel grid
	float f = floor(TIME * 2.4);
	vec3 foam = vec3(0.906, 0.965, 0.957) * tint;
	float wob = floor(h21(floor(px / 8.0)) * 4.0);
	float phase = mod(f + wob, 4.0);
	float reach = phase < 1.0 ? 1.5 : phase < 2.0 ? 2.5 : phase < 3.0 ? 3.5 : 2.5;
	if (d <= reach) {
		float solid = step(d, reach - 1.0) + step(d, 1.5);
		if (solid < 0.5 && mod(px.x + px.y + f, 2.0) > 0.5) discard;
		COLOR = vec4(foam, solid > 0.5 ? 0.9 : 0.6);
	} else if (d > 5.0 && d <= 6.5 && mod(floor(px.x / 2.0) + f, 5.0) < 1.0) {
		COLOR = vec4(foam, 0.35);
	} else if (d > 8.0) {
		vec2 cell = vec2(floor((px.x + f * 2.0) / 24.0), floor(px.y / 10.0));
		float hv = h21(cell + f * 7.13);
		COLOR = vec4(0.0);
		if (hv < 0.16) {
			float gx = cell.x * 24.0 + floor(h21(cell + 3.1) * 16.0) - f * 2.0;
			float gy = cell.y * 10.0 + floor(h21(cell + 5.7) * 8.0);
			float len = 2.0 + floor(h21(cell + 9.3) * 3.0);
			vec3 g1 = vec3(0.475, 0.741, 0.863) * tint;
			vec3 g2 = vec3(0.663, 0.863, 0.933) * tint;
			if (px.y == gy && px.x >= gx && px.x < gx + len) COLOR = vec4(hv < 0.06 ? g2 : g1, 0.86);
			else if (px.y == gy - 1.0 && px.x >= gx + 1.0 && px.x < gx + len - 1.0 && hv < 0.08) COLOR = vec4(g1, 0.63);
		}
		if (COLOR.a == 0.0) discard;
	} else {
		discard;
	}
}
