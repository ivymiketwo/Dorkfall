shader_type canvas_item;
// Final screen grade for the world: a touch more saturation and contrast, a warm
// tint, a soft vignette and a little film grain. Sits above the world, below the HUD.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform float saturation = 1.14;
uniform float contrast = 1.06;
uniform vec3 tint = vec3(1.035, 1.0, 0.94);
uniform float vignette = 0.28;
uniform float grain = 0.025;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c *= tint;
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * smoothstep(0.25, 0.85, dot(d, d) * 2.2);
	c += (hash(floor(FRAGCOORD.xy * 0.5) + floor(TIME * 8.0)) - 0.5) * grain;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
