shader_type canvas_item;
// Gentle breeze for ferns: the fronds sway more toward the top, and every
// plant is out of step with its neighbours (phase comes from where it stands).
uniform float amp = 1.4;        // in art pixels
uniform float speed = 1.5;

void vertex() {
	float h = 1.0 - UV.y;
	float ph = MODEL_MATRIX[3].x * 0.043 + MODEL_MATRIX[3].y * 0.031;
	VERTEX.x += (sin(TIME * speed + ph) + 0.4 * sin(TIME * speed * 2.3 + ph * 1.7)) * amp * h * h;
}
