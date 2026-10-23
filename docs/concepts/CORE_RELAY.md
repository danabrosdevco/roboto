# COMPUTE CORE — ROUND TWO. THE BANDS ARE GONE; IT IS A MACHINE NOW.

Round two of `docs/briefs/COMPUTE_CORE_ART.md`, which still governs the
CONTRACTS and whose VISUAL direction is overridden here by the human.
2026-10-14 · **status: built, shipped, photographed lit at three sizes — and
as of the same day WIRED: the game's own capture code docks the drone on the
pad, asserted on a gate. Section 4a is that round and is the one to read.**

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
| dock clearance | `CORE_TICK=1 tools/probe_core_clearance.gd`, with `tools/tick_placed.gd` |
| **dock, on a gate** | **`tools/test_holdable_core.gd`** — the real dock path, on the real prefabs |

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

**The run turns the corner, and that deletes an open question.** The human saw
this lit, liked it, and asked for one change — "can we have the glowing lines
bit extend on two sides of it". It now does: a return of the same fin bank on
the mass's **−X face**, with the same panels at the same depth, carrying the
LOW steps of **one** run that then turns the corner and climbs the flank.
`core_relay_large_flank.png` shows the whole of it — three panels on the
approach face stepping up to seven across the bank — and `core_relay_large_tick.png`
shows the other half of the same thing from the approach bearing. **Two
adjacent faces, not opposite ones**, so it is still two of four and still
asymmetric.

That also answers round two's third open question, which was whether the whole
composition had to be turned 90° because its richest elevation faced away from
the approach. **It does not.** The approach now carries the start of the climb
and the corner; the flank carries the ascent. Delete that decision.

What makes it one run rather than two decorations: the return is the SAME
component (same fins, same depth, same three-units-inboard-of-the-tips rule),
and the step heights are a single table crossing both faces — the return's top
step is the main bank's bottom step. The one thing that constrains it is the
inner raking strut, which has to bear on that same face; the bank stops 14
units short and the strut passes through the gap, which looks like what it is.

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
| shelf tip past the bund's −X edge | **1.06** | 0.31 | 0.01 |
| pad | 2.625 sq | 2.625 sq | 2.625 sq |
| **dock point**, Godot, local | **(−0.44, 2.91, −1.69)** | **(−1.06, 4.59, −1.69)** | **(−1.94, 7.84, −1.56)** |
| `ext` · `LIP_U`, units | 24 · 8 | 36 · 8 | 36 · 8 |
| **drone clearance above the pad** | **0.46** | **0.84** | **0.84** |
| brushes · collision | 56 · 9 | 60 · 9 | 66 · 9 |
| Paint · Lit entities | 5 · 11 | 5 · 13 | 5 · 16 |

The FOOTPRINT row is the bund, which is what a level places and what the
clearance sweep measures; it has not moved. The SHELF now reaches past it at
the free end, which nothing at ground level cares about — the slab is at 2.91
to 7.84 m — but which does mean **a small core within about a metre of a wall
on its −Z side will have its shelf inside that wall.** The row is there so that
is a known number rather than a surprise.

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
asymmetric as the brief asked: **glands in the tray (0.66 m) → up the −X face →
round the corner → up the fin bank → the shelf lip at the tip of the overhang →
two crown slots.** 11 / 13 / 16 lit pieces, every one carrying `pulse_y`, **none
constant** — the console plate was the only constant one and it is gone. Rest
energy is baked once by the dress pass and nothing else writes
`emission_energy_multiplier`.

**Materials.** `metal_wall_3` navy ribbed on the masses, `metal_floor_1` plate
on every fitting, `grate_perf` on the tray and the vent, `glitch_tx_neutral` on
the lit pieces with emission as well as albedo and `EMISSION_OP_ADD`. No
concrete, no `metal_floor_3`. Every material `resource_local_to_scene`.

## 4a. The TICK on the pad — THE GAME DOES IT NOW, and the geometry moved to let it

Round two staged a drone by hand in a camera script, which proves a marker is
in the right place and nothing at all about whether capture can use it. The
human's answer to that was the whole of this round's brief: *"can you please fix
it so that it works between the tick and the capture objective? that's the whole
point — they have to work together."*

**1. The core places the drone on the pad, in its own code, and a gate says so.**
`holdable_core.gd::_call_tap` did `tap.position = Vector3(0.0, _dock_y(), 0.0)`:
the core's own AXIS, at a height off `size_tier`. That is true of a core whose
cap is a centred slab on a mast, and this one's is not — the pad is off-axis on
a cantilevered shelf at two thirds height — so capture dropped the pod through
the model at every size and nothing said a word, because a prefab and a pod in
the same space is not an error, it is two meshes. There is now a `_dock_point()`
that returns a **Vector3**, read off the `Dock` marker the prefabs ship, and
`tools/test_holdable_core.gd` runs the real dock path on the real prefabs and
measures where the pod stopped: **0.000 m from the marker at all three sizes**,
with the host moved to (12, 3, −7) and turned 37° so that an identity transform
cannot pass the test by accident. The axis the old line used is 1.74 / 1.99 /
2.49 m away from the pad, and the test asserts that too — if it ever reads zero,
the pad has moved back onto the axis and the fix has been undone by geometry.

**2. The machine gave way, not the drone.** `ext` — the slab that runs back from
the pad toward the mass, and therefore how far the pad stands off it — is now
**24 / 36 / 36** against round two's 0 / 12 / 36. The rule is written down in
`build_core_relay.gd`: run the slab back until either the drone has real room or
the slab reaches the bund's own −X edge, whichever comes first. On the medium
those coincide exactly at 36.

| | horizontal clearance above the pad | was |
|---|---|---|
| small | **0.46 m** | FOULED |
| med | **0.84 m** | 0.08 m |
| large | **0.84 m** | 0.84 m |

**3. All four barbs are on deck.** The pad's outboard edge WAS the slab's edge —
that is what a cantilever is — so the leg at the free end closed on open air at
every size while the other three bit. It overhangs by a measured 0.11 m, so the
slab now runs `LIP_U` = 8 units (0.25 m) past the pad at that end and the barb
stands on 0.14 m of it. **Eight units and not more**: the lip is a tip detail on
the overhang, not a second shelf, and the cantilever is the strongest thing on
the model. `core_relay_small_tickclose.png` is the shot — four legs down, inside
the lugs, the machine clear behind.

*The probe had been lying about this, and the lie is worth keeping written down.
It dropped a ray from 0.1 m above each barb tip, and the barbs come down 5 to
11 cm BELOW the deck surface — they are meant to; a clamp hooks an edge, it does
not stand on a floor — so the ray started INSIDE the slab, where a trimesh
either misses or reports its far side. It called a barb standing on 0.25 m of
new lip "NOTHING UNDER IT". It now starts clear above the pad and compares the
surface it finds to the tip.*

**4. The small core survives, and it is the one to look at.** Placed, the TICK
is 3.19 × 3.50 m against a 4.50 × 3.50 m footprint, so a captured small core is
mostly drone and no arithmetic changes that. What `ext` 24 costs is **1.06 m of
shelf hanging past the bund's −X edge**, at 2.91 m up on a 4.19 m machine.
`core_relay_small_tick.png` and `core_relay_small_flank.png` are the evidence
and the verdict is that it reads as a machine with an overhang rather than as a
bird table — the crown still goes up past the pad, the fin bank and the amber
still carry, and the drone is a big thing clamped onto a small relay, which is
what a small relay being taken should look like. **If the human disagrees, the
dial is `ext` on the small and the next stop down is 18** — 0.26 m of clearance
for 0.56 m of overhang. Below that it fouls again, and there is no version of
this where the small core both clears the drone and keeps its slab inside its
own plinth: the bund edge is at `ext` 0.

**5. What is still not wired, and it is not in a file this lane may touch.**
`capture_tap.gd` now builds its body from **the real `tick.tscn` rig** (another
lane, this round), so the thing the game lands is the TICK and not the old
procedural pod. Two numbers are missing before the shot and the game agree:

- **the pose.** The tap carries the rig in its FLIGHT pose. Measured, that pose
  is 4.08 × 4.52 m and spans 3.25 m — wider than the 2.625 m pad and wider than
  the small core's entire footprint. The placed pose is 3.19 × 3.50 and clears.
  `tools/tick_placed.gd` is the state change, compiled: thigh −22°, shin −62°,
  `FanTower.position.y` 0.76, booms −48°.
- **the lift.** In the placed pose the rig's own bottom is 2.11 m below its
  origin, so the body wants `TickPlaced.LIFT` (+2.00 m) above the dock point or
  it sits with its barbs 2 m under the shelf.

Both belong in `capture_tap.gd`, on landing. The dock POSITION is correct
without them.

**The renders are of the game's number now.** `tools/shoot_core_skeleton.gd`
seats a real `HoldableCore` on the model the way `site_slice.gd` does and asks
it where a tap goes, rather than reading the marker itself — so if the drone is
in the wrong place in `core_relay_*_tick.png`, it is in the wrong place in the
game. Only the pose is still the rig's, for the reason above.


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

- **The small core's shelf now hangs 1.06 m past its own plinth**, which is what
  clearing the drone there costs. Decided rather than asked, because the brief
  was to make it work; `ext` 18 is the next stop down if the overhang is worse
  than the margin. See 4a.4.
- **The fourth barb grips now** — 0.25 m of lip at the free end, decided rather
  than asked, for the reason in 4a.3. The alternative that was rejected was
  calling a clamp that grips three edges and overhangs one correct.
- **The drone's POSE and LIFT on landing**, which live in `capture_tap.gd` and
  are the last two numbers between the shot and the game. 4a.5 has both.
- **Whether the small core needs to read across a map at all**, given 4.19 m of
  machine at 40 m is a smudge with an amber strip on it.
- **The one new clash, and the four old ones**, which are placement rather
  than art.
- **Whether a core at rest should have visible light in it**, still open from
  round one. The staircase answers it differently from the bands did: at rest
  the panels are found, at the crest they are the object's loudest feature.
