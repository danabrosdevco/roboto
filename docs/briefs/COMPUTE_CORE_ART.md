# Brief — the compute core, built properly

Written 2026-10-14 by GAMEPLAY, off three rounds of concepts and two rejected
builds. The direction is settled; the geometry is not.

Owner: **TERRAIN**. Status: **not started**.

**Deliverable:** `maps/blocks/compute/compute_core{_small,,_large}.map` and the
scenes FuncGodot writes from them — replacing the shipped trio, which is one
form scaled three ways.

---

## 1. What a core is, which is the part two builds got wrong

> it's a connectivity feature that allows the player to take control of an area
> and its resources/compute so it should feel like that

**A core is a relay, not a server cupboard.** It holds a territory; it does not
sit in one. Both rejected builds drew storage — racks, bays, cabinets — and
both read as architecture rather than as a device. The thing to draw is what
*connects*: cable trunks running into the earth, an uplink, junctions, lines
slung out to the ground. Taking it should feel like taking the area's wiring.

The kit already has that vocabulary and nothing had used it. Look at all of
these before drawing: `compute_cable_run`, `compute_satellite_dish`,
`compute_obelisk`, `compute_monolith`, `compute_network_cabinet`,
`compute_transformer`.

## 2. The direction, in the human's words

> i think having interlaced color / non-color is good. i also think thin is
> better. it should look metal, not concrete.

Three rules, all load-bearing:

**Interlaced.** Horizontal bands up the mast — metal, faction colour, metal,
lit slot, metal. Not panels, not zones: bands.

**Thin.** The shipped core is 22 brushes and reads as equipment because its
members are slim. The rejected build was chunky and read as a facade.
**Model nothing vertical on the mast.** A grid needs two directions; give it
one. Masts in the accepted study were 0.90 / 1.30 / 1.95 m across.

**Metal.** Not concrete. See section 5.

## 3. The reference

`docs/concepts/archive/CORE_LOOK3.md` and the fifteen lit renders beside it
(`docs/concepts/core_l3_*.png`) are the study this brief comes from. Five
variants on one skeleton:

| | its answer to *connectivity* |
|---|---|
| **TRUNK** | four cable bundles from the mast foot into the earth through painted glands |
| **UPLINK** | a dish on a braced boom with a lit feed horn, and a ground feeder |
| **PATCH** | the interlace slots become shelves, jumpers looping between them |
| **ANCHOR** | tie-rods raking from the lowest band to ground bollards |
| **RELAY** | cross-arms at alternating bearings, lines slung to deck glands |

`tools/build_core_look3.gd` builds all fifteen from primitives. **It is a
study, not a source** — the real article is brush geometry and it is yours.
Read it for proportions and for the comments, which record what failed.

**The human has not yet chosen a variant.** Build the direction; if one is
picked before you start, build that. RELAY answers the brief most directly and
is legible in silhouette from any bearing; UPLINK is the cleanest object and
the only one nameable at four hundred metres, but a dish says *reports out*
rather than *takes an area's compute*.

## 4. The interlacing, with numbers

A constant band pitch is what makes size legible, and it is the cue three
rounds went looking for and did not find:

| | small | medium | large |
|---|---|---|---|
| height | **4.20** | **7.00** | **12.40** |
| painted rings | 2 | 4 | 8 |
| slots at 0.62 m pitch | 4 | 8 | 17 |

**More bands is a bigger machine, for free.** Hold the painted run near
**17–18% of the mast** at every size. The pitch is the dial; 17 slots on the
12.4 m core may read as a ladder rather than a machine, and that is the first
thing to judge in-engine.

## 5. Materials

| | texture | why |
|---|---|---|
| mast, flare, corbel | **`metal_wall_3`** | dark navy ribbed. Amber is warm, navy is near its complement, so bands read at range — on the brown sheets amber sits on amber and the mechanism dies. It is also the sheet the paint is on, so painted and bare bands are **one material in two colours**, which is what "interlaced colour / non-colour" literally asks for. Far from FAC_ARGUS tyrian. |
| decks, fittings, pipework | **`metal_floor_1`** | riveted plate, a value lighter, so gear separates from the stem |
| gratings, vents, dish face | **`grate_perf`** | reads as breathing, at a grain fine enough to stay a texture |
| the lit slots | **`glitch_tx_1`** | see section 7 |

**No concrete anywhere.** The rejected build had its shaft on `concrete_tx_5`,
which is a transformer yard. **And not `metal_floor_3`** — it is a rack grille
and it tiled into a facade of windows.

## 6. The hard contracts

**The cap is 2.60 m across at every size, and clear.** The TICK drone
(`Character/characters/ai/tick.tscn`, built and approved) lands on it and
clamps four barbed legs 0.37 m outside its edge. That constancy is why the
chosen concept won: one clamp is correct on a 4.2 m core and a 12.4 m one
alike, and nothing is re-solved per size. **Put nothing on the cap.**

**Heights exactly 4.20 / 7.00 / 12.40.**

**Footprints 3.28 / 4.43 / 6.30**, matching the study. Any level that swaps a
core needs a navmesh rebake; holding these costs no *extra* one.

**A console face on −Z** a robot can stand at and press. Screen at y 1.55 —
the player's eye — kick rail 1.02, brow 1.92. Note the study made the console
a **pedestal rather than a recess**: a 0.49 m bay cut into a 0.90 m mast
severs the stem.

**A latent fault in the wrapper, worth fixing while you are here.**
`compute_core_point*.tscn`'s header says collision stops the player "half a
metre short". Measured: the capsule radius is **0.25**, and `InteractRaycast`
hangs **0.261 m forward of the camera** — so a `reach_size` set exactly to the
footprint puts the ray origin **11 mm inside the box**, on the wrong side of
the rule that comment states. Set `reach_size` to **footprint − 0.6**.

## 7. Owner colour and the pulse — read this before cutting brushes

A core is a capture objective and **who holds it must be readable across a
map**. `Env/world_objects/core_signal.gd` fakes that today with a procedural
collar and band, and its own header says the real art should replace it
without touching the state machine. This is that art.

**The structural problem: the shipped core is one merged mesh.** Everything is
`worldspawn`, so it bakes to a single `MeshInstance3D` and nothing can be
recoloured. The fix is already in the kit —

**`func_detail_illusionary` gives a brush group its own `Node3D` and its own
`MeshInstance3D`.** `compute_cable_run.map` already uses it. So:

- **the painted bands** go in their own entity, grouped under a node named
  **`Paint`**;
- **each lit slot gets its OWN entity**, grouped under **`Lit`** — one per
  band, not one for all of them, because the pulse travels and needs them
  addressable separately;
- everything else stays `worldspawn` and carries the collision.

**The contract on those materials, learned the hard way:**

1. **Both lists set `emission` as well as `albedo_color`.** Anything that sets
   albedo alone repaints the surface and leaves it glowing in the previous
   owner's colour.
2. **Every material is `resource_local_to_scene = true`.** A sub-resource in a
   `.tscn` is one object shared by every instantiation — two cores in a level
   would share materials and the second capture would repaint the first. It
   has never fired only because no level holds two.
3. **`glitch_tx_1` goes on emission as well as albedo, with
   `EMISSION_OP_ADD`.** The faction colour is then a floor the data grain sits
   on: hue owned by the faction, grain by the texture. **MULTIPLY recolours
   the glow** — an amber core emits yellow-green speckle and an Argus core is
   unreadable.
4. **Emission energy multiplies into clipping, not brightness.**
   `FAC_ADVERSARY` is `Color(0.91, 0.63, 0.23)` — red is already at 0.91.
   1.3 photographed pale, with the amber going toward white. The study settled
   at **0.45 on the paint** and lets the lit slots carry the glow.

**The pulse already exists.** `maps/blocks/compute/core_pulse.gd` runs a band
of light up the mast at 6 m/s off one looping tween per height bucket, built
in `_ready`, with nothing executing per frame. Attach it to the core's root.
It wants the `Lit` children separable by height and reads their baked energy
as the rest level — **do not stamp `emission_energy_multiplier` on them**, it
animates exactly that float.

It also carries a diagnostic: `CORE_PHASE=0.35` freezes the cycle so a still
can prove a moving thing.

## 8. What is still open, and belongs to the human

- **Which variant**, or which parts of which.
- **Band density** — 17 slots on the 12.4 m core: machine, or ladder.
- **Whether a dish is the right fiction**, if UPLINK is taken.

## 9. How this will be judged

**Lit, in a level. Not line art.** Every fault across three rounds was found by
looking at a lit render and none would have shown in outline — flat plastic
tape, an orange rectangle on the floor, a green lamp with a machine inside it,
smeared UVs, a reveal invisible under its own lip. Line art hid all of it.

```
godot --audio-driver Dummy --path . --script res://tools/mockup_shots.gd -- <dir> props
```

Add the scenes to that file's `PROPS` map. It needs a window, so no
`--headless`.

## 10. The two failures, so they are not repeated

**The first build was a server cupboard.** Rack bays, grille, shelf courses,
corner posts. It read as a building because a grid has two directions and it
had both. Thin, and nothing vertical.

**The second drowned in colour.** Nineteen painted pieces, every lit strip
emissive, and no grey left for any of it to read against. The note was "lots of
places for faction colour", and the right reading of that is **legible places,
not area**. 17% of the mast, interlaced, on navy.
