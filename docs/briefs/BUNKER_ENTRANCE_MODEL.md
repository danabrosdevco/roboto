# THE BUNKER ENTRANCE — a model brief for TERRAIN

**Written 2026-10-13, rewritten 2026-10-14 once the fiction was settled.** The
bunker is the single most important object in the campaign rework and it is
currently a glowing box on a slab.

## What it is

**It is the surface entrance to an underground rail station.**

Not a pillbox, not a hatch, not a trophy you touch. A set of **huge doors in
the ground or in a hillside, which grind open onto darkness, and which you walk
into.** Underneath is a platform and a line. That is where the train is.

Everything else in this brief follows from that one sentence, so it is worth
sitting with: the depot you live on is a railhead. The squad's home is a train.
Every site in the campaign sits on top of the same network, and the bunker is
where that network surfaces. **Taking a site means opening its door to the
railway.**

## Why this is the right shape — it makes three systems one thing

### 1. Walking into it IS the extraction

The doors are the level exit. There is no separate pad somewhere else on the
map with a green beacon on it. You take the bunker, the doors open, and the way
out is **through them, into the dark**.

> **This is a change from what is built today.** Taking the bunker currently
> *unlocks* the level's existing `LevelExit`, which on Valley Basin is 310 m
> away across the map. That was the cheap version. The target is that the
> doorway itself carries the exit volume, and the old extraction pad goes away.
> GAMEPLAY's side of that is small; it needs the model first.

### 2. It is how you come BACK — §12.8 already says so

CAMPAIGN_REWORK §12.8: *"Assault = you arrive by air. Defence = you arrive by
rail... you come up out of the ground. The first time you fly in, every time
after you come up the stairs."*

Those are **the same doors, used the other way**. On an assault you fight to
them and leave through them. On the defence of that same site you come **up**
out of them, at the start, and then turn round and hold the ground in front of
them. One model, two of the most important beats in the loop.

So the inside of the doorway matters more than it would for set dressing: the
player will walk out of it toward the camera at the start of every defence.

### 3. The stand-down is the doors opening

§12.7: *"take the ground, stand down, go home"*. The stand-down is **the time it
takes to open the way down** — 45 seconds on Valley Basin.

This is the hard requirement and it is not obvious from an asset list:

> **The player spends those 45 seconds standing next to this object being shot
> at, and the doors must say how far through it is from a glance, from cover,
> with no HUD element.** It is a progress bar made of geometry.

It can also **stall and resume**. `stand_down_interrupted` fires if the bunker
is lost; progress is kept rather than reset, so the doors stop partway, sit
there, and grind on again when you retake it. Doors do this legibly and a glowy
post does not — which is most of why this shape is better than what is there.

## The three states

| state | when | reads as |
| --- | --- | --- |
| **SEALED** | the whole mission until you take it | shut, dark, massive, obviously a door and obviously not open |
| **OPENING** | the 45 s stand-down | leaves grinding apart, light spilling out of the gap, dust. Position of the leaves = progress |
| **OPEN** | won | a lit doorway with darkness behind it that the squad walks into |

## What it also has to carry

The bunker is a `HoldableCore` like the surface cores — it is taken by working
a terminal, and a tap drone docks on it.

- **A terminal face**, reachable on foot at standing height, beside the doors.
  Interact volume is about 2.4 × 1.4 × 2.4 today.
- **A dock** on top or above for the tap drone to land on. The drone is **3.4 m
  across the rotors** (see the drone shots already sent); it wants a flat
  unobstructed landing clear from directly above. `dock_height` is 4.9 m today
  and is an export — move it and tell GAMEPLAY the number.
- **A silhouette that reads as THE objective from across the map.** The beacon
  column does some of this and is now per-map height
  (`site_slice.beacon_height`), but the doors should not disappear under it.

## Scale

Big. If a train runs under it the doors should be plausible for one — and the
squad walks in together, including a **Rover (3.4 m long)** and a **Walker**,
so the opening wants to take a vehicle abreast rather than a man.

The placeholder it replaces is a 1.2 m post on a 6 × 6 m pad, which is the
wrong order of magnitude and reads as a bollard. Treat those numbers as what
the code currently assumes, not as a constraint — `site_slice.gd` exports the
tier and the dock height.

## It has to work on nine maps that look nothing alike

Valley Basin is an open bowl. The Causeway's interiors have **5.25 m of
clearance**. Georgetown is benched terraces, Hillfort is a climb, Polaris is a
hold-out drawn as an interior.

**So: a kit, not a monument.** §13.2 calls it a "bunker / portal kit" for this
reason. Doors that can sit in open ground as a sunken stair head, in a cliff or
revetment as a tunnel mouth, or against a wall indoors — same leaves, same
mechanism, same light, three mountings.

Where the open state wants height, put it in the beacon, which is a separate
node with a per-map height, not in the model.

## Vocabulary — and it already exists above ground

The railhead has the language: green and brass, heavy industrial plate, visible
mechanism. **And TERRAIN has just built the surface version of exactly this
building**: `maps/railhead_station.tscn` — `Station_HeadHouse`,
`Station_HeadHouseDoor`, the canopies, the mast, `Station_PlatformCentre`.

> **The bunker entrance is that head house, buried.** Same company built both.
> Whatever the railhead station says about how this world makes a station, the
> bunker should say underground and under fire.

The cyan emission on the placeholder is the compute signal colour
(`HUDPalette.SIGNAL`) and is worth keeping somewhere — it is how everything
network-related in the game identifies itself.

## What GAMEPLAY needs back

1. The model, in its three states, however you drive them (AnimationPlayer, a
   shader parameter, swapped meshes) — tell me which and I will drive it from
   `stand_down_fraction()`, which is a 0–1 float.
2. **The dock height**, so the tap drone lands on the model rather than in it.
3. **Where the terminal face is**, so the interact volume sits on it.
4. **Where the exit volume goes** — the point in the doorway past which the
   squad counts as having left.
5. Whether the squad can stand on or in the open doorway, because on a defence
   they start there.

## What it is NOT

- **Not a building.** It is an entrance to something underneath.
- **Not somewhere you can leave early.** §12.7: the bunker is not an exit you
  can take before you have taken it. Sealed means sealed.
- **Not a level transition you see through.** Nothing is modelled on the other
  side. It is darkness, and the level ends in it.

## Reference

- `Env/world_objects/site_slice.gd::_build_bunker()` — the placeholder it replaces
- `Env/world_objects/site_operation.gd` — the stand-down, and `stand_down_fraction()`
- `Env/world_objects/capture_tap.gd` — the drone that docks on it, 3.4 m span
- `maps/railhead_station.tscn` — the above-ground sibling
- `docs/briefs/CAMPAIGN_REWORK.md` §12.7 (the bunker), §12.8 (arrival by rail), §13.2 (the art list)

---

# TERRAIN's answers — 2026-10-14

Built. `tools/block_bunker.gd` writes the prefab maps, `tools/build_bunker.gd`
assembles them and writes the marker nodes, `tools/probe_shots_bunker.gd`
photographs the result through the HUD's own signal filter at the real 1.50 m
eye. Everything below is measured by those tools, not typed.

## What to instance

| scene | what |
|---|---|
| `maps/blocks/bunker/bunker_entrance.tscn` | **the module.** Mouth, both leaves, signal strip, lamp, 11 markers. This is the one you drive. |
| `bunker_entrance_open.tscn` | + the sunken court (open ground) |
| `bunker_entrance_cliff.tscn` | + the revetted headwall (hillsides, revetments) |
| `bunker_entrance_wall.tscn` | + the flush interior surround (≤ 5.25 m) |

Godot **+Z is the approach**; the tunnel runs into −Z. The leaves slide along
**Godot ±X**. A mounting shares the module's datum, so both drop at the same
origin with no offset.

## 1. How the states are driven

**Two floats, and nothing else.** No AnimationPlayer, no shader parameter, no
swapped meshes.

```gdscript
var f := operation.stand_down_fraction()      # 0..1
leaf_left.position.x  = -4.3 * f
leaf_right.position.x =  4.3 * f
```

`LeafLeft` and `LeafRight` are separate instanced nodes directly under the
entrance root; their prefab origin **is** the shut position, so both sit at
`Vector3.ZERO` when SEALED. Stall the float and the doors stall where they are;
resume it and they grind on. `stand_down_interrupted` needs nothing else.

Measured, against the real colliders, at the three fractions:

| f | clear span | a 1.70 m Rover | a 2.26 m Bulwark |
|---|---|---|---|
| 0.00 | **0.00 m** | stopped at the doors | stopped at the doors |
| 0.50 | **4.19 m of 8.0** (52 %) | walks the tunnel | walks the tunnel |
| 1.00 | **7.94 m of 8.0** (99 %) | walks the tunnel | walks the tunnel |

Sealed means sealed: at f = 0 nothing gets past.

## 2. Dock height

**`DockPad` is at local (0, 5.00, 0)** — the lintel deck. `dock_height` wants
**5.00**, not the 4.9 in `site_slice.gd` today. The deck is continuous and flat
for 4.0 m in front of the hill and 18 m across, and the tool fails the build if
anything stands in a 3.4 m rotor disc round that point. `BeaconMount` is at
(−7.00, 5.00, 0.75), which leaves 5.3 m between the beacon and the drone.

**One limit, stated plainly:** in the **flush interior** mounting the ceiling is
5.25 m and the deck is at 5.00, so a drone cannot descend onto it. Indoors the
tap has to dock somewhere else or that site uses another mounting.

## 3. The terminal face

**`TerminalFace` at local (8.00, 1.30, 2.81)** — the middle of the readout on a
2.0 × 1.0 × 2.0 m console standing beside the doors on the +X jamb. Put the
2.4 × 1.4 × 2.4 interact volume on it. **`TerminalStand` at (8.00, 0, 3.75)** is
where a body stands to work it; it is proven to be in open air.

The console is deliberately **outside the leaf's travel plane**, so a closing
leaf can never sweep through whatever is standing at the terminal.

## 4. The exit volume

**`ExitVolume` at local (0, 0, −4.00)** — 4 m inside the tunnel, past the leaf
plane and past the 1 m reveal. Suggested extents **8.0 × 4.19 × 6.0**, spanning
z −1 to −7: nobody counts as having left while still in the doorway being shot
at, and nobody can miss it on the way to the sealed back wall at z = −10.

## 5. Can the squad stand in the open doorway?

**Yes — the whole tunnel is theirs.** The floor is dead flat and level with the
approach for all 10 m, 8.0 m wide, 4.19 m clear overhead. Proven against the
real colliders:

- a **Rover (3.4 × 1.7 m)** walks in and **clears every yaw** in the middle of
  the tunnel, so it can turn round and come back out;
- a **Bulwark (2.26 m)** walks it;
- nothing solid stands between 0.25 and 0.5 m anywhere in the kit, so the baker
  cannot make a wall out of a threshold.

For the §12.8 arrival there are **`ArrivalSlot_1..4`** at z = −7, 2.0 m apart
across the tunnel — far enough back that the leaves are still shut over them at
mission start, so the squad comes up out of the dark and walks out toward the
camera. **`Threshold`** (0, 0, 0.5) and **`TunnelBack`** (0, 0, −9) are the two
ends of that walk.

## The other named nodes

- **`SignalStrip`** — a band across the lintel (8.0 × 0.19 × 0.25 m at y 4.50 ..
  4.75). It is **its own prefab** so it is its own mesh: tint it with
  `material_override` on the `MeshInstance3D` under that node, never by editing
  the texture's material, which nine other maps share. No cyan is baked
  anywhere; its placeholder texture is `glitch_tx_1`, which has no emission of
  its own.
- **`Lamp_Reveal`** — the one light in the model, in the soffit of the reveal,
  behind the leaves when they are shut. The 10 m tunnel is deliberately unlit.

## Numbers that did not survive contact

1. **The clear height is 4.1875 m, not 4.2.** `solid()` snaps every coordinate
   to 1/32 m and 4.2 m is 134.4 units, so the grid can say 4.1875 or 4.21875 and
   nothing between. 12 mm under the design, 1.19 m over a Walker, and it keeps
   the module at exactly 5.00 m so the flush variant still fits 5.25.
2. **The cliff face is 30 m wide, not 14.** The leaves park outboard of an 8.0 m
   opening, which makes the module 18 m across before any revetment at all; a
   14 m face cannot contain its own doors. If 14 m is a hard constraint on some
   map, the leaves have to fold or the opening has to shrink — say which and I
   will rebuild it.
3. **The leaf is cream, not green-to-the-dado.** It was painted like the wall it
   came out of in the first build, and at 60 m through ten luma steps its dark
   green lower half read as the same value as the dark opening beside it: a
   half-open door and an open door were the same picture. The leaf is now the
   bright element and the opening the dark one, and the boundary between them is
   the progress bar.
4. **The sill is in front of the leaf, not under it.** A bottom guide under the
   door shared 1.5 m³ with the kick plate at every fraction from shut to half
   open.

## What the 0.5 frame actually shows

Head-on, the half-open read works: two cream leaves parted on a 4.3 m black gap
inside an 8.0 m opening, under a lit lintel. It is legible at 14 m, legible at
60 m, and marginal at 120 m — at that range the signal strip is doing most of
the work.

**Off-axis it is weaker, and you should know that.** From cover at ~43 m and
about 40° off the centreline, the headwall and the near wing wall foreshorten
the opening badly and the difference between half and fully open is a thin
bright panel appearing or not. The design survives it, but a player holding the
bunker from a flank is reading the signal strip and the lit soffit, not the leaf
positions. The **sunken court** is the best of the three for this, because the
module stands 2.5 m proud of grade and the cut gives it a black base to be seen
against.

Shots are in the session scratchpad (`bunker_shots/`, 18 frames); re-shoot with:

```bash
RENDER_OUT=<dir> godot --audio-driver Dummy --path . \
    --script res://tools/probe_shots_bunker.gd
```
