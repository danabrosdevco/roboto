# Brief — the Bulwark's tower shield

Written 2026-10-09 by GAMEPLAY, off the first lit renders of the new Bulwark
chassis (`Character/characters/ai/bulwark.tscn`). The geometry is settled; the
surface is not. The shield currently wears `robot_metal.tres` through
`FactionLivery` like every other panel on the frame, and that is exactly the
problem — see below.

Owner: **TERRAIN**. Status: **not started**.

**Deliverable:** two entries in `tools/make_textures.gd` — `shield_plate` and
`shield_plate_scarred` — each with its `_mask.png`, built the way
`pauldron_plate` and the `camo_fabric` pair were. No pixel of any bought pack
gets read, sampled or filtered; the licence is kept by drawing from nothing and
copying only the style, which is what that file already does.

---

## What it goes on

One piece, and it is the largest flat surface on any robot in the game.

| | |
|---|---|
| node | `Rig/Torso/ShoulderL/ElbowL/ShieldMount/Shield` |
| shape | box, **1.55 w × 2.20 h × 0.18 d** metres |
| cut | a vision slot, 0.64 × 0.13, through the upper third |
| boss | a hemisphere, r 0.20, on the outer face |
| orientation | vertical, carried on the forearm, facing front |

For scale: the Walker's whole hull is 1.5 × 0.9 × 1.75. **This one plate is
taller than a Walker's body and nearly as wide.** At 20 m it is roughly 120 px
across — an order of magnitude more screen than the pauldrons that
`PLATE_TEXTURE.md` was written for, and the first thing the eye lands on when
the frame walks into view.

## Why it cannot stay on the shared hull material

Three reasons, in order of how much they matter:

**1. It is the silhouette.** Everything else on this chassis reads as "robot".
The shield is what makes it a Bulwark, and right now it is the same steel as
the shin. A frame whose defining feature is indistinguishable from its leg has
no defining feature.

**2. Flat and huge is the worst case for a tiling texture.** The hull material
is fine on a 0.4 m greave where you never see more than a few texels of it.
Stretched over 1.55 × 2.20 of unbroken plane it tiles visibly, and any blob
larger than about 10 cm will read as a repeating pattern rather than as a
surface.

**3. This thing gets shot.** It is the only object in the game whose entire
purpose is to be hit — the chassis exists because suppression is measured along
a round's flight path, so everything aimed at the squad behind it passes close
to this plate. It should look like it.

## What it should read as

**Rolled plate, bolted up, and hit a lot.** Not rusted, not derelict: this is
maintained kit that is used hard and repaired. The distinction is the same one
`PLATE_TEXTURE.md` draws for the pauldrons, and for the same reason — the
`metal_rusty_*` family is right for a shelled bridge and wrong for a thing a
squad depends on this week.

Specifically wanted, in rough priority:

- **A horizontal grain.** Rolled steel is finished along its length, and a
  horizontal direction runs with the slot and against the frame's verticals.
- **Structure, not noise.** Something to break the plane up at the 20–40 cm
  scale: a seam or two where plates are joined, a border band, bolt lines down
  the edges. Big enough to survive at 12 px.
- **Impact marks.** Scuffs, dings, bright scrapes where paint has come off down
  to bare metal. These are what sell it and they are the point of the second
  variant.
- **Nothing finer than ~8 texels at 256.** Same rule as the pauldrons: fine
  noise is grey mush at distance, and this is seen at every distance.

### The two variants

| name | what it is | where it goes |
|---|---|---|
| `shield_plate` | issued condition — clean plate, seams, bolts, light wear | the stock chassis |
| `shield_plate_scarred` | the same plate after a campaign: deep gouges, a dented quadrant, paint stripped round the boss | a veteran / rank variant, matching how `camo_fabric_worn` and `pauldron_plate_worn` pair with their clean versions |

Keep the two **registered to each other** — same seams, same bolt positions —
so the scarred one reads as the same object damaged rather than a different
shield. That is what `pauldron_plate` / `pauldron_plate_worn` do.

## The one real decision: how much the faction repaints

`Character/faction_metal.gdshader` repaints by luminance band — centre 0.45,
width 0.425 as called, so **everything between 0.24 and 0.66 luminance takes
the faction colour** and everything outside keeps the texture's own value.
`make_textures.gd` already reports this percentage per texture; use it.

For this piece I want **more** of it painted than the pauldrons got, not less.
The shield is the frame's identity and its faction should be readable across a
field. Aim for the body of the plate inside the band and the marks outside it:

- plate body → **inside** the band, so it takes faction colour
- bolt heads, seam shadows, deep gouges → **below 0.24**, stay dark
- bright fresh scrapes, the stripped metal round the boss → **above 0.66**, stay
  bright

That last one is the detail that will make it work: a repainted shield with
unpainted scars reads instantly as "this has been hit", in any faction colour.

Watch the ceiling. `CEIL` in `make_textures.gd` is 0.46 and nothing generated
goes brighter, so the bright scrapes need to come from the *mask*, not from
pushing albedo up — otherwise this plate glows next to its own frame.
`pauldron_plate` currently overshoots its own brief here (peak 0.701 against a
0.46 ceiling) and photographs as chrome; please do not inherit that.

## How to see it

The chassis renders out of `tools/mockup_mech.gd` as line art, but the surface
question needs it lit:

```bash
godot --audio-driver Dummy --path . --script res://tools/mockup_shots.gd -- scratchpad/shield kit
```

Judge it **on the frame, at 20 m, in two different faction colours**, not as a
flat swatch. A swatch has told us the wrong thing about every surface in this
project so far.

## Hooking it up when it is done

The shield is listed in the Bulwark's `FactionLivery.pieces`, so it currently
takes the shared hull material. Giving it its own surface means registering a
base material for it — `faction_livery.gd` already supports this
(`add_pieces_with`, and the `_bases` dictionary), which is the same mechanism
the hats use to keep wool looking like wool. `Campaign/cosmetics.gd`'s
`SURFACES` table is the precedent for how a surface is declared.

Shout if the geometry is wrong for the texture rather than working around it —
the plate is generated from `tools/build_bulwark.gd` and its proportions are
not precious.
