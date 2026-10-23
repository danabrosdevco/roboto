# Brief — block collision, and why Salient is slow

Written 2026-10-10 by GAMEPLAY, off a census of every TrenchBroom block in the
project and a runtime count of what Salient actually loads.

Owner: **TERRAIN** (blocks and their use).
Status: **fix 1 done. Fix 2 piloted, rejected on its stated grounds, and then
LANDED ANYWAY on the human's call — see "Rolled out" at the very foot of this
file, and read "Measured outcome" below it for what the pilot found. The blocks
on disk ARE collapsed as of 2026-10-10.**

> **Read the outcome section first.** The performance premise of fix 2 — that
> collapsing per-brush hulls buys query time — was measured on Salient and is
> **false**. The blocks are deliberately left uncollapsed. Everything between
> here and that section is the original analysis, kept because its diagnosis
> and its numbers are right; only its conclusion is not.

**Salient loads 45,881 collision shapes. Two blocks account for 75% of them.**
Not because the map is big — because of one setting in the FGD that nobody has
had a reason to look at.

---

## The number

`tools/probe_level_cost.gd` (new, keep it) counts what a level costs at
runtime and attributes it to the block responsible:

```
LEVEL=res://maps/salient_level.tscn godot --headless --audio-driver Dummy \
    --path . --script res://tools/probe_level_cost.gd
```

```
── salient_level.tscn ──
  nodes              52312
  MeshInstance3D      1835   (one draw call each unless multimeshed)
  CollisionShape3D   45881   (every one lives in the broadphase)
  physics bodies      1159
  lights                 1

── WHERE IT COMES FROM ──
  block                               count  meshes   shapes
  feature_trench_revetment              456     912    30096
  fort_razor_wire                       117     117     4563
  estate_u_block                          4       4     1740
  estate_collapsed_corner                 5       5     1310
  estate_frame_shell                      5       5      865
  estate_slab_broken                      4       4      776
  prop_sandbag_nest                      18      18      756
  prop_power_pole                       107     107      749
  alpine_stump                           42      42      630
```

A revetment ships **66 collision shapes**. Salient instances it 456 times.

Why that matters beyond memory: every one of those sits in the physics
broadphase for the life of the level, and the broadphase is queried constantly
— `GroundSnap` on every spawn, near-miss suppression on **every shot fired by
anyone**, every melee sweep, every cover probe. The cost is not paid once at
load; it is paid per query, forever.

---

## Why it happens

FuncGodot builds **one `ConvexPolygonShape3D` per brush** for any entity whose
FGD class is CONVEX. The addon's own classes:

| class | `collision_shape_type` | shapes produced |
|---|---|---|
| `worldspawn` | **CONVEX** | one **per brush** |
| `func_detail` | CONCAVE | **one** for the whole entity |
| `func_detail_illusionary` | NONE | zero |

`worldspawn` is the odd one out. And across the project's 423 `.map` files:

```
400  "classname" "worldspawn"
121  "classname" "func_detail_illusionary"
 24  "classname" "func_detail"
  6  maps using special/clip
```

So the convention is already half-adopted — `feature_trench_revetment.map` has
71 brushes, **66 in worldspawn and 5 already in `func_detail_illusionary`**.
The habit exists; it is the *bulk* geometry that sits in the expensive class,
because worldspawn is where brushes go unless you say otherwise.

**This is not a Salient problem.** Salient is where it shows first because it
is the largest map. Every level pays it in proportion to how many blocks it
instances.

---

## Three fixes

### 1. The root — one line, affects every future import

`addons/func_godot/fgd/worldspawn.tres`:

```
collision_shape_type = 1     →     collision_shape_type = 2
```

CONVEX → CONCAVE. Every entity then gets **one** `ConcavePolygonShape3D`
instead of one per brush. Visuals untouched; nothing in the `.map` files
changes.

It is a vendored addon file, so an addon upgrade would silently revert it.
Worth a one-line assertion in the suite (`worldspawn.collision_shape_type ==
CONCAVE`) so that is caught by a test rather than by a profiler months later.

### 2. The backfill — a tool, measured, not yet run

Fix 1 changes **future imports and nothing on disk**: the committed block
`.tscn` files are what levels instance, and they are not rebuilt unless
somebody re-imports the `.map`.

`tools/collapse_block_collision.gd` (new) rebuilds each block's collision as a
single trimesh from its own mesh — exactly what FuncGodot would have emitted
at CONCAVE. **Dry run by default.**

```
godot --headless --audio-driver Dummy --path . \
    --script res://tools/collapse_block_collision.gd -- [--write] [path or dir]
```

Dry run across all 423 blocks, today:

```
collision shapes: 14,794 -> 436   (340 blocks changed, 97% saved)
feature_trench_revetment.tscn        66 -> 1
```

It left three alone and said why: `ground_spoil`, `prop_dirt_mound` and
`prop_rubble_pile` have collision but no mesh to build a trimesh from. They
look like collision-only volumes, which is correct to skip.

**Nothing has been written.** These are TERRAIN's files and the decision is
TERRAIN's.

### 3. The proper fix, per block — TrenchBroom side

The classic Quake workflow, and the best end state:

- detail brushes into **`func_detail_illusionary`** (zero collision)
- a handful of **`special/clip`** brushes for the collision you actually want

`clip_texture = "special/clip"` is already configured in the map settings and
only **6 of 423** maps use it. A revetment done this way is ~3 clip boxes
rather than one 66-triangle-group trimesh — better than fix 2, because a
trimesh still carries every triangle even though it is one broadphase entry.

Worth doing for the top of the table (`feature_trench_revetment`,
`fort_razor_wire`, the four `estate_*` blocks). Not worth doing for 423 blocks
by hand, which is what fix 2 is for.

---

## Suggested order

1. **Fix 1** — one line, and new blocks are born cheap.
2. **Fix 2 with `--write`** — the existing 423 stop being expensive without
   re-authoring anything.
3. **Fix 3** on the six blocks at the top of the table, as and when they are
   next touched anyway.

After 1 and 2, Salient should go from 45,881 shapes to roughly the number of
instanced blocks — about 1,300. That is the prediction; re-run
`probe_level_cost.gd` to check it rather than taking it on trust.

---

## What to test before trusting it

Two things that cannot be judged headless, and both are real:

- **A trimesh is static-only collision.** Correct for level geometry, wrong if
  a block ever ends up parented to something that moves. Fix 2 only touches
  `StaticBody3D`, but it is worth knowing.
- **Character controllers catch on trimesh edges more than on convexes.**
  `move_and_slide` through a trench is precisely the case where that shows up.
  Somebody needs to walk the Salient trench line before and after.

If fix 2 makes the trenches feel snaggy, fix 3 on the trench blocks is the
answer — clip boxes are convex and do not have the edge problem at all.

---

## Not in scope here, but found on the way

`tools/probe_level_cost.gd` also reports **1,835 `MeshInstance3D`**, of which
**680 are three repeated static meshes** (456 revetments, 117 wire, 107 power
poles). Three `MultiMeshInstance3D` would replace 680 draw calls with 3.

The tradeoff is real though: MultiMesh loses per-instance frustum culling, and
Salient has 940 m sightlines. Worth measuring both ways rather than assuming,
and worth its own brief.

---

## Measured outcome — 2026-10-10, TERRAIN

### Fix 1: done

`addons/func_godot/fgd/worldspawn.tres` is **CONCAVE** (`6fa1d74b`). New blocks
are born with one shape per entity instead of one per brush. No `.map` changed,
nothing visual changed.

Because it is a vendored addon file an upgrade reverts it silently, so
`tools/test_block_collision.gd` now asserts it. That test is the only reason it
would ever be noticed.

### Fix 2: piloted, and REJECTED on its stated grounds

**The performance premise is false.** "45,881 → 1,300 shapes, 97% saved" is a
**count**, and the brief treats it as a proxy for query time. The broadphase is
a tree, so cost is logarithmic in shape count: a 32x reduction is ~1.5x fewer
levels to descend. And the triangles do not vanish — they move from the
broadphase into the trimesh's own internal tree.

`tools/bench_block_collision.gd` (new, keep it) measures the four query
families that actually run, replicated from their call sites, CPU-timed around
the calls only, paced at `Engine.max_fps = 60`. Piloted on Salient,
**45,881 → 1,411 shapes**:

- **Query time changed by nothing.** Six of eight view/family pairs came back
  flat or slower.
- **The melee sphere sweep was 4.5% SLOWER** in both views — the only true
  shape query, and where trimesh narrowphase is dearest.
- **It found 6.6% fewer contacts** near the changed geometry. That is not
  noise, it is physics: **a convex hull is a solid volume and a trimesh is a
  shell.** Ray hit rates were unchanged, which is the control.

**What the collapse does buy, and it is real but different:** static memory
**−83 MB**, instantiate **293 → 162 ms**, nodes **52,312 → 7,842**. Load and
memory, not frame time. If those are wanted they are their own decision, and
they are not free — see the melee regression above.

**The blocks are left uncollapsed.** `--write` has never been run.

### The thing this brief missed, and anyone repeating it must not

**All nine levels set `geometry_parsed_geometry_type = 1`
(`PARSED_GEOMETRY_STATIC_COLLIDERS`). The navmesh is baked FROM the collision
shapes.** Changing collision shape type is therefore a navigation change on
every map, not a physics change. Any future attempt at fix 2 must re-bake and
re-prove all nine, not count shapes.

### Fix 3 and fix 2 are in tension — the guard that now exists

Blocks built with `special/clip` have collision their **mesh does not
describe**: clip brushes are solid and do not render. Rebuilding collision from
the mesh throws them away. `collapse_block_collision.gd` now **skips all six**
(`bridge_damaged`, `fort_checkpoint`, `ground_spoil`, `prop_dirt_mound`,
`prop_jersey_barrier`, `prop_rubble_pile`).

`prop_jersey_barrier` is why it matters: its visible barrier is illusionary and
its **one** collision shape *is* the clip box, so collapsing would have swapped
a deliberate 1-shape volume for a detailed trimesh of the barrier — more
triangles, different shape, hand-authoring undone. **Fix 3 done properly makes
a block permanently ineligible for fix 2.**

### Fix 3: still the right end state

Unaffected by any of the above, and it is the only one of the three that makes
a block genuinely cheap rather than differently shaped. Worth doing on the top
of the table as those blocks are next touched anyway.

### Outstanding, and only the human can settle it

**A trimesh snags `move_and_slide` more than convexes do**, and a 3.0 m trench
with a 1.70 m Walker in it is exactly that case. Never tested. If the memory and
load wins are ever taken, the Salient trench line has to be walked before and
after — and the 6.6% contact loss above says that concern is not theoretical.

---

## Addendum — 2026-10-10, after the pilot reported

### Two claims in this brief are factually wrong and should not be re-used

**1. Near-miss suppression makes no physics query at all.** Line 50 above, and
the headers of `probe_level_cost.gd` and `collapse_block_collision.gd`, all name
it as a per-shot broadphase query and use it to argue the cost is paid "per
query, forever". `AIWeapon.suppress_along` (`Character/weapon/ai_weapon.gd:503`)
walks `AI.SIGNAL_GROUP` with a dot product each. **The sphere query built at
`ai_weapon.gd:135-141` is dead code — it is never passed to `intersect_shape`.**
The real per-shot cost is 4 friendly-fire rays plus one 250 m ray per pellet.

**2. The navmesh dependency is missing** and was not derivable from this brief.
All nine levels bake with `PARSED_GEOMETRY_STATIC_COLLIDERS`. It was piloted and
**came back safe** — individual objective walks moved under 1% and nothing
closed — but it had to be checked, not assumed.

### The pilot's own correction

Its report says the "82.0% in cut" cover baseline could not be reproduced from
any chassis and looks stale. **It is reproducible and it is not stale** — the
frame is `drone`, and `CHASSIS=drone` reads route C at exactly **82.0% in cut**.
The confusion came from an earlier brief calling that frame "player", which is
not a chassis name. Use `drone`.

### The cost the collapse carries, beyond the melee regression

Measured on Salient, and it lands on work this lane had just finished:

- **Bulwark route C is 9 m longer** (184 → 193 m, x1.11 → x1.16).
- **Bulwark and squad route-C in-cut 64.4% → 61.0%**, −3.4 points. The walker is
  unchanged at 60.5%.
- `probe_level_faults` 153 → 155. A threshold artefact — the probe does an AABB
  intersection against a 12 m³ cut-off and two marginal pairs tipped over as
  bounds shifted — but technically worse.

### The better lead, and why it is NOT a one-liner

`ai_weapon.gd:47-49` sets `character_mask = 1|2|4|8` with a comment saying this
"stops every shot from testing terrain geometry". **It does not.** Layer 1 is
`GameWorld`, and every block's `StaticBody3D` sits there — no block in the
project sets `collision_layer`, so they all default to 1.

Dropping GameWorld from the melee mask, measured on the **uncollapsed** level:
**2.388 → 1.090 µs hot, 2.159 → 1.075 µs broad — a 2.0-2.2x speedup**, against
the collapse's zero, with no re-bake of anything.

**But it cannot be done today.** Character bodies do not set `collision_layer`
either (`bulwark.tscn:417` is the only one in the project that sets one at all),
so they are on layer 1 too, and masking out layer 1 would make melee stop
hitting robots. The real finding is **a collision-layer hygiene problem — world
and characters share a layer, so no mask can separate them.** Fixing that is
worth its own brief and is a bigger prize than anything in this one.

---

## Rolled out — 2026-10-10, after the addendum

**Fix 2 is landed.** `--write` has been run; the 338 collapsible blocks on disk
carry one `ConcavePolygonShape3D` each. The pilot's recommendation above was
overridden deliberately, by the human, to play-test the one thing no bench can
answer: whether a trimesh snags `move_and_slide` in a 3.0 m trench. **Every
number the pilot measured is confirmed unchanged** — nothing grew.

```
45cadf7d  blocks: collapse per-brush collision      <- THE REVERT POINT
bb9d17e6  blocks: put back four dropped scene uids
e8bff34d  salient      a32a9397  depot        fae959c4  polaris
a79cd9ca  georgetown   27a39ba3  hillfort     0b10197b  pittsburgh
8d6fdaa4  valley_basin 4ca286f9  heliostat    599516a1  causeway
2c604eb4  test_bridges: footprint from any shape, not only hulls
```

### What the addendum did not know, and the next person must

**There are TWELVE active levels, not nine, and only TEN bake from collision.**
`coastal-road` and `mutaha_wip` leave `geometry_parsed_geometry_type` unset, so
it defaults to `PARSED_GEOMETRY_MESH_INSTANCES` and **their navmesh is baked
from meshes, not colliders** — a collision change cannot move it, and neither
was re-baked. A fresh bake of those two DOES differ from what is committed, but
that is drift from somebody else's terrain work; do not land it under a
collision commit. `causeway` is the tenth collision-baked level and its mesh is
the external `maps/causeway_level_nav.tres`.

**`proving_level.tscn` instances no blocks at all** — its geometry is its own
FuncGodotMap. Its re-bake came back byte-identical, so it has no commit.

**`probe_nav_reach.gd` cannot test causeway**: the level has no `SpawnPoint`, so
the probe bails before walking anything. **`probe_mission_anchors.gd` is the
instrument that works** — it reads the groups the spawner reads and covered all
118 causeway anchors, plus depot, proving and heliostat, none of which keeps an
`Objectives` group the reach probe can find. Use it, not reach alone.

### What moved, and the cheap way to read it

- **`probe_level_faults` rises on every map and it is a bounds artefact.**
  It unions each `CollisionShape3D`'s own AABB per piece, and one trimesh gives
  a looser box than a dozen tight per-brush hulls, so pairs cross its 12 m³
  cut-off without anything moving. Salient 153 → 155, pittsburgh 39 → 50,
  mutaha_wip 71 → 82, coastal-road 4 → 10 — **and the last two had no re-bake
  at all**, which is the proof it is about bounds and not about navmesh. The
  control is the probe's own "two floors in the same place" walk, which is a
  sampled measure: bit-identical before and after on every map.
- **`test_bridges.gd` failed 24 checks and the bridges were fine.** Its
  `_footprint()` tested `is ConvexPolygonShape3D` and skipped everything else.
  Fixed in `2c604eb4`. The same assumption still degrades
  `build_salient.gd`, `build_railhead.gd` and `build_polaris.gd` placement
  guards to bounding boxes, and makes `probe_brush_overlap.gd` report zero
  overlaps forever — none of them is on a gate; all are logged as follow-ups.
- **`test_block_reach` 99 → 105 and `test_block_steps` 96 → 98 pieces.** Real,
  not an artefact, and the mechanism is the one `test_bridges.gd`'s own header
  names: **the baker sees surfaces, not solids.** A trimesh is a shell, so the
  navmesh now bakes on roofs and interior ledges that a solid convex hull
  sealed off. New: `industrial_blast_furnace` (five decks), `mark_stack`,
  `park_overgrown_bed`, `estate_slab_five`, `industrial_plant_office`,
  `wire_belt_run`; and risers on `estate_frame_shell` and `ground_berm_ring`.
  **Read the direction of that number carefully.** `test_block_reach` counts
  decks the squad CANNOT reach, so the six new ones are navmesh ISLANDS, and
  `map_get_path` will not route onto an island — it returns the nearest
  reachable point instead. So this does not let a bot walk up a blast furnace.
  What it does do is give `EnemyForceSpawner` and the cover-point spawner more
  surfaces to SEAT something on, and a garrison seated on a roof island stands
  there for the whole operation. That is the thing to watch, and the symptom to
  watch for is a spawner warning, not a bot climbing a wall.
- **Depot's upper gantries at y=10 and y=17 were already navmesh islands** —
  57.1% coverage before, 42.9% after, two more upstairs samples of fourteen.
  All 36 `SquadMuster` stands are on the ground floor and all 36 reach.
- **`causeway_level_nav.tres` still throws its sync error on load.** The
  re-bake does NOT clear it. Salient throws the same error and always has.

### Fix 3 is now the only thing left worth doing

Unchanged by any of the above and still the only one of the three that makes a
block genuinely cheap instead of differently shaped. The collapse has made the
case for it stronger, not weaker: the six `special/clip` blocks are the only
ones that came out of tonight both cheap AND solid, and the shell-not-solid
consequences listed above are exactly what clip boxes do not have.
