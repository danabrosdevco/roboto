# Brief — the Swarm shell, for the Broodcarrier

Written 2026-10-10, off the lit in-game render of the finished Broodcarrier
(`Character/characters/ai/brood.tscn`, photographed through
`tools/mockup_shots.gd -- <dir> brood`). The geometry is settled; the surface
is not. All fifty-five painted pieces wear `robot_metal.tres` through
`FactionLivery` — **the player's own steel, on the only frame in the game that
is supposed to come from somewhere else.**

Owner: **TERRAIN**. Status: **not started**.

**Deliverable:** three entries in `tools/make_textures.gd` — `swarm_shell` with
its `_mask.png`, `swarm_pod` with its `_mask.png`, and `swarm_pod_b` — built
the way `pauldron_plate` and the `camo_fabric` pair were. No pixel of any
bought pack gets read, sampled or filtered; the licence is kept by drawing from
nothing and copying only the style, which is what that file already does.

This is the most important of the three frame briefs written today, because it
is the only one that carries a **faction**. The Kite and the Vessel are the
player's; a better surface makes them read better. The Broodcarrier is the
first frame that has to say *a different thing built this*, and the surface is
the cheapest and strongest way to say it.

---

## The decision that is already made

**Swarm is machine, not organism. Do not draw chitin.**

This is settled and is recorded here so nobody re-litigates it halfway through
drawing. `BROODCARRIER.md` §1 ran a concept round with an explicitly organic
option — `concepts_c.gd:brood_c`, the "gravid abdomen", a bloated
three-segment body with pods barnacled over its skin. It was "the most Swarm of
the four and the most organic, and was the close second", and it lost, with the
reason written down: it "reads as a creature rather than a machine, which cuts
both ways."

A texture can overturn that. A carapace sheen, a hide grain, anything wet or
segmented or shell-like, and the frame becomes a creature regardless of what
shape it is — which would change what the faction *means* across every mission
it appears in, and that is above a texture brief's pay grade.

So the surface wanted is **scavenged, re-welded, corroded, assembled from
mismatched salvage**: a machine built by machines with no quality control.
Explicitly **not** chitin, carapace, hide, shell, scale, or anything with a wet
highlight.

The human has been told this is the recommendation and may yet overrule it.
The reasoning is above so it can be argued with.

## What it goes on

Fifty-five painted pieces, measured off `tools/build_brood.gd`. The frame
measures **2.94 W × 2.14 H × 3.32 L** (`check_frame.gd`).

| node | shape | size, metres |
|---|---|---|
| `Rig/LiftHoop` | torus, inner 1.02 / outer 1.28 | **2.56 across**, tube r 0.13 |
| `Rig/Rotor{A,B,C}` | three fans at 14°, 139°, 243°, each tilted differently | hub r 0.13 × 0.18; **blade 0.72 × 0.045 × 0.19** |
| `Rig/Strut{A,B,C}` | chords at 62°, 186°, 300° — angles matching nothing above | 0.1 × 0.1 × 1.15 |
| `Rig/CoreA` | sphere r 0.6, scaled (1.25, 0.82, 1.15) | **1.50 × 0.98 × 1.38** |
| `Rig/CoreB`, `CoreC` | two off-axis lobes | r 0.42 and r 0.34 |
| `Rig/BroodBay/Pod1..Pod9` | squashed eggs, scale (1, 1.2, 1), each with a `Band` torus and a `Stalk` | **radii 0.24, 0.25, 0.29, 0.29, 0.31, 0.32, 0.33, 0.38, 0.44** |
| `Pod1/Shell`, `Flap1`, `Flap2`, `Hatchling` | the one pod modelled open, with a hatchling half out | hemisphere r 0.38 |

`Rig/SensorCluster/Ocellus1..5` keep their own emissive material and are
deliberately off the livery list — five unequal amber eyes at r 0.080, 0.065,
0.055, 0.045 and 0.035 on the core's forward-lower flank. Nothing in this brief
touches them. They work; they are the only part of the frame that currently
says "not ours".

### Two facts about this geometry that decide the texture

**1. There is not one flat panel on the frame.** `build_brood.gd` says so
outright — "there is not one flat panel or one cut corner on this frame" — and
it is literally true: the fifty-five pieces are spheres, tori, cylinders and
a handful of thin boxes. **Everything `SHIELD_PLATE.md` and `VESSEL_PANELS.md`
ask for is wrong here.** Seams, bolt lines, border bands and panel divisions
all assume a plane; on a sphere's UVs they pinch at the poles and smear at the
equator, and on a torus they wrap into rings. What survives on a curved
low-poly primitive is **mottle, patch variation and tonal breakup**, which is
also exactly what "assembled from mismatched salvage" looks like. The geometry
and the fiction want the same texture, which is lucky and should be used.

**2. Nine pods, and the player has to be able to count them.** `BROODCARRIER.md`
§5: "The pods must visibly empty… a spawner whose remaining stock the player
cannot read is a spawner the player cannot make a decision about." In the
render **they do not read as nine.** Every pod is the same smooth egg in the
same colour, they overlap, and the cluster comes back as one lumpy mass. That
is a surface failure as much as a geometry one, and it is why this brief asks
for two pod textures rather than one: alternating `swarm_pod` and
`swarm_pod_b` across Pod1..Pod9 gives the cluster tonal separation at no
geometry cost, and mismatched pods is the faction's whole thesis anyway.

## Why it cannot stay on the shared hull material

**1. It is literally the player's factory.** `robot_metal.tres` is the Walker's
plate. The player's visual language is "chamfered plate off a production line",
and the Broodcarrier's brief (`BROODCARRIER.md` §1, `NEW_FRAMES.md` §8) is
"accreted, asymmetric, amber, nothing precision-made, and visibly *not* the
player's factory". The generator went to real trouble to honour that in the
shape — fans that count badly, struts at angles that match nothing, pods at
eight sizes, no eye — and then dressed all of it in StratCom steel. The shape
argues one thing and the surface argues the other.

**2. In amber it already reads as pottery.** This is the finding from the
render and it is the specific technical problem. `mockup_shots.gd` repaints
enemy frames, so the Broodcarrier was photographed through
`faction_livery.gd`'s `ENEMY` amber, `Color(0.70, 0.35, 0.02)` — and it comes
back looking like **a glazed terracotta urn**: smooth warm eggs, a smooth warm
bowl, a smooth warm rim. Nothing on it reads as metal at all.

`mockup_parts.gd` already knows why. Its `rust_material()` carries the comment:

> RUST IS THE MINORITY, not the base coat — a ramp that spends most of its
> range on orange comes out looking like varnished wood

That is hard-won prior art and it is directly this brief's problem, arriving by
a different route. There the orange came from the ramp; here it comes from the
faction paint, and the shader multiplies so there is no escaping it. The lesson
transfers exactly: **cite that comment, do not rediscover it.** Its ramp is
also a good model for the proportion — of five stops, two dark steels, one mid
grey, and only the top two warm.

**3. The arithmetic says the texture must bring no warmth at all.**
`Character/faction_metal.gdshader` paints `albedo * faction_color * 2.0`, a
multiply. `hud_palette.gd:63` holds the colour already:

```gdscript
const FAC_SWARM := Color(0.91, 0.63, 0.23)   # amber, lifted from #B35A05
```

Doubled, that is a per-channel multiplier of **(1.82, 1.26, 0.46)**. So:

- **The blue channel is more than halved before anything else happens.** Any
  neutral grey painted Swarm comes out saturated orange on its own. The
  texture does not need to supply hue and must not try.
- **Red clips above albedo 0.549.** At `CEIL` 0.46 the brightest Swarm pixel is
  (0.837, 0.580, 0.212) — a strong orange with saturation 0.75, and still
  inside the gamut. Push the ceiling the way `pauldron_plate` did, to 0.72, and
  red goes to 1.31 and clips flat: a highlight that should read as worn metal
  becomes a hole of featureless orange. **Keep `CEIL` at 0.46 for this
  family.** It is not a convention here, it is the clipping point.
- **So corrosion must be carried by VALUE, not by hue.** Pitting, dark
  staining, light scale, patch-to-patch tonal steps. Saturation in the texture
  itself should be the lowest of anything in the pack — **0.04–0.10**, below
  `camo_fabric`'s 0.227 and below `epaulette_plain`'s 0.134. Whatever warmth is
  wanted, the faction already supplies more than enough of it.

## What it should read as

**A machine assembled out of other machines' parts, outdoors for a long time.**

In rough priority:

1. **Patchwork at 30–60 cm.** Large irregular regions of different tone, with
   *hard* boundaries — no soft gradients anywhere, which is the file's standing
   rule. Each patch is a different piece of salvage. This is the single idea
   the texture lives or dies on and it is the one that survives on a sphere.
2. **Weld beads along the patch boundaries.** Lumpy, uneven, not straight: a
   line of short overlapping blobs rather than a drawn line. A weld that is
   neat is a weld from a factory.
3. **Pitting and scale, as value.** Dark pits, lighter scale blooms, uneven in
   density — heavier in some patches than others, because the patches came from
   different places. This is where `rust_material()`'s proportion goes: mostly
   steel, oxide in the pits, never the base coat.
4. **Drip and run staining downward.** Swarm hangs in the air and everything
   on it runs the same way. `_grime` already darkens rather than lightens and
   is the right tool.
5. **One or two fragments of somebody else's marking** — a part number, a
   stencil edge, half a stripe, cut off by a patch boundary. Scavenged means
   the parts had a previous owner. One strong idea per texture, as `_epaulette`
   does, and nothing legible: a readable word turns this into a joke.

### What it must not have

- **Chitin, carapace, hide, scale, segmentation, any wet highlight.** See the
  decision above. If a specular-looking highlight is needed anywhere it should
  read as *bare metal*, hard-edged, and it should be small.
- **Panel seams, bolt grids, border bands.** The plate vocabulary. It is wrong
  for this faction and wrong for these primitives.
- **Rust as the base coat.** The `rust_material()` comment, and the arithmetic
  above twice over.
- **Symmetry or regular pitch in anything.** Nothing on this frame is
  precision-made; a texture with a visible period undoes six careful decisions
  in the generator.

### The three entries

| name | what it is | where it goes |
|---|---|---|
| `swarm_shell` | the carrier's own structure: heaviest patchwork, most welds, the dirtiest | `CoreA/B/C`, `LiftHoop`, `Strut{A,B,C}`, the rotor hubs and blades |
| `swarm_pod` | a pod: smoother, fewer welds, more scale and staining — a different batch from the thing carrying it | `Pod1,3,5,7,9` shells, bands and stalks |
| `swarm_pod_b` | the same pod, a tone lighter and with its patches in different places | `Pod2,4,6,8` |

Keep `swarm_pod` and `swarm_pod_b` **deliberately unregistered to each other** —
different patch layouts, not the same layout damaged. That is the opposite of
the `pauldron_plate` / `pauldron_plate_worn` and `shield_plate` /
`shield_plate_scarred` relationship, and the reason is the whole faction: those
pairs are the same object at two ages; these are two objects that were never
the same. Alternating them across the cluster is what will let a player count
nine pods instead of seeing one mass.

## How much the faction repaints

**Most of it, but not the salvage.** Swarm's amber is the faction identity on a
frame with no other identifying feature — it has no eye, no turret and no
chamfered head — so the paint has to land. Use the `_mask.png` red channel with
`derive_mask_from_albedo = false`, as the epaulettes and pauldrons do. Green is
0: the ocelli already carry the frame's only emission, from their own material.

- **Painted (mask 1):** the patch fields, **60–70%** of the tile.
- **Held out (mask 0):** weld beads, the deepest pits, and **one or two whole
  patches per tile.** That last one is the detail that will make this work. A
  machine assembled from salvage has pieces that were never repainted, and a
  shell that is mostly Swarm amber with two grey panels in it reads as
  *accreted* in a way that nothing else on the frame can say. It is also the
  structural equivalent of the shield brief's unpainted scars, arrived at from
  the opposite direction.
- **No 0.4 partial-paint value.** The pauldrons chip to 40% because bare metal
  beside saturated cyan reads pink by contrast; a held-out patch here is meant
  to read as a different piece of metal, which is the effect, not the artefact.

Numbers, checked with
`godot --headless --path . --script res://tools/probe_texture_stats.gd -- textures/PSX_Textures swarm`:

- 256×256, RGB8, quantised to 32 levels through the same 4×4 ordered dither.
- mean luminance **0.18–0.23**. At the pack's own 0.20, not above it: the
  faction paint supplies the lift.
- peak **≤ 0.46**. See the clipping arithmetic. This is the number most likely
  to be broken by someone reaching for a metallic highlight.
- **saturation 0.04–0.10.** The lowest in the pack, on purpose.
- in band **60–70%** on the albedo, with mask coverage 60–70% to match.
- `swarm_pod_b` about **0.03 lighter in mean** than `swarm_pod`. Enough to
  separate the pods in a cluster, not enough to read as two factions.

## One thing to settle before this ships

**`faction_livery.gd` has no SWARM colour.** Its `COLORS` dictionary
(`faction_livery.gd:23`) holds PLAYER, ALLIED, ENEMY and NEUTRAL, and
`_material_for` falls back to `COLORS[NEUTRAL]`, bare grey. `hud_palette.gd`
has `FAC_SWARM` written and waiting, but the HUD colour and the livery colour
are two different tables and **nothing makes them agree.**

So today the Broodcarrier paints grey, and the render in this brief is it
wearing `ENEMY` amber `Color(0.70, 0.35, 0.02)` — which is more saturated than
`FAC_SWARM` (0.97 against 0.75) and therefore a slightly harsher test than the
real thing will be. That is fine for judging the texture.

But when `Enums.Factions.SWARM` is appended, `faction_livery.gd` needs a
`COLORS` entry and it must be the same `Color(0.91, 0.63, 0.23)`, or the blip
on the minimap and the robot under it will be two different ambers. That is not
this brief's work — `ENEMY_FACTIONS.md` owns the append and names the three
COLORS entries as part of it — but the texture is being drawn against a number,
and the number has to be the one that ships.

## How to see it

```bash
godot --audio-driver Dummy --path . --script res://tools/mockup_shots.gd -- <out dir> brood
```

Needs a window — run **without** `--headless`, against
`Godot_v4.3-stable_win64_console.exe`. That rig repaints enemy frames
automatically, so the shot comes back in amber rather than grey.

Judge it:

- **at 20 m, in amber**, and ask the one question that matters: *can you count
  the pods?* If the cluster is still one mass, the two pod entries are not
  differentiated enough.
- **beside a Walker or a Bulwark in player cyan.** The whole point is that the
  two frames look like they came out of different places. A swatch cannot tell
  you that and has told us the wrong thing about every surface in this project
  so far.
- **against the sky.** It is a flyer; the same caution `KITE_SKIN.md` makes
  applies, though less sharply — this frame is three times the Kite's mass and
  is meant to be looked up at as a problem rather than tracked as a target.

## Hooking it up when it is done

All fifty-five pieces are in the Broodcarrier's `FactionLivery.pieces`, in a
flat leaves-only list the generator collects as it builds (see its livery note
— listing `Rig` instead would recurse and paint the ocelli). Giving these three
their own surfaces means registering base materials; `faction_livery.gd`
already supports it (`add_pieces_with`, and the `_bases` dictionary), which is
the same mechanism the hats use to keep wool looking like wool, and
`Campaign/cosmetics.gd`'s `SURFACES` table is the precedent for how a surface
is declared. The per-pod split is three `add_pieces_with` calls, not a change
to the scene.

**Out of scope, noted so nobody folds it in:** the human also said the
Broodcarrier "probably needs animation later". The fans and the pods are
already built as individually named nodes for exactly that — `Rotor{A,B,C}`
spin about one node each, and `BroodBay/Pod1..Pod9` are ordered lowest-first so
a spawn script empties the bay downward. That is a script job and belongs with
the spawn loop, which `BROODCARRIER.md` §6 gates behind `are_hostile` becoming
a table.
