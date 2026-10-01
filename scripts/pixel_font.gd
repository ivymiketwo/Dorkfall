class_name PixelFont
## Tiny built-in 3x5 pixel font so UI text stays crisp at native resolution.

# 3x5 glyphs, read left-to-right, top-to-bottom
const GLYPHS := {
	"0": "111101101101111", "1": "010110010010111", "2": "111001111100111",
	"3": "111001111001111", "4": "101101111001001", "5": "111100111001111",
	"6": "111100111101111", "7": "111001001001001", "8": "111101111101111",
	"9": "111101111001111", "/": "001001010100100", "H": "101101111101101",
	"P": "111101111100100", "S": "011100010001110", "T": "111010010010010",
	"M": "101111111101101", "F": "111100110100100", "A": "010101111101101",
	"V": "101101101010010", "O": "010101101101010", "R": "110101110101101",
	"D": "110101101101110", "Y": "101101010010010", "L": "100100100100111",
	"E": "111100110100111", "X": "101101010101101",
	"B": "110101110101110", "C": "011100100100011", "G": "011100101101011",
	"I": "111010010010111", "J": "001001001101010", "K": "101101110101101",
	"N": "110101101101101", "Q": "010101101111011", "U": "101101101101111",
	"W": "101101111111101", "Z": "111001010100111",
	"+": "000010111010000", ".": "000000000000010", "-": "000000111000000",
}


static func draw(canvas: CanvasItem, pos: Vector2, text: String, color: Color) -> void:
	for pass_color: Color in [Color(0, 0, 0, 0.7), color]:
		var offset := Vector2.ONE if pass_color != color else Vector2.ZERO
		for i in text.length():
			var glyph: String = GLYPHS.get(text[i], "")
			for p in glyph.length():
				if glyph[p] == "1":
					var px := pos + offset + Vector2(i * 4 + p % 3, floori(p / 3.0))
					canvas.draw_rect(Rect2(px, Vector2.ONE), pass_color)
