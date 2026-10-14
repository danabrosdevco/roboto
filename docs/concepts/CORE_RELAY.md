# COMPUTE CORE — ROUND TWO. THE BANDS ARE GONE; IT IS A MACHINE NOW.

Round two of `docs/briefs/COMPUTE_CORE_ART.md`, which still governs the
CONTRACTS and whose VISUAL direction is overridden here by the human.
2026-10-14 · **status: built, shipped, photographed lit at three sizes.**

> "yeah i don't like the bands. can we do like a more asymmetrical structure
> that's more imposing / wider, looks like technology and is visually more
> interesting? it doesn't need a terminal."

So, gone and not to be reintroduced: **the interlaced horizontal bands** (the
whole language — the 1.0 m pitch alternative was shown too), **"thin, model
nothing vertical"**, and **the console pedestal**. Round one is
`docs/concepts/CORE_SKELETON.md` and its renders are kept beside this one as
`core_skel_*.png`; a rejected round is evidence.

| | file |
|---|---|
| geometry | `tools/build_core_relay.gd` → `maps/blocks/compute/compute_core{_small,,_large}.map` |
| scenes | `tools/block_prefabs.gd --only=<name> --force`, then **`tools/core_skeleton_dress.gd`** |
| renders | `tools/shoot_core_skeleton.gd -- docs/concepts` (needs a window) → `core_relay_*.png` |
| clearance | `tools/probe_core_clearance.gd`, and `CORE_FOOT=shipped\|r1` to compare eras |

**The dress pass is still not optional.** FuncGodot assigns materials by
texture name, so a fresh prefab is navy metal with grey patches on it. It read
this round's tags unchanged, because the entity structure was the one thing
round one got right.

---

## 1. What it is now

A **relay machine in the register of `compute_transformer`**, composed
asymmetrically. In map axes (map +X → Godot +Z; the player approaches from
map −X):

- **a bunded tray** on a sunk plinth, with a rim on the **+X and +Y sides
  only**. All four sides is a planter; two is a bund with a spill side, and
  the two it is missing are the two you walk in from.
- **a two-stage primary mass** in the +X/+Y corner, the upper stage inset on
  −X and −Y **only**, so the step is one-sided and the thing has a front and a
  back. Its crown is **canted**, falling toward −X.
- **a lower secondary mass** alongside on −X, hugging +Y, carrying a lying
  cylinder and the cable terminations.
- **a fin bank** on the −Y flank of the lower stage: one row, one direction,
  one pitch, four to six times finer than anything else on the model.
- **three cable terminations** — bushing, jumper, junction, vertical trunk,
  gland in the tray floor. This is the fiction GAMEPLAY's section 1 insists
  on: a core is a relay, and taking it is taking the area's wiring.
- **a cantilevered landing shelf** over the open −X/−Y quarter of the tray,
  on two raking struts, carrying the drone pad at its free end.

**Nothing is panelled.** The masses are plain boxes with large blank faces,
crossed by a shelf, a trunk or a vent. That is the whole defence against
section 10's trap — the first rejected build "read as a building because a
grid has two directions and it had both" — and going wider is exactly the move
that walks back toward it, so it is the thing to protect if the file is edited.

## 2. What the lit renders say, which is the only thing that counts

**`core_relay_row.png`** — three sizes, one ground plane, one camera, true
common scale.

**It is not a monument and not a cabinet.** At every size the silhouette is a
machine: a wide base, an off-centre mass, an overhang, a canted top. The
footprint being a RECTANGLE rather than a square does more work than it has any
right to — a square plan reads as architecture before anything is put on it.

**The small core is no longer a mushroom.** That was round one's clearest
fault: a constant 2.6 m cap on a 4.2 m stem, so the head was wider than the
mast was tall and the thing read as a bird table. The same constant pad now
sits **beside** the mass on a shelf at two thirds height with the crown going
on up past it, so it is neither the top of the object nor on its axis.
`core_relay_small_eye.png` and `core_relay_small_flank.png`: it reads as a
squat relay unit, which is what a small one should be. **The cap contract cost
nothing this time**, and that is a direct consequence of moving it off the
axis.

**The cantilever is the strongest thing on the model** and it is worth knowing
that before anything else is added. `core_relay_large_eye.png` — the overhang
and its two struts are what make the object read as DESIGNED rather than as
massing, from every bearing, at every size.

**The lit staircase works, and it took a photograph to find out.**
`core_relay_large_flank.png` is the shot: seven lit panels climbing diagonally
across the fin bank, and the pulse walks up and along the bank at once. The
first version put them on the mass face at the bottom of slots 0.19 m wide and
up to 1.06 m deep — hidden from anything more than ten degrees off the normal,
and the same flank shot showed **not one of the seven**. They are now three
units inboard of the fin tips and still between two fins, so they are light
coming out of a machine rather than a lamp stuck on the side of one.

**Amber is in four places, not spread over an area.** The first lit pass ran
the crown slot across the whole face — 2.2 × 3.4 m of emissive amber on the
large core — and it photographed as a backlit poster, which is the fault round
one's console plate was pulled for arriving somewhere new. At 42% of the face,
pushed to one edge, it still carries ownership at forty metres
(`core_relay_med_far.png` is the test) and is no longer the first thing the eye
lands on at six.

**What is still weak.** At 40 m the small core is findable rather than
conspicuous (`core_relay_small_far.png`) — 4.19 m of machine is simply small,
and the amber is a strip and a few marks. If a small core has to be visible
across a map, that is a signal-art question for `core_signal.gd`, not a
geometry one.

## 3. Measurements

| | small | med | large |
|---|---|---|---|
| height | **4.19** | **7.00** | **12.41** |
| footprint, map X × Y | **4.50 × 3.50** | **6.00 × 4.75** | **8.25 × 6.50** |
| …as Godot X × Z | 3.50 × 4.50 | 4.75 × 6.00 | 6.50 × 8.25 |
| pad | 2.625 sq | 2.625 sq | 2.625 sq |
| **dock_height** | **2.91** | **4.59** | **7.84** |
| brushes · collision | 53 · 9 | 55 · 9 | 59 · 9 |
| Paint · Lit entities | 5 · 10 | 5 · 11 | 5 · 13 |

Heights are exact to round one's, which is the size hierarchy the site tiers
were sized against. `probe_map_overlap`-style checking is built into the tool:
**0 overlapping brush pairs** on all three, checked as solids before the file
is written.

**Nine collision brushes at every size**, against round one's 11 / 15 / 23 and
the shipped trio's 25. Every fitting — fins, bushings, trunks, glands, kerbs,
lugs, struts, vent — is `func_detail_illusionary`, so it draws and does not
collide; they are thin plates in front of solid mass, so a bullet still stops.
Across the 42 instances the levels hold, that is about 700 collision shapes
saved against round one.

## 4. The contracts, and where they live

**The drone pad.** 2.625 m across at every size, clear, nothing above it —
guaranteed by construction rather than measured: the pad's +X edge is set from
the upper stage's −X face, so no part of the mass can ever overhang it. Kerbs
are on the two INBOARD edges only, because the TICK clamps four legs 0.37 m
outside the edge and the two it comes in over are left clean. The four landing
lugs are where they were.

**The interact volume.** Untouched and still required. `holdable_core.gd`
exports `interactible`; `compute_core_point*.tscn` wires
`interactibles = [NodePath("Terminal/Interactible")]` into a `DummyTerminal`
that already has `show_body = false`. **"Doesn't need a terminal" meant no
modelled console, and that is all it meant** — nothing on the model carried the
interaction before or now. The player presses the machine itself, from any
face, at standing height (`reach_height` 1.5).

**`reach_size` is footprint − 0.6 per axis, and is NO LONGER SQUARE:**
`(2.9, 3, 3.9)` / `(4.15, 3, 5.4)` / `(5.9, 3, 7.65)`. Godot Z is the long
one. Swapping the two axes puts the short reach on the approach face, where
the player actually stands. The 0.6 is round one's arithmetic, unchanged:
capsule radius 0.25, `InteractRaycast` 0.261 m forward of the camera, and no
hit registered for a ray that starts inside the volume.

**The pulse.** `core_pulse.gd` is untouched and the vertical path is intact,
asymmetric as the brief asked: **glands in the tray (0.66 m) → the lit
staircase up the fin bank → the shelf lip at the tip of the overhang → two
crown slots.** 10 / 11 / 13 lit pieces, every one carrying `pulse_y`, **none
constant** — the console plate was the only constant one and it is gone. Rest
energy is baked once by the dress pass and nothing else writes
`emission_energy_multiplier`.

**Materials.** `metal_wall_3` navy ribbed on the masses, `metal_floor_1` plate
on every fitting, `grate_perf` on the tray and the vent, `glitch_tx_neutral` on
the lit pieces with emission as well as albedo and `EMISSION_OP_ADD`. No
concrete, no `metal_floor_3`. Every material `resource_local_to_scene`.

## 5. The cost, measured rather than asserted

A navmesh rebake is owed on **ten levels, 42 instances** — it was already owed
after round one, and this makes it bigger. Against the trio that actually
shipped, a side grew by:

| | Godot Z (long) | Godot X (short) |
|---|---|---|
| small | +1.31 m | +0.81 m |
| med | +1.31 m | +0.69 m |
| large | +1.54 m | +0.66 m |

**And placement, which nothing in this project would otherwise have checked.**
`tools/probe_core_clearance.gd` sweeps a box the size of the new bund through
every capture point on the ten levels and reports what else is solid in it. Run
at all three eras:

| footprints | clashes |
|---|---|
| shipped (1.88 / 3.38 / 5.18) | **5** |
| round one (3.25 / 4.44 / 6.31) | **7** |
| this round | **8** |

So **five of the eight were already there** before any of this — `RelayShore`
(pittsburgh), `RelayServer` (mutaha_wip), `RelayCraters` (coast road),
`RelayServer` and `RelayCompute` (mutaha appendix) have stood inside something
since they were placed. Round one added `RelayFurnace` (pittsburgh) and
`AnchorObjective` (valley basin). **This round adds exactly one:
`RelayStrip` in Pittsburgh, at Godot (100, 0.58, −85).** Pittsburgh was the one
to check and it is the one that moved; four of its five are now fouled and that
street needs a human eye, because a core is an objective you walk up to and
three of them are standing in walls.

## 6. What is the human's

- **Whether the fin bank should be on the flank the player approaches.** It is
  on −Y and the approach is −X, so the richest elevation is the one you see
  second. Turning the composition 90° is one constant.
- **Whether the small core needs to read across a map at all**, given 4.19 m of
  machine at 40 m is a smudge with an amber strip on it.
- **The one new clash, and the four old ones**, which are placement rather
  than art.
- **Whether a core at rest should have visible light in it**, still open from
  round one. The staircase answers it differently from the bands did: at rest
  the panels are found, at the crest they are the object's loudest feature.
