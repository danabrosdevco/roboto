# BRIEF — the proving grounds, larger and more open

Written 2026-10-13 by TERRAIN. Owner: **TERRAIN**. Status: **not started.**

The human's words:

> could you do a new proving grounds art so that the space is larger and a touch
> more open? we're revising how capture points work / and how extraction works
> and both are larger so we need 1. an area for an enemy capture point and 2. an
> open space for a 'bunker' which is both extraction point and a capture node.
> you don't need to build the capture points or anything just extra space at the
> back of the map and make the map more open so walkers / rovers etc. can more
> easily navigate it

**You are building SPACE, not gameplay.** No capture points, no extraction
volumes, no objectives, no spawns. Somebody else fills these rooms.

---

## 1. What is there now — measured, do not re-derive

`maps/proving/proving_level.map`, **309 brushes in 4 entities, 0 overlapping
pairs** (it got to 0 the hard way in `a28cbab8`; it must still be 0 when you
finish). There is **no generator** — this is the only active map without one.

| | |
|---|---|
| shell | 200 m on Godot Z (−100…100), 140 m on X (−70…70), floor at Y −3.5 |
| **playable today** | walled rectangle, roughly **x ±29, z −45…+46** |
| squad spawn | `(0, 0.2, −28)`, facing +Z |
| objective + level exit | both at `(0, 3.2, +37)` |
| cover points | 19+, all inside z −45…+46 |

The floor **already extends to the shell**. The open grey apron outside the
perimeter wall is flat, walkable ground that is simply fenced off. So most of
the space the human wants exists; it is walled away and not baked.

### The trap that would waste the whole job

`maps/proving_level.tscn`'s NavigationMesh sets:

```
filter_baking_aabb = AABB(-30, -3, -47, 60, 22, 94)
```

**The bake is clipped to x ±30, z ±47.** Build the finest back area in the
project and nothing will path onto it until that box grows. Grow it to cover
everything you build, with a couple of metres of margin.

Also unset on that mesh, so taking Godot's defaults: `agent_radius` 0.5,
**`agent_height` 1.5**, `agent_max_climb` 0.9, `cell_size` 0.25.
`geometry_parsed_geometry_type = 1`, so it bakes from **colliders**.

---

## 2. Build a generator

Write `tools/build_proving.gd`. Yes, that is more than editing the `.map`, and
it is the right call:

- every other active map has one, and this is the odd one out
- capture and extraction are **being revised right now**, so there will be a
  next revision and a next one after that
- the existing map reached 0 overlaps by hand and a generator keeps it there

**Keep the landmarks.** The central tower and the two blockhouses at either end
are what the place reads as. A distance-legibility pass on another map measured
that tall mid-ground mass is the single thing that makes terrain readable, so
do not flatten the arena into a car park. Larger and more open, not empty.

Rebuild the level with `tools/level_map_rebuild.gd` — it rebuilds the
FuncGodotMap inside the scene **and leaves the objectives, spawn, level exit
and cover points alone.** Do not hand-edit the `.tscn`; that is how gameplay
nodes get destroyed by a regeneration.

---

## 3. The layout

Three zones along +Z. The player still enters at `z −28` facing +Z; **do not
move the spawn, the objective or the level exit** — they are gameplay nodes and
not yours. Build around them.

**A. The arena, z −45…+46 — keep, but open it up.**
Its lanes are a tight grid of low walls that a 3.40 m Rover cannot turn in.
Widen them and delete enough of the maze that every route meets section 4.
Keep the tower and the blockhouses.

**B. Enemy capture yard, about z +55…+72.**
An open compound an attacking squad has to take: clear in the middle so a
capture volume can sit there later, cover at its edges, and **at least two
separate approaches**. Do not put anything in the centre — leave a clear
**20 × 20 m** floor.

**C. Bunker clearing, about z +75…+95.**
This one is both extraction point and capture node, so it is approached, held
and left under fire. Leave a **flat, completely clear 30 × 30 m** pad with
**open ground on at least three sides**. Nothing in it, no slope across it. A
Bulwark must be able to walk right round whatever gets dropped there later.

Open the back perimeter wall between A and B — a gateway or a breach, not a
removed wall, so the arena still reads as an arena. Widen the playable width
in B and C out toward **x ±55**.

---

## 4. Navigation — the numbers this has to meet

Measured frames: walker **1.70 wide × 3.00 tall**; bulwark **2.26 across the
shield**; rover 1.70 wide and **3.40 long**; reclaimer 1.50 × 3.10.

- **No route narrower than 8 m**, anywhere. Build generous and the bake cannot
  argue. At 8 m even a future radius-1.25 bake leaves 5.5 m of mesh.
- **Nothing solid between 0.25 m and 0.5 m.** The baker will not climb it and
  the body steps over it, so it bakes as a wall the squad walks through.
- **Playable ground stays flat.** Height comes from built assets, not from
  slopes. A ramp the squad must use is at most 15°.
- Keep **3.0 m of headroom** over every route — a Walker is 3.00 m tall and the
  mesh currently promises 1.5.
- Recast erodes `agent_radius` off **every** side. Measure gaps as built width
  minus twice the radius.

**Set on the NavigationMesh:** `filter_baking_aabb` grown to cover the new
extent, and `agent_height = 3.0`, because 1.5 is simply wrong for this cast.
**Leave `agent_radius` and `agent_max_climb` alone** — a separate brief
(`docs/briefs/MULTI_CLASS_NAV.md`) is about to change how radius works, and two
variables at once teaches nothing. Build wide enough that radius stops
mattering.

---

## 5. Prove it

- `probe_nav_reach` with `CHASSIS=walker|bulwark|rover|reclaimer` — the squad
  must reach the existing objective AND both new areas, every chassis.
- **A Rover must be able to turn around in every lane.** It is 3.40 m long;
  reachability will not catch a corridor it can enter and not leave.
- `probe_map_overlap` on the `.map`: **0 pairs**, as now.
- `probe_footing` and `probe_level_faults`: nothing standing in the air,
  nothing interpenetrating.
- Top-down plan, before and after, so the change is visible at a glance.
  `tools/minimap_bake.gd` does this — **note it writes into `maps/minimaps/`
  for every level, so check `git status` after and revert what you did not
  mean to change.**
- Eye-level shots down each approach, **through the signal filter** at the real
  **1.50 m** eye (uniforms live in `Character/hud/hud.tscn`, not the shader
  defaults). A render without the filter is not a picture of this game.

---

## 6. Rules

Do not create or switch branches; three lanes share this checkout. Stage paths
explicitly, commit through a throwaway index, and leave files you did not
change alone. Use the `_console.exe` headless; the plain `.exe` detaches and
prints nothing, so a failure looks like a pass. **Python is not installed.**
`check.sh --changed` and `smoke.sh` must pass.

## 7. Report back

A before/after plan, the reach numbers per chassis, the narrowest route you
actually built, and anything you could not open up without wrecking the arena's
character. Say plainly if the 30 × 30 m bunker clearing does not fit where this
brief put it — the zone bounds are a starting point, not a survey.
