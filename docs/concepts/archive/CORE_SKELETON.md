# COMPUTE CORE — THE SKELETON, BUILT. NO HEAD.

> **SUPERSEDED, 2026-10-14. The human saw this lit and rejected the direction:
> "i don't like the bands … more asymmetrical / more imposing / wider … it
> doesn't need a terminal." `docs/concepts/archive/CORE_RELAY.md` is what replaced it
> and `tools/build_core_relay.gd` is what builds the shipped trio now. THIS
> DOCUMENT IS KEPT AS EVIDENCE, not as a description of anything on disk: the
> renders it cites (`core_skel_*.png`) are kept too, and
> `tools/build_core_skeleton.gd` still builds this geometry if it is ever
> wanted back. Everything below describes the rejected round.**

Round one of `docs/briefs/COMPUTE_CORE_ART.md`, which governs. 2026-10-14 ·
**status: built, shipped, photographed lit. The variant is still open and so is
band density.**

The human was offered RELAY / UPLINK / TRUNK off `CORE_LOOK3.md` and chose
**"build the skeleton, decide after"**. So this is the shared body at all three
sizes and nothing else: deck, mast, interlacing, flare, corbel, cap, console
pedestal. **No cross-arms, no dish, no tie-rods, no cable trunks.**

| | file |
|---|---|
| geometry | `tools/build_core_skeleton.gd` → `maps/blocks/compute/compute_core{_small,,_large}.map` |
| scenes | `tools/block_prefabs.gd`, then **`tools/core_skeleton_dress.gd`** |
| renders | `tools/shoot_core_skeleton.gd -- <dir>` (needs a window) |

**The dress pass is not optional.** FuncGodot assigns materials by texture
name, so a freshly built prefab is navy metal with four grey panels on it. The
dress pass is what makes `Paint` and `Lit`. It is re-appliable, because a
`block_prefabs` rebuild throws it away.

---

## 1. The answer to the question that was deferred

> **Do 17 slots on the 12.4 m core read as a machine, or as a ladder?**

**A ladder.** Not marginally. Look at `core_skel_row.png` — the three cores on
one ground plane, one camera, true common scale — and at
`core_skel_large_eye.png`, which is the 12.4 m core from a standing player's
eye at about eighteen metres.

Eight painted rings and seven lit reveals over 10.6 m at a constant 0.62 m
pitch is a **rung repeat**, and a rung repeat on a plain vertical stem is the
most legible ladder signal there is. It is made worse by the bands standing
proud: each one presents a horizontal top face that catches the sun, so the
read is specifically *rungs* or *stacked trays*, not *stripes*. The object I
photographed at 12.4 m is a chimney with a fire escape on it.

**The medium core is where the idea works.** Four rings over 5.2 m leaves
enough bare metal between them that they read as banding on a machine rather
than as treads. `core_skel_med_eye.png`.

**It is one constant, and I have photographed the alternative rather than
describing it.** `core_skel_large_eye_ALT_1m_pitch.png` and
`core_skel_row_ALT_1m_pitch.png` are the same skeleton at `BAND_PITCH` 1.0 m
with `BAND_U` thickened to 0.375 m to hold the 17–18% colour share — so **five
thicker rings instead of eight thin ones, at the same painted area.** The
ladder reading is gone and the size cue survives: five rings against the
medium's three still says bigger machine. **I have not made that change.** The
shipped files are at the brief's 0.62 m pitch and the two constants are
`PITCH_U` and `BAND_U` in `tools/build_core_skeleton.gd`.

### The size cue itself works

In `core_skel_row.png` (large left, medium centre, small right — the camera
looks up +Z so +X is to the left) the three are obviously three different
machines, from band count alone, with no second cue. That half of the look is
sound at every density I shot.

---

## 2. What else the lit renders say, that no outline would have

**The small core is a mushroom.** `core_skel_small_eye.png`. The cap is 2.63 m
across and constant by contract; the whole object is 4.19 m tall with a 3.25 m
deck, so the head is wider than the mast is tall and the console cabinet is
nearly as tall as the stem. It reads as a bird table or a parking meter. This
is a **direct consequence of the constant cap**, which is the contract the
chosen concept won on and which I have not touched. If the small core has to
look like a smaller version of the same machine rather than a different object,
something has to give, and it is not mine to give.

**The lit slots do not read at rest.** At `LIT_GLOW` 0.40 the slot emission
works out at almost exactly the painted bands' 0.45 — so at rest the reveals
are the same brightness as the paint, in a recess, at a fifth of the area, and
on a still they are simply absent. I widened the aperture from 0.125 m to
0.1875 m after the first render and they are now findable, not conspicuous.
**They come alive in the pulse frames** (`core_skel_large_pulse.png` — two
reveals at the crest, clearly brighter than the bands) which is the designed
behaviour. The question for you: should a core at rest have visible light in
it, or should light only ever mean *the pulse is passing*? Raising `LIT_GLOW`
is one number, but `core_pulse.gd` multiplies it by 2.4 at the crest and the
brief's own measurement says the amber goes white above about 0.96.

**The console plate is the brightest thing on the model, at every size.**
`CONSOLE_GLOW` is 0.85 and it is a flat amber rectangle roughly 0.9 × 0.53 m.
On the small core it is most of the front elevation. It reads as a backlit
poster rather than a screen. The study shipped the same value; I have kept it
so the comparison is honest.

**The painted bands are flat tape, not painted metal — still.** This is the
reversal `CORE_LOOK3.md` §"One deliberate reversal" flagged, at the value it
settled on. 0.45 of untextured amber emission across a 0.22 m face swamps
`metal_wall_3`'s ribs just as 0.95 did; the ribs survive beautifully on the
*bare* segments, which is where you can see the sheet working. Lowering
`PAINT_GLOW` further, or giving the paint an emission texture, are the two
levers and both are yours.

**One fault I did fix.** The study's own renders have the deck grating as a
field of enormous polka dots — `grate_perf` at one tile per 2 m puts a single
perforation at about 15 cm. See the deck in `core_l3_trunk_med.png`. It is at
one tile per 0.5 m here and the deck now reads as grating.

**The deck is still a lot of quiet ground**, which is `CORE_LOOK3.md` §6's own
finding and is the thing a variant's gear is supposed to fill.

---

## 3. The entity structure, which is the actual deliverable

The shipped core was **one merged `worldspawn` mesh**, so nothing on it could
be recoloured — which is why `Env/world_objects/core_signal.gd` still fakes
owner colour with a procedural collar. That is now fixed in the geometry:

```
ComputeCoreLarge                      (FuncGodotMap)
  entity_0_worldspawn                 solids + all collision (23 brushes)
  entity_1_func_detail_illusionary    trim, mesh only
  Signal                              core_pulse.gd
    Paint   Band1 … Band9             one entity, one mesh, one material each
    Lit     Slot1 … Slot9             one per band, addressable by height
            ConsolePlate              no pulse_y: constant on purpose
```

**`Signal` is a deviation and it is forced.** The study's cores were plain
`Node3D` roots carrying `core_pulse.gd`. A FuncGodot prefab's root carries
`func_godot_map.gd` — which is what lets a human select it and press Build —
and a node holds one script, so the pulse goes on a child and `Paint`/`Lit` go
under that child because `core_pulse.gd` resolves `^"Lit"` relative to itself.
An owner-colour pass written later should use `find_child()`, not a fixed path.

All four material rules hold, verified in the saved `.tscn`: `emission` set
alongside `albedo_color` on both lists, `resource_local_to_scene = true` on
every material, the screen texture on emission with `EMISSION_OP_ADD` (which is
Godot's default and therefore does not appear in the file), and 0.45 on the
paint. Nothing writes `emission_energy_multiplier` on a `Lit` material except
the dress pass, once, as the rest level.

**Rule 2 is not latent.** The brief says material sharing "has never fired only
because no level holds two [cores]". Measured: **ten of the ten levels that
hold a core hold at least three**, and `causeway_ops` holds eight. It would
have fired on the first capture.

### The mast is a stack, so nothing overlaps

A band around a column is four plates or a segment of the column; there is no
third option that does not interpenetrate. The mast is built as bare segments
with the band and reveal heights left out, and each band or reveal fills its
own slot as one brush — 31 brushes on the large core where four-plate rings
would be 116. `probe_map_overlap` reports **0 pairs** on all three.

**The cost, stated:** those slots are `func_detail_illusionary`, so the mast's
collision has a 0.22 m gap at each painted band and a 0.19 m gap at each
reveal, each shielded by a band standing proud of it. The study's own collision
was a handful of boxes and had the same gaps. If a core must stop a bullet at
every height, `PAINT_CLASS` and `LIT_CLASS` become `"func_detail"` — one
concave shape per band.

---

## 4. Measurements, and the contract that could not survive

Brushes snap to **1/32 m**. 4.20 m is 134.4 units and 12.40 m is 396.8, so
neither height is expressible as brush geometry at all; 3.28 m is 104.96 units
and a cap centred on an axis needs an even count, so the footprints move too.
The study was primitives, which have no grid.

| | contract | built | residual |
|---|---|---|---|
| height | 4.20 / 7.00 / 12.40 | **4.19 / 7.00 / 12.41** | −13 / 0 / +6 mm |
| footprint | 3.28 / 4.43 / 6.30 | **3.25 / 4.44 / 6.31** | −30 / +8 / +13 mm |
| mast across | 0.90 / 1.30 / 1.95 | **0.88 / 1.31 / 1.94** | −25 / +13 / −13 mm |
| cap across | 2.60 | **2.63** | +25 mm |
| slots / rings | 4 / 8 / 17 · 2 / 4 / 8 | **exact** | — |
| painted share | 17–18% | **18.2 / 16.8 / 16.5%** | — |

Everything is inside 3 cm. Cost: **61 brushes and 23 collision brushes** on the
large core (the shipped one was 25 and 25), **20 meshes** against the study's
78–112.

### Against what actually shipped

The old trio was `core_column()` scaled three ways and measured
**1.88 / 3.38 / 5.18 m square at 3.88 / 6.66 / 12.06 m tall.** The brief's
claim that holding the study's numbers "costs no *extra* navmesh rebake" is
true relative to F2 and **not true relative to what shipped**: every deck grew
by **1.37 / 1.06 / 1.12 m a side**, and a core's deck is a 0.53 m sheer step.

**A rebake is owed on ten levels, 42 instances:**

| level | cores |
|---|---|
| `maps/gameplay/causeway_ops.tscn` | 8 (6 small, 1 med, 1 large) |
| `maps/gameplay/georgetown_ops.tscn` | 5 |
| `maps/pittsburgh_level.tscn` | 5 small |
| `maps/mutaha_wip_level.tscn` | 5 small |
| `maps/appendix/mutaha_level.tscn` | 4 small |
| `maps/valley_basin_level.tscn` | 4 small |
| `maps/gameplay/salient_ops.tscn` | 4 |
| `maps/coastal-road_level.tscn` | 3 |
| `maps/gameplay/polaris_ops.tscn` | 3 |
| `maps/hillfort_level.tscn` | 1 |

**Check placement as well as the bake.** A small core's deck is 1.37 m wider a
side than the one it replaces, and five of them sit in Pittsburgh.

---

## 5. Two checks the round was asked for

**The shipped `.map` files were byte-reproducible** from
`tools/block_industrial.gd` (`--force compute_core compute_core_small
compute_core_large` → `cmp` identical on all three), so nothing a human had
touched was overwritten. The originals were copied aside first anyway.

**`reach_size` is fixed.** The wrapper comments claimed collision stops the
player "half a metre short"; the capsule radius is 0.25 and `InteractRaycast`
sits 0.261 m forward of the camera, so a `reach_size` equal to the footprint
puts the ray *origin* 11 mm inside the box. Now footprint − 0.6:
**2.65 / 3.84 / 5.71**, and the comments say why.

---

## 6. The material override, for GAMEPLAY

**Section 5's `glitch_tx_1` is replaced by `glitch_tx_neutral`** on the Lit
slots, on measurement. `glitch_tx_1` is saturation **0.771**, and a core has to
carry four faction colours — amber FAC_ADVERSARY, blue SIGNAL, green FAC_HOME,
tyrian FAC_ARGUS. A 0.77-saturation grain cannot carry purple and amber both:
adding a heavily hued grain to a faction colour muddies it even under
`EMISSION_OP_ADD`, which is section 7's own MULTIPLY failure arriving by a
different route. `glitch_tx_neutral` is the same image with the hue stripped
and exposure kept — saturation 0.771 → 0.109, mean 0.183 → 0.176, peak 0.561
unchanged — so the faction colour owns the hue and the texture owns the
sparkle. Because the mean is within half a percent, the study's energies carry
over untouched. **Section 5 needs amending.**

---

## 7. What is still the human's

- **Which variant**, or which parts of which. Nothing here prejudges it: the
  gear hangs off `_gear_<variant>()` beside `_console()` and nothing else in
  the file has to move.
- **Band density.** `core_skel_row.png` against `core_skel_row_ALT_1m_pitch.png`.
- **Whether a core at rest should have visible light in it**, or whether light
  should only ever mean the pulse is passing.
- **Whether the small core being mostly head is acceptable**, given the cap is
  constant by contract.
- **`PAINT_GLOW` at 0.45.** The bands are still tape rather than painted metal.
