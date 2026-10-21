"""Cuts Rex's ranch fence sheet (art/fence_src/ranch_fence_sheet.png) into the pieces the game uses.

    python3 tools/cut_fence.py

Pieces (art px, drawn at half size; each stands on the bottom row of its picture):
  rfence_a / rfence_b / rfence_c  a post with 24 px of rails to its right: placed every 32 art px
                                  (16 world px) they join into one fence running left-right (the
                                  next piece's post covers the rail ends). b has the knotted rail.
  rfence_side                     a post with the rails running down the picture below it, for
                                  fences running up and down the screen (one every 32 art px;
                                  anchored at the post's foot, row 30, not the picture's bottom)
  rfence_post                     a plain post on its own (beside a gate)
  rfence_corner                   the big capped post (corners, ends)
  rfence_gate_open                the gate swung open, hinged on its post (post on the right)
"""
from PIL import Image

SRC = "art/fence_src/ranch_fence_sheet.png"


def crop(img, box):
    return img.crop(box)


def main():
    s = Image.open(SRC).convert("RGBA")
    post_a = s.crop((5, 8, 14, 39))                 # 9 x 31, left post of the plain section
    post_b = s.crop((37, 8, 46, 39))                # its right post (slightly different grain)
    rails_a = s.crop((14, 8, 37, 39))               # 23 px of plain rails (rows match the posts)
    rails_b = s.crop((64, 8, 87, 39))               # 23 px of the knotted section's rails
    rails_c = s.crop((70, 8, 93, 39))
    for name, post, rails in (("a", post_a, rails_a), ("b", post_b, rails_b), ("c", post_b, rails_c)):
        out = Image.new("RGBA", (32, 31))
        out.alpha_composite(rails, (9, 0))
        out.alpha_composite(post, (0, 0))
        out.save("art/rfence_%s.png" % name)
    # side piece (fence running up and down the screen): this post at the top, and the rails,
    # seen end-on, running straight down the picture to the next post 32 px below (both rails
    # line up from this angle, so one strip). The game anchors it at the post's foot (row 30)
    # and the next post, drawn later, covers the strip's end.
    strip = Image.new("RGBA", (7, 38))
    seg = rails_a.crop((2, 6, 21, 13)).rotate(90, expand=True)     # 7 x 19 of plain rail
    y = 0
    while y < strip.height:
        strip.alpha_composite(seg, (0, y))
        y += seg.height - 1
    side = Image.new("RGBA", (9, 48))
    side.alpha_composite(strip, (1, 10))
    side.alpha_composite(post_a, (0, 0))
    side.save("art/rfence_side.png")
    post_a.save("art/rfence_post.png")
    s.crop((110, 8, 124, 39)).save("art/rfence_corner.png")
    s.crop((94, 87, 123, 122)).save("art/rfence_gate_open.png")
    print("cut the fence pieces")


if __name__ == "__main__":
    main()
