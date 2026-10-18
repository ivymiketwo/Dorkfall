"""One-off (October 2026): extends the painted cobblestone village street 48 world px east so it
reaches the new wizard tower's door. Edits ground squares g_3_2 and g_4_2: the street's last 48 px of
cobbles are copied onto the grass east of it and its end border is moved to the new end."""
from PIL import Image

# the street's end sits on the seam between two ground squares, so both are edited together
SQUARES = ["art/ground/g_3_2.png", "art/ground/g_4_2.png"]
SQ_ORIGIN = (3 * 1024, 2 * 1024)
WORLD_ORIGIN = (-1680, -992)
EXTEND = 48 * 2       # art px


def grey(c):
    return max(c) - min(c) < 40 and sum(c) < 700


def main():
    sq = Image.new("RGB", (2048, 1024))
    for i, f in enumerate(SQUARES):
        sq.paste(Image.open(f).convert("RGB"), (i * 1024, 0))
    px = sq.load()
    mid_y = (160 - WORLD_ORIGIN[1]) * 2 - SQ_ORIGIN[1]
    x = (380 - WORLD_ORIGIN[0]) * 2 - SQ_ORIGIN[0]
    while grey(px[x + 1, mid_y]):
        x += 1
    end = x                                        # last street column (its border)
    top = mid_y
    while grey(px[end - 20, top - 1]):
        top -= 1
    bot = mid_y
    while grey(px[end - 20, bot + 1]):
        bot += 1
    border = 2
    old = sq.copy()
    body = old.crop((end - border + 1 - EXTEND, top, end - border + 1, bot + 1))
    cap = old.crop((end - border + 1, top, end + 1, bot + 1))
    sq.paste(body, (end - border + 1, top))
    sq.paste(cap, (end - border + 1 + EXTEND, top))
    for i, f in enumerate(SQUARES):
        sq.crop((i * 1024, 0, (i + 1) * 1024, 1024)).save(f, optimize=True)
    print("street end", end, "rows", top, bot)


if __name__ == "__main__":
    main()
