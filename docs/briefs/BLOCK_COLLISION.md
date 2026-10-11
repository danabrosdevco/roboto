# Brief — block collision, and why Salient is slow

Written 2026-10-10 by GAMEPLAY, off a census of every TrenchBroom block in the
project and a runtime count of what Salient actually loads.

Owner: **TERRAIN** (blocks and their use). Status: **not started — nothing has
been written.**

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
