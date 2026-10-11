# Brief — the Kite's airframe skin

Written 2026-10-10, off the lit in-game render of the finished Kite chassis
(`Character/characters/ai/kite.tscn`, photographed through
`tools/mockup_shots.gd -- <dir> kite`). The geometry is settled; the surface is
not. Every painted piece on the frame wears `robot_metal.tres` through
`FactionLivery`, the same material as a Bulwark's shin, and that is the problem
— see below.

Owner: **TERRAIN**. Status: **not started**.

**Deliverable:** two entries in `tools/make_textures.gd` — `kite_skin` with its
`_mask.png`, and `rotor_blade` — built the way `pauldron_plate` and the
`camo_fabric` pair were. No pixel of any bought pack gets read, sampled or
filtered; the licence is kept by drawing from nothing and copying only the
style, which is what that file already does.

---

## What it goes on

Eighteen painted pieces, measured off `tools/build_kite.gd`. The whole frame
measures **2.20 W × 1.62 H × 1.96 L** (`check_frame.gd`), and almost all of
that is air — the 2.20 is the rotor disc, not the aircraft.

| node | shape | size, metres |
|---|---|---|
| `Rig/Hull` | chamfered block, four CSG cuts (glacis −30°, tail +20°, two 30° flank bevels) | **0.70 × 0.46 × 0.90** uncut |
| `Rig/Mast` | cylinder | r 0.10 × 0.60 |
| `Rig/RotorUpper`, `Rig/RotorLower` | hub + 3 blades each, discs 60° apart | hub r 0.13 × 0.18; **blade 1.10 × 0.035 × 0.10** |
| `Rig/TailFin` | chamfered plate on edge | 0.48 × 0.42 × 0.05 |
| `Rig/Pylon` | box | 0.12 × 0.46 × 0.14 |
| `Rig/Turret/MountRing` | cylinder flange | r 0.20 × 0.072 |
| `Rig/Turret/Head/HeadBody` | the gun pod: Walker turret profile at 0.6, cheek and brow cut | **0.708 × 0.36 × 0.78** |
| `Rig/Turret/AmmoDrum` + `DrumBand` | cylinder, 10 sides, and a torus | r 0.14 × 0.34 |
| `Rig/Turret/GunPivot/Mantlet` | box | 0.30 × 0.216 × 0.156 |
| `Rig/Turret/GunPivot/GunPort` | torus aperture | 0.12 / 0.15 |

`Rig/Turret/Head/Eye` is deliberately off the livery list and keeps the
Walker's own `StandardMaterial3D`. Nothing in this brief touches it.

**There is no large flat surface anywhere on this frame.** That is the first
thing that separates it from `SHIELD_PLATE.md`: the biggest single face here is
the gun pod's 0.708 × 0.78 underside, less than a sixth of the Bulwark's
shield, and the piece that occupies most of the silhouette is a 1.10 × 0.10
bar. At the 20 m squad distance `PLATE_TEXTURE.md` measures against, a blade is
**82 px long and 7 px wide**. The hull is 52 px across.

## Why it cannot stay on the shared hull material

Three reasons, and none of them is the shield's reason.

**1. Ninety hull should not look like four hundred.** `KITE.md` §2 is explicit:
"It is made of paper — 90 hull — so it is a frame you commit and then protect,
not one you leave parked." In the render it is wearing the Bulwark's steel, and
a surface is the cheapest statement a frame makes about what it can take. A
flyer that looks armoured is a flyer the player will fly like one, once. The
Kite's skin should read as **formed sheet over a frame** — stressed skin, lap
joints, lightening holes, something you would put a rifle round through — and
not as rolled plate.

**2. It is seen from below, against the sky, and nothing else here is.**
This is the lighting case the pack has never had to survive. A ground frame is
lit from above and read off its top and flanks; the Kite cruises at altitude
and the surfaces the player actually looks at are the hull's underside, the gun
pod's bottom face, the ammo drum and the undersides of six blades — **every one
of them facing away from the sun**, against a background several stops
brighter. Two consequences that decide the whole texture:

- **The albedo is nearly all the player gets.** There is no highlight on a
  downward face. Whatever structure this texture has must be legible as flat
  albedo with no light on it, which is the `bearskin_fur` lesson in reverse:
  that family carries `_floor = 0.05` because "pure black leaves a cut-out
  silhouette with no interior", and `pauldron_plate` measures a minimum of
  0.000 and is cited in its own brief for exactly this. **This texture needs a
  floor.** Nothing on it should go below about 0.10 luminance, or at altitude
  the Kite is a black kite-shape with no aircraft in it.
- **And it must not clip at the top.** `faction_metal.gdshader` paints
  `albedo * faction_color * 2.0`. PLAYER is `Color(0.55, 0.90, 0.95)`, so the
  green and blue multipliers are 1.80 and 1.90 and **anything above albedo
  0.53 clips to white under the player's own livery.** `pauldron_plate` raised
  its ceiling to 0.72 and photographs as chrome; on a silhouette already backed
  by a bright sky, a clipped skin is indistinguishable from glare. **Keep
  `CEIL` at 0.46** on this family. It is one of the few places in the pack
  where the convention is not merely a convention.

**3. At 7 px a blade, the hull mottle is damage.** `robot_metal` carries the
same large blotchy noise everything else does. On a 52 px hull that is fine. On
a 7 px blade it lands two or three blobs across the chord and the blade comes
back looking chewed rather than thin — visible in the render, where the six
blades read as ragged bars rather than as a disc. `PLATE_TEXTURE.md` already
set the rule ("nothing finer than ~8 texels at 256") for a 12 px lame; a blade
is narrower than the lame and needs its own answer, not a tighter version of
the hull's.

## What it should read as

**Light aircraft, maintained, flown hard, and thin.** Not derelict, not
armoured. The nearest thing in the pack's vocabulary is the opposite of
`metal_rusty_*` and also the opposite of `shield_plate`: where the shield is
rolled plate that has been hit, this is **pressed skin that has been
handled** — fuel and exhaust staining, scuffing where a crew would grab it,
and panel joints that say the thing is assembled from sheet rather than carved
from a billet.

In rough priority:

1. **Panel lines and lapped seams at 15–30 cm.** Hard one-pixel lines, which is
   the pack's rule, laid out as overlapping skin panels rather than as a grid.
   This is the single detail that will say "aircraft". Big enough to survive at
   a 52 px hull — call it four or five divisions across the tile and no more.
2. **Flush rivet runs along the seams.** Not a field of rivets: lines of them
   following the joints. The geometry places no stud meshes on this frame, so
   unlike the pauldrons there is no second, wrong set to conflict with.
3. **A pair of lightening holes or an inspection panel.** One strong
   structural idea in the tile, the way `_epaulette` carries one. It is the
   cheapest way to say "there is a frame under this skin and the skin is thin".
4. **Staining, aft and downward.** Soot streaking behind the mast, a dark
   smear running back from the pod. Darkening only — the `_grime` helper is
   already the right tool and already darkens rather than lightens.
5. **No rust, no impact damage.** Both belong to other briefs. A Kite that has
   been hit is a Kite that is already on the ground.

### The second entry: `rotor_blade`

A separate texture, because a blade is the one piece on the frame whose
problem is its aspect ratio. 1.10 × 0.10 is **11:1**, and whatever is drawn on
a square tile arrives on it stretched eleven times in one axis.

What it wants is almost nothing: a **near-flat tone with a single hard
spanwise highlight line**, a darker root third and a lighter tip, and the leading
edge marked as a hard band along one side. No blobs, no mottle, nothing with a
scale. Six blades turning is a disc and a disc is a texture-free object; the
only job here is that the individual blade, when it is stopped on a parked or
downed frame, reads as a thin aerofoil and not as a dirty stick.

Use it on `RotorUpper/Blade0..2` and `RotorLower/Blade0..2`. Leave the hubs on
`kite_skin`.

## How much the faction repaints

More than the pauldrons, and for a different reason than the shield's.

A Kite is identified at range in the air, as a dark shape on a bright
background, and the only thing that will tell a player it is theirs is the
colour. So the **skin field wants to be inside the paint band and reasonably
bright inside it** — not because the faction needs to read across a field, but
because a backlit silhouette throws away everything that is not carried by the
albedo itself.

Use the `_mask.png` red channel with `derive_mask_from_albedo = false`, as the
epaulettes and pauldrons do. Green is 0.

- **Painted (mask 1):** the skin field, 65–75% of the tile. More than
  `pauldron_plate`'s 65%, because there is less of this frame to catch the eye
  in the first place.
- **Held out (mask 0):** panel seams and their shadow lines, rivet heads, the
  soot staining. Exhaust soot that turns cyan is not soot.
- **Nothing at all in the 0.4 band.** A chip keeps 40% of the paint weight on
  the pauldrons because bare metal beside saturated cyan reads pink; there is
  no bare metal on this texture to need it.

Numbers, checked with
`godot --headless --path . --script res://tools/probe_texture_stats.gd -- textures/PSX_Textures kite`:

- 256×256, RGB8, quantised to 32 levels through the same 4×4 ordered dither.
- mean luminance **0.22–0.27**. At the upper end of the pack, deliberately: a
  surface seen unlit needs the brightness in the albedo.
- **minimum luminance ≥ 0.10.** The unusual number, and the one that decides
  whether this works. Set `_floor` for the family the way `_bearskin` does.
- peak **≤ 0.46**. See the clipping arithmetic above.
- saturation **0.06–0.14**. Lower than the pauldrons. The player's cyan is the
  colour; a skin bringing its own will fight it and will go green.
- in band **65–75%** on the albedo.

## How to see it

```bash
godot --audio-driver Dummy --path . --script res://tools/mockup_shots.gd -- <out dir> kite
```

Needs a window — run **without** `--headless`, against
`Godot_v4.3-stable_win64_console.exe`.

That rig photographs the frame from above the horizon, which is the one angle
that does **not** test this texture. Judge it:

- **from below, against the sky.** This is the case the whole brief is about
  and the rig does not currently shoot it. If it means staging the Kite at
  altitude and putting the camera on the deck, do that — a swatch has told us
  the wrong thing about every surface in this project so far, and a
  three-quarter hero shot will tell us the wrong thing about this one.
- **in two faction colours.** PLAYER cyan is the one that clips.
- **parked, close**, for the blade.

## Hooking it up when it is done

Every piece listed above is in the Kite's `FactionLivery.pieces` and so takes
the shared hull material. Giving the skin its own surface means registering a
base material for it; `faction_livery.gd` already supports this
(`add_pieces_with`, and the `_bases` dictionary), which is the same mechanism
the hats use to keep wool looking like wool. `Campaign/cosmetics.gd`'s
`SURFACES` table is the precedent for how a surface is declared. `rotor_blade`
goes on the six blades through the same mechanism.

Shout if the geometry is wrong for the texture rather than working around it.
The frame is generated from `tools/build_kite.gd` and its proportions are not
precious — but note that **another lane is editing that file right now**, so
describe what you want by node name and not by coordinate.
