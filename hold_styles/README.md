# Hold styles = hand placement modules

There are two separate modules. Call them by these names:

- **Staff module / staff hand placement** - `staff.tres`. Two-handed staves (vertical, grip in the middle). Untouched by the 1-hand module.
- **1hand / melee hand placement module** - `melee_hand.tres`. One-handed items gripped at the bottom: swords, fishing rods, axes...

# Hold styles

How an equipped item sits in the character's right hand.

## One-handed items (swords, fishing rods, axes...) - automatic
Every equipped weapon that is **not** Two Handed is held with `melee_hand.tres` automatically - there is nothing to set.
Two-handed weapons (staves) keep their own style (`staff.tres`).

## Item gripped at the bottom - how to make one
1. Make the item as usual: `worn_texture` = a worn-art sheet with the item drawn upright in the 24x40 cell at x=96
   (same as the staff / `art/worn_*_rod.png`), handle at the **bottom** of the picture.
2. Equip slot Weapon, not Two Handed (or tick **Handle At Bottom** to force it for a two-handed one). That is all: it is held with
   `melee_hand.tres` in all four directions (pointing forward and up, foreshortened toward/away from the camera,
   handle hidden behind the body or under the hand where it should be).
3. Optional: **Hold Scale** shrinks or grows just that item (the fishing rods use 0.654).

Everything the preset does is a number in `melee_hand.tres` - change it and every bottom-grip item follows.
To give one item its own look, set its **Hold Style** to a copy of `melee_hand.tres` (that always wins).

Order of choice: item Hold Style > one-handed weapon / Handle At Bottom (`melee_hand.tres`) > `<weapon_kind>.tres` (staff) > defaults.

## How the 1hand module lines items up (always from the bottom of the sprite)
The hand is placed by measuring from the **bottom edge of the item's picture**, in pixels, so item size does not matter:
- If the item has a short handle under a crossguard (a sword), the hand sits in the middle of that handle (worked out from the picture).
- If it has no short handle (a fishing rod), the hand sits at the very bottom pixel.
- **Hold Grip Offset** (on the item): +3 / +4 leaves that many more pixels of the item showing below the hand; negative moves the hand toward the very bottom. 0 = automatic.
The staff module is not affected (it still uses its own grip number).
