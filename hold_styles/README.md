# Hold styles

How an equipped item sits in the character's right hand.

## Item gripped at the bottom (swords, fishing rods, axes, spears...)
1. Make the item as usual: `worn_texture` = a worn-art sheet with the item drawn upright in the 24x40 cell at x=96
   (same as the staff / `art/worn_*_rod.png`), handle at the **bottom** of the picture.
2. On the item (`items/<name>.tres`) tick **Handle At Bottom**. That is all: it is held with
   `bottom_grip.tres` in all four directions (pointing forward and up, foreshortened toward/away from the camera,
   handle hidden behind the body or under the hand where it should be).
3. Optional: **Hold Scale** shrinks or grows just that item (the fishing rods use 0.654).

Everything the preset does is a number in `bottom_grip.tres` - change it and every bottom-grip item follows.
To give one item its own look, set its **Hold Style** to a copy of `bottom_grip.tres` (that always wins).

Order of choice: item Hold Style > Handle At Bottom (`bottom_grip.tres`) > `<weapon_kind>.tres` (staff, sword) > defaults.
