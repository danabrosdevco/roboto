# What makes a good asset

Every rule here was paid for. Each one names the bug it prevents, because a
rule without its reason gets dropped the first time it is inconvenient.

Scope: TrenchBroom brush assets built by the `tools/block_*.gd` generators and
placed by the `tools/build_*.gd` level builders. Read `CLAUDE.md` first; this
is the long form of "make a new block".

---

## 1. The one rule

> **Absolutely no overlap ever. They can touch but they can't overlap.**

Two brushes may share a face exactly, back to back, each visible only from its
own side. That is correct and it is how a wall meets a floor.

Interpenetration of *any* depth flickers. There is no depth small enough to be
safe — the depth buffer cannot choose between two surfaces at the same place,
so it picks differently as the camera moves and the surface crawls. "A few
centimetres proud" is not a softer version of the rule, it is the bug.

This applies to mesh-only and ghost brushes too. They are not drawn by the
collision system but they *are* drawn.

Detail is **in or out**. A window is a reveal cut into the wall or a frame
standing clear of it. It is never a pane laid on the face.

---

## 2. The numbers, measured

Do not carry these in your head between sessions — re-read them. Two of them
changed under me mid-project and I quoted the old ones for weeks.

| | value | where |
|---|---|---|
| map units per metre | **32** | `UPM` in `tools/block_buildings.gd` |
| AI step-over height | **0.45 m** | `step_height`, `Character/characters/ai/enemy.gd` |
| AI step-over reach | **0.35 m** | `step_forward`, same file |
| navmesh cell size | **0.25 m** | the `NavigationMesh` in each `*_level.tscn` |
| agent radius | **0.5 m** | same — **2 cells** |
| agent height | **1.8 m** | same |
| cell height | **0.25 m** | not set in any level — Godot's default |
| agent max climb | **0.25 m**, i.e. exactly 1 voxel | same — but `salient` uses 0.5; **check the scene** |
| edge max error | **1.3 cells = 0.33 m** | same |
| texture size / format | **256 x 256, RGB8** | the PSX pack, bar two files |
| texture luminance | mean ~0.20, peak **capped 0.46** | `CEIL` in `tools/make_textures.gd` |
| texture quantise | **32 levels/channel, 4x4 Bayer** | `LEVELS`, same file |

**Axis mapping.** FuncGodot maps Quake `(x, y, z)` to Godot `(y, z, x)`.

- A block built along its map **X** runs along Godot **Z**.
- A block whose front is its map **+Y** faces Godot **+X**.
- Yaw 90 sends `+X +Z` to `+X −Z`, **not** to `−X +Z`.

Use the `ALONG_X` / `ALONG_Z` / `FACE_*` constants the builders already define.
Re-deriving this by hand is how Polaris's first assembly came out with the ring
road at right angles to its own corners.

---

## 3. Ground and surfaces — the expensive family

This is the single costliest class of defect in the project. On Polaris it was
1,231 of 8,119 sample columns; on Georgetown 399 of 3,243. Roughly one map
column in seven, crawling.

**The fault is two horizontal faces at the same height over the same ground.**

It hides from everything. The brush probe only compares brushes *inside one
`.map`*, and the two faces are in different files. The piece-pair AABB test
sees almost no shared volume, because a road bed 0.3 m deep laid on a slab that
is already there barely intersects it. Only `tools/probe_level_faults.gd`'s
coplanar check finds it, by casting down twice per column.

### Rules

- **A piece that stands on ground does not bring its own ground.** If the level
  provides a floor, the asset's job is what stands on it.
- **Where an asset must carry a surface** — a driveway apron, a loading pad, a
  storage yard — its top goes at **0**, and the clearance comes from sinking
  the ground to **−0.06**, never from lifting the asset. Lifting the aprons
  instead drove them up into their own shutters, kerbs and walls: 32
  overlapping pairs inside one piece.
- **A piece that replaces a ground tile must be the size of the tile.** The
  retention basin only works because it is exactly 64.00 x 64.00 m — one 2x2
  block of cells.
- **An excavation cannot be expressed by one-tile-per-cell** unless the hole is
  the size of the cells. A basin or a canal channel needs a cell-aligned void
  list *and* a piece sized to fill those cells, both driven from one constant.
- **Ground is derived, never described.** The level builder records the
  footprint of anything that brings a walking surface and lays the floor last,
  one tile per cell. Three hand-written versions drifted: the worst typed a
  corridor's left edge into a function taking a centre, putting 350 m of
  asphalt off the west side of the map and bare dirt under the eastern half of
  its own road. Nothing reported it, because nothing compared the two.

---

## 4. Navigation — what the baker can and cannot see

`move_and_slide` has no step-up. The AI fakes one by retrying a blocked move
0.45 m higher and 0.35 m forward. **It is why everything in this game needs a
ramp built onto it.**

- **Stairs do not bake.** A tread must be at least ~2x the agent radius —
  **1.0 m** — or Recast finds no walkable surface on it at all. A 0.34 m tread
  baked nothing. Build stairs as a **ramp with mesh-only treads**: the ramp is
  what walks, the treads are what you see.
- **A 0.3 m lip closes a route.** The agent climbs 0.25 m. The canal coping ran
  across every bridge mouth and the squad only ever got over because the deck
  and the coping happened to round into neighbouring voxels. Sinking the decks
  6 cm dropped reachability from 90.9% to **49.3%** and shut all four bridges.
  **A 6 cm change to a surface can close a route, and only a bake says so.**
- **The plinth rule.** A skirt between 0.45 m (AI step-over) and 0.5 m is the
  worst possible height: the navmesh says the squad is standing on it and the
  body cannot hold it. Either under the step or well over it. `core_column`
  uses a 0.22 m pad then a 0.62–1.1 m collar with nothing between.
- **`agent_max_climb` is in voxels of `cell_height`**, and `agent_radius` is
  ceiled to cell units. A value that looks like metres is not.
- **Godot has no per-agent path clearance.** A path query takes no radius, so a
  wide chassis needs its own navmesh on its own layer.
- **The navmesh is not the player.** A surface being in the mesh does not mean
  a body can stand on it, and the reverse.

Design consequences, from the human:

- **Playable ground must be flat.** Bots cannot use jagged terrain or ridges.
  Height comes from built assets, not painted hills.
- **Gate with walls, not cliffs.** A steep ring around a position reads as a
  crater; build the wall and leave the ground open.
- **Riverbeds are not navigable.** A river must force the squad onto a
  crossing — and removing a bridge only closes a route if a *reloaded path
  test* proves the squad cannot wade.

---

## 5. Collision — what is solid, and what only looks it

`no_collision()` puts everything after it into a `func_detail_illusionary`
entity: drawn, not solid, not seen by the navmesh baker. It is used about a
hundred times across the kit and it is the most under-used tool in it.

### The rule

> **Nothing is solid between 0.25 m and 0.5 m.** That band is the baker's climb
> at the bottom and the squad's step-over at the top. In it, the navmesh says
> *wall* and the AI says *step*, and neither is wrong.

Below 0.25 m, Recast walks over an obstacle and the mesh flows across it, so a
kerb costs nothing — the 0.16 m kerbs throughout the street kit are fine as
they are. Above 0.5 m, the squad cannot step over it, the navmesh and the body
agree, and collision is the point. **It is the gap between the two that breaks
things**, and it is only 25 cm wide.

Check which numbers a level actually bakes with: `agent_max_climb` is 0.25 on
georgetown and polaris but 0.5 on salient, where the band closes entirely.

The second rule follows from the first:

> **Scatter is mesh-only, unless being stopped by it is the point.**

Scatter, debris, litter, kerb stones, fallen branches, scree, tussocks,
benches, hedges, planting, spoil, cable runs, small pipework. If a body would
walk over it, or *might*, it should not be solid.

### Three reasons, and they are all worse than they sound

1. **A small collider punches a hole much bigger than itself.** Recast erodes
   the walkable surface by the agent radius around every obstacle. Agent radius
   is **0.5 m**, so an ankle-high stone 0.3 m across removes a disc about
   **1.3 m** wide from the navmesh. A handful of them scattered across a route
   removes the route. The comment in `block_alpine.gd` puts it exactly: *a
   knee-high stone with a collider punches a hole in the navmesh.*

2. **A line of them chops the ground into slivers.** Colliders closer together
   than 2 x agent radius (**1.0 m**) leave a gap that bakes as nothing at all —
   the same arithmetic that stops a 0.34 m stair tread baking. So a hedge, a
   fence line or a row of bollards with collision does not narrow a route, it
   **closes** one. From `block_suburbs.gd`: *the whole point of a hedge on a map
   is that it hides a route rather than closing one.*

3. **Anything near 0.45 m is a maybe.** That is the AI's step-over height
   exactly. A park bench is 0.45 m to the seat, so with collision the squad
   sometimes steps over it and sometimes does not, depending on approach angle
   and speed — `block_canal_park.gd` calls a row of them *a line of maybes*.
   Nondeterminism is worse than either outcome: it cannot be designed around
   and it cannot be reproduced in a bug report.

**The band cuts both ways, and the second way is worse.** A lip in it does not
only carve navmesh the squad should have — it is also a wall the navmesh
respects and the body does not, so the squad can step over an edge the mesh
told the planner was closed. The canal coping is 0.3 m, chosen deliberately
because 0.3 is "under the 0.45 a body steps over". That is true, and it is the
problem: the baker will not climb 0.3, so the towpath mesh stops at the coping,
while the body steps straight over it into a 2.6 m channel. **A height checked
against the body's step must also be checked against the baker's climb.**

### What should still be solid

Cover. The point of a car park's corrals, planters and bins is that they stop a
bullet and break a sightline, and that needs collision. The test is not size,
it is **whether being stopped by it is the point** — waist-to-head cover is
solid, ankle-height clutter is not.

Where a thing must be solid but its shape need not be, collide as a **box**. The
shape the physics and the navmesh see does not have to be the shape you draw: a
pillar cluster nothing will ever walk between is a box, and the navmesh is
cheaper and better for it.

### Cost

Collision is generated **per brush**. A wall with window reveals came out at
**451 collision brushes**; `no_collision()` before the detail pass made it 4.

Anything meant to go down in hundreds — grass, scree, litter — is mesh-only
*and* wants a visibility range on its layer.

---

## 6. The generator is the source — until it isn't

- Assets are generated. Edit `tools/block_*.gd`, regenerate, rebuild the
  prefab. Never hand-edit a generated `.map`.
- **Except once a human has edited it.** Then the file on disk is the source,
  and force-rebuilding destroys their work. This has happened twice. For small
  changes to an edited map use `tools/map_retexture.gd`.
- FuncGodot reads `.map` as **raw text** at load, so `--headless --import` is
  not needed for a `.map` change. A changed `.map` *does* need
  `tools/block_prefabs.gd` to rebuild its `.tscn`.
- **Check at placement time, not after.** Moving pieces one at a time to clear
  clashes found afterwards is whack-a-mole — each piece you move to clear one
  lands on something else. Georgetown took four passes to get from seventy
  clashes to fifty that way. The builder knows the footprints, so it warns at
  the moment it puts a piece down, naming both pieces.
- **Describe once, derive the rest.** Any coordinate that describes where
  something *else* is will drift the first time that thing moves, silently.
  `Polaris_Storage` was typed at (−314, −150); the ring road changed by 6 m,
  the power centre moved with it, and the objective ended up inside a wall —
  found only by walking a baked navmesh.
- **Every early return warns.** A function that silently does nothing is the
  most expensive kind of bug here.
- **A checker with categories hides every fault in the category it skips.**

---

## 7. Readability — the part no probe measures

An asset that is geometrically perfect and reads as nothing has failed.

- **Prominence needs height on the near lip.** A flat hilltop hides what stands
  on it; roughly 23 m on the approach side or the objective is invisible.
- **Like-on-like has no edge.** The retention basins are real 2.6 m
  excavations and read as flat ground, because dirt slopes into dirt. A change
  of material at a rim is what makes a hole look like a hole.
- **Cover is waist to head height.** A car park's real cover is accidental —
  corrals, planters, bins. That is the accident worth building.
- **Measure clearance between built pieces before calling a placement done.**
- **No robot assets in TrenchBroom.** Build the bay, never the robot standing
  in it.

---

## 8. Before you call an asset done

```bash
bash tools/check.sh --changed          # must print PASS; includes the brush-overlap gate
```

Then, depending on what you touched:

```bash
MAP="res://maps/blocks/<dir>/<name>.map" "$GODOT" --headless --path . \
    --script res://tools/probe_map_overlap.gd        # one asset, brush against brush

LEVEL=res://maps/<level>.tscn "$GODOT" --path . \
    --script res://tools/probe_level_faults.gd       # holes, floaters, two floors, pieces inside each other

"$GODOT" --path . --script res://tools/probe_ground_clutter.gd   # solid things in the 0.25–0.5 m band

BAKE_ONLY=1 LEVEL=... "$GODOT" --path . --script res://tools/probe_nav_hillfort.gd
LEVEL=...            "$GODOT" --path . --script res://tools/probe_nav_reach.gd
```

**Rebake and re-walk after any change to a walking surface, however small.**
Six centimetres closed four bridges.

A screenshot cannot prove the absence of flicker — a coplanar count can. But a
count cannot prove an asset reads, and a screenshot can. Use both, and say
which one you actually ran.

---

## 9. Failure families, by symptom

| symptom | cause |
|---|---|
| surface crawls as the camera moves | two faces at one height; or detail laid proud |
| geometry drawn twice in a loop | `for s in [-1, 1]` with `s` unused in the body |
| a window inside the back wall | `window("y", -d, ...)` — found independently in three files |
| a window half a width off | `window()`'s `along` is the **centre**; callers passed the left edge |
| a mass with no rooftop plant | a parapet or cornice built as a solid slab, swallowing it |
| a basin that is not a basin | the bowl top sat *above* the slab — it was never a hole |
| a piece sinks into the ground | `heap()` / `mound()` with a 0.3 m skirt |
| rails passing through posts | `fence_run` drawing both from the same extent |
| squad stuck at the foot of a block | a skirt between 0.45 and 0.5 m — the plinth rule |
| a clear route the squad will not take | ground clutter with collision — 0.5 m erosion each side |
| squad steps over a thing sometimes and not others | it is near 0.45 m **and** solid; make it mesh-only |
| a hedge or fence line closes a route it should only hide | colliders under 1.0 m apart bake nothing between |
| a route closes after a cosmetic edit | a lip over 0.25 m; rebake and walk it |
| an objective unreachable, geometry clean | a typed coordinate naming a derived piece |
| texture missing at load | a texture name that was never in the folder — **check, don't invent** |
| `load_steps` error | it must be resources **+ 1** |
| enum values shift in a `.tscn` | enums are **append-only** |
| one instance's change hits all of them | resources are shared — `duplicate()` first |
