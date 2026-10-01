shader_type canvas_item;
// Wind through the wheat: a gust band travels diagonally across the field and
// shears the pixels sideways, snapped to whole art pixels (tear-like look).
// Wave shape follows the Hearthlight reference: slow gust envelope * fast ripple.
uniform vec2 field_px = vec2(2400.0, 1600.0);
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float amp_px = 3.0;
uniform float gust_speed = 0.35;

void fragment() {
	vec2 p = UV * field_px;
	float along = dot(p, wind_dir);
	float gust = 0.5 + 0.5 * sin(TIME * gust_speed - along * 0.0028);
	gust = smoothstep(0.35, 0.95, gust);
	float ripple = sin(TIME * 1.9 - along * 0.012) * 0.65 + sin(TIME * 3.3 - along * 0.02) * 0.35;
	float row = floor(p.y / 4.0);
	float jitter = fract(sin(row * 12.9898) * 43758.5453) - 0.5;
	float off = floor((ripple * gust * amp_px + jitter * gust * 1.5) + 0.5);
	vec2 uv = vec2(UV.x + off / field_px.x, UV.y);
	COLOR = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
}
