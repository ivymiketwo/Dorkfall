shader_type canvas_item;
// Idle breathing for sprite sheets: everything above `split_row` of each frame drops
// `shift_rows` art rows when `bob` is 1, sliding over the legs (never opening a gap).
// Shared by the body and every gear layer so they move together.
uniform float bob = 0.0;
uniform float vframes = 4.0;
uniform float split_row = 29.0;
uniform float shift_rows = 2.0;

void fragment() {
	vec2 tsize = vec2(textureSize(TEXTURE, 0));
	float frame_h = tsize.y / vframes;
	float fr = floor(UV.y * vframes);
	float row = floor(UV.y * tsize.y - fr * frame_h + 0.0001);
	vec2 uv = UV;
	float s = bob * shift_rows;
	if (s > 0.0 && row < split_row + s) {
		float src = row - s;
		if (src < 0.0) {
			COLOR = vec4(0.0);
		} else {
			uv.y = (fr * frame_h + src + 0.5) / tsize.y;
			COLOR = texture(TEXTURE, uv);
		}
	}
}
