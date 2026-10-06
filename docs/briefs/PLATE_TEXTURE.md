# Brief — plate steel, for the rank pauldrons

Written 2026-10-05 by GAMEPLAY, off eight rounds of in-game mock-ups of the
promotion kit (`tools/mockup_shots.gd -- <dir> rank`). The geometry is settled;
the surface is not. The pauldrons currently use `mockup_parts.armor_material()`,
which is a flat untextured `StandardMaterial3D` — albedo 0.13/0.17/0.19,
roughness 0.42, metallic 0.75 — and in the renders it reads as smooth dark
plastic.

Owner: **whoever takes it**. Status: **not started**.

**Deliverable:** two entries in `tools/make_textures.gd` — `plate_steel` and
`plate_steel_worn` — each with a `_mask.png`, built the same way `camo_fabric`
and the `epaulette_*` set were. No pixel of the bought pack gets read, sampled
or filtered; the licence is kept by drawing from nothing and copying only the
style, which is what that file already does.

---

## What it goes on

Not a wall. Three specific pieces, and the difference matters more than usual:

| piece | shape | size on screen at 20 m |
|---|---|---|
| shoulder dome | squashed sphere, r 0.40, cupping the shoulder point | ~30 px across |
| rolled rim | torus round the dome's lower edge | ~6 px band |
| four lames | bands cut from a cylinder of the hull's radius, 0.145 m tall | ~12 px each |

Three consequences:

**1. It is seen on curves, never flat.** The dome is a squashed sphere and the
lames are arcs. UVs stretch at the dome's poles and compress at the lames' ends.
A pattern with a strong direction in it will fight that; a pattern with a
*horizontal* grain will run along the lames, which is the way rolled steel is
actually finished and the one direction that helps.

**2. It is small.** A lame is about twelve pixels tall at squad distance. Fine
noise turns to grey mush at that size — the camo entry in `make_textures.gd`
already says this about blobs and it is twice as true here. Nothing in this
texture should be smaller than about 8 texels at 256.

**3. It is kit a robot has earned and maintains.** Not a derelict. The pack's
`metal_rusty_tsk_*` family sits at saturation 0.53 and is right for a shelled
bridge; it is wrong for a promotion. This should read as **cared for and used**,
which is a different thing from rusted.

## The one real decision: how much of it the faction repaints

`Character/faction_metal.gdshader` repaints by luminance band — centre 0.45,
width 0.425 as it is called. Measured with `tools/probe_texture_stats.gd`, the
pack's existing choices sit at opposite ends on purpose:

| | mean | peak | sat | repainted |
|---|---|---|---|---|
| `camo_fabric` | 0.130 | 0.253 | 0.227 | **0.2%** |
| `epaulette_plain` | 0.287 | 0.446 | 0.134 | **90.2%** |
| `metal_wall_tx_1` | 0.227 | 0.501 | 0.253 | 38.6% |
| pack convention | ~0.20 | ≤0.46 | 0.08–0.25 | — |

Camo is deliberately under the band, because a disruptive pattern that turns
flat faction orange is not camo. The epaulette board is deliberately inside it,
because that is where a faction is read at a glance.

**A pauldron wants both, and that is what the mask is for.** Paint the field;
leave the edges alone:

- **Inside the band (takes the faction colour):** the plate field. This is the
  large smooth area of each lame and the dome's crown. It should be the majority
  of the texture — **55–70% in band**, so a player's pauldron is plainly cyan
  and an enemy's plainly amber at two hundred metres.
- **Held out by the mask (stays steel):** the rolled edges, the rivet heads, and
  the scuffed high points. Real painted armour wears back to bright metal
  exactly there, and keeping those out of the paint is what will stop the piece
  reading as one flat coloured blob.

Use the `_mask.png` red channel with `derive_mask_from_albedo = false`, as the
epaulettes do. Green is 0: no emissive markers on armour.

## Numbers to hit

Checked with `godot --headless --path . --script res://tools/probe_texture_stats.gd -- textures/PSX_Textures plate`

- 256×256, RGB8
- mean luminance **0.20–0.26**. Slightly above the pack's 0.20 because this is
  maintained kit standing next to weathered concrete, but not above 0.26 or it
  starts to glow in a level.
- peak **≤ 0.46**. There is no white anywhere in the pack and there should be
  none here.
- saturation **0.10–0.18**. Low on purpose — the faction supplies the colour,
  and a texture that brings its own will fight it.
- in band **55–70%** on the albedo.
- quantised to 32 levels a channel through the same 4×4 ordered dither
  everything else in that file uses. The banding is most of what makes the pack
  read as PSX rather than as low resolution.

## What should be in it

In rough order of how much work each does at distance:

1. **A horizontal brushed grain**, running along the lames. Hard-edged streaks,
   not a soft gradient — the file's rule is no soft gradients anywhere.
2. **A broad highlight band** across the upper third. GL compatibility lights
   flat and these pieces are curved, so the sweep of light that makes real plate
   read has to be painted in. This is the single detail most likely to make it
   look like steel instead of plastic.
3. **Edge wear**: brighter, desaturated scuffing concentrated where a rolled
   edge or a rivet would sit. Masked out of the faction paint.
4. **A few hard scratches**, long and thin, at a shallow angle to the grain.
   Four or five, not forty.
5. **`_worn`**: the same plate after a campaign. Paint thinned over the high
   points, more edge metal showing, a dent or two. The relationship between
   `plate_steel` and `plate_steel_worn` should match the one between
   `camo_fabric` and `camo_fabric_worn`, so the pair can be swapped by rank or
   by missions survived later without a second conversation.

## What should not

- **Rust.** Covered above. If a rusted variant is ever wanted it is a third
  entry, not a change to these.
- **Rivets drawn as a regular grid.** The geometry already places real stud
  meshes; a texture grid of them will not line up and will read as a second,
  wrong set.
- **Anything finer than ~8 texels.** It will not survive a 12 px lame.
- **A directional pattern that is not horizontal.** Diagonal brushing will skew
  visibly as it wraps the cylinder the lames are cut from.

## How to check it is right

Three steps, in this order. The third is the one that matters.

1. `probe_texture_stats.gd` for the numbers above.
2. Point `mockup_parts.armor_material()` at the new material.
3. **Re-run the rank shots and look at them.** `godot --audio-driver Dummy
   --path . --script res://tools/mockup_shots.gd -- <dir> rank` gives a
   line-up at squad distance, a head-on, a profile and three portraits. Eight
   rounds of this is how the geometry got from "wings" to pauldrons, and every
   one of those rounds was a thing that looked fine reasoned about and wrong
   photographed. A texture that passes the stats and looks like plastic in the
   line-up has failed.

## Open question for the human

The mock-ups paint every bolted-on piece with one `armor_material()`. If plate
steel lands, it is worth deciding whether the **kit** items — the armour
plating module, the harness, the grenade rack — take it too, or stay on the
present flat material. They are the same bought-hardware category and currently
look it. That is a wider change than this brief and should not be folded into
it without being asked for.
