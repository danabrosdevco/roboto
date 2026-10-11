# Brief — dress wool, for the vehicle headgear

Written 2026-10-06 by GAMEPLAY, off six rounds of in-game mock-ups of the
vehicle rank hats (`tools/mockup_shots.gd -- <dir> vhat`). The geometry is
settled; the surface is not. The headgear currently resolves
`mockup_parts.wool_material()`, which looks for `beret_wool.tres`, fails, and
falls back to a flat `StandardMaterial3D` at albedo 0.17/0.19/0.17 — in the
renders it reads as grey putty.

Owner: **whoever takes it**. Status: **not started**.

**Deliverable:** two entries in `tools/make_textures.gd` — `beret_wool` and
`beret_wool_worn` — each with a `_mask.png`, built the same way `camo_fabric`
and the `pauldron_plate` set were. No pixel of the bought pack gets read,
sampled or filtered; the licence is kept by drawing from nothing and copying
only the style, which is what that file already does.

The moment `beret_wool.tres` exists, the kit picks it up with no code change —
`wool_material()` already resolves it by name and warns when it is missing.

---

## Why this is not camo

The headgear used `camo_fabric` and it was wrong twice over.

**Camo is a disruptive pattern. Its entire job is to stop a shape being read.**
A rank mark exists to be read, at squad distance, by a player deciding which of
six robots to give an order to. Those two purposes are in direct opposition, and
the pattern wins — a camo beret on a camo vehicle is a smudge.

**It is also far too dark.** Measured with `tools/probe_texture_stats.gd`:

| | mean | peak | sat | in band |
|---|---|---|---|---|
| `camo_fabric` | 0.130 | 0.253 | 0.227 | 0.2% |
| pack convention | ~0.20 | ≤0.46 | 0.08–0.25 | — |

At mean 0.130 the beret photographed as a dark lump on a pale hull — the note in
the render review was "a lil pile of poo", which is accurate. Dress wool is
plain, dense, and slightly *warmer* than the steel beside it, not darker.

## What it goes on

Five pieces, all of them bevelled slabs rather than curved shells, which matters
more than usual:

| piece | shape | size on screen at 20 m |
|---|---|---|
| beret crown | three chamfered courses, 1.14 down to 0.66 | ~34 px across |
| beret droop | one slab, 0.40 × 0.84, hanging past the turret edge | ~12 px |
| beret flash | 0.24 × 0.27, upright behind the cap badge | ~7 px |
| Tarleton turban | 1.12 × 1.00 × 0.10, a wide thin band | ~8 px band |
| Tarleton roach | four courses, 1.02 down to 0.38 | ~30 px tall |

Three consequences:

**1. It is seen on FLAT faces meeting at hard angles.** Not a dome. Every one of
these is a chamfered octagonal slab, so the texture lands on big flat planes
with 45° chamfers between them. This is the opposite of the pauldron brief — no
UV stretching to design around, but also no curvature to hide a repeat. **A
visible tile boundary will be obvious here**, so the pattern must be seamless
and non-directional.

**2. No directional weave.** The courses are stacked with alternating
orientations and the roach is turned a quarter relative to the crown. A twill or
any diagonal grain will run different ways on adjacent pieces of the same hat.
Felted, not woven.

**3. It is small, and it is the thing the player reads rank from.** The roach is
about 30 px tall at squad distance and the flash 7 px. Nothing in this texture
should be smaller than about 8 texels at 256.

## The one real decision: this one SHOULD take the faction colour

This is where the brief departs from both of its predecessors.

`Character/faction_metal.gdshader` repaints by luminance band — centre 0.45,
width 0.425. `camo_fabric` sits deliberately *under* the band (0.2% repainted)
because camo that turns flat faction orange is not camo. The pauldron plate sits
mostly inside it (52%).

**A beret is regimental identity worn on the head.** It is the single piece on
the vehicle whose entire purpose is to say *whose* this robot is and *how senior*
— so it should be the most strongly repainted thing in the kit, not the least.
A player's officer Rover should wear a plainly cyan beret and an enemy's a
plainly amber one, legible across a valley.

So: **70–85% in band**, higher than anything else in the pack. Hold out of the
mask only:

- the **fold shadows** where the droop falls past the band, so the slouch keeps
  its form instead of flattening into one colour
- a **slightly darker rim** on the lowest course, which is where a real beret's
  leather band shows under the wool

Use the `_mask.png` red channel with `derive_mask_from_albedo = false`, as the
epaulettes and the pauldron plate do. Green is 0: no emissive on cloth.

## Numbers to hit

Checked with `godot --headless --path . --script res://tools/probe_texture_stats.gd -- textures/PSX_Textures beret`

- 256×256, RGB8
- mean luminance **0.22–0.28**. Above the pack's 0.20 and well above camo's
  0.130, because this is maintained dress worn to be seen.
- peak **≤ 0.46**. **Hold this one.** `pauldron_plate` shipped at peak 0.701
  against the same ceiling and the result photographs as polished chrome rather
  than steel — it is the outstanding defect in the rank kit. There is no white
  anywhere in the pack and there should be none here.
- saturation **0.06–0.12**. Lower than anything else in the pack on purpose:
  the faction supplies the colour at 70–85% coverage, and a wool that brings its
  own hue will fight it harder than a texture at 38% coverage would.
- in band **70–85%** on the albedo.
- quantised to 32 levels a channel through the same 4×4 ordered dither
  everything else in that file uses.

## What should be in it

In rough order of how much work each does at distance:

1. **A fine felted speckle** — two or three luminance steps, hard-edged, grain
   around 8–10 texels. This is almost the whole texture. Wool at 30 px reads as
   a slightly restless flat colour, and that restlessness is the only thing
   separating it from a painted plane.
2. **Broad soft blotching** at very low amplitude, 60–80 texels across, to stop
   the speckle reading as uniform noise. Low contrast — this should be felt
   rather than seen.
3. **A nap direction shift**: two or three large regions a few percent apart in
   luminance, with soft irregular borders. Real pressed wool catches light in
   patches. No straight edges.
4. **Fibre flecks**: a sparse scatter of single lighter and darker pixels,
   maybe 1 in 400. Not a grid, not evenly spread.
5. **`_worn`**: the same wool after a campaign — the nap rubbed flat and
   slightly brighter on the high points, a thinned patch or two, the speckle
   partly polished out. The relationship between `beret_wool` and
   `beret_wool_worn` should match the one between `camo_fabric` and
   `camo_fabric_worn`, so the pair can be swapped by rank or by missions
   survived later without a second conversation.

## What should not

- **Camo blobs.** Covered above. This texture exists because camo was wrong.
- **Any directional weave, twill or ribbing.** It will run different ways on
  adjacent faces of the same hat.
- **A visible tile seam.** These are flat slabs and it will show.
- **Anything finer than ~8 texels.** It will not survive a 7 px flash.
- **White, or anything above 0.46.** See the pauldron plate.

## How to check it is right

Three steps, in this order. The third is the one that matters.

1. `probe_texture_stats.gd` for the numbers above.
2. Nothing to wire — `wool_material()` already loads it by name.
3. **Re-run the vehicle hat shots and look at them.** `godot --audio-driver
   Dummy --path . --script res://tools/mockup_shots.gd -- <dir> vhat` gives
   veteran-against-officer pairs and a close for each of the three frames. Six
   rounds of this is how the geometry got from a flat lump to a beret with a
   slouch, and every one of those rounds was a thing that looked fine reasoned
   about and wrong photographed. A wool that passes the stats and still reads as
   putty in the close-ups has failed.

## Open question for the human

The Tarleton's **roach** is fur in the real article, not wool — a different
material entirely, coarser and darker, and on a 3 m walker it is the single
biggest piece of cloth in the game. It currently shares `beret_wool` because one
texture is cheaper than two. If it wants its own `crest_fur`, that is a third
entry and should be asked for rather than assumed; the roach reads as a shape
long before it reads as a surface, so it is a real question whether it is worth
the work.
