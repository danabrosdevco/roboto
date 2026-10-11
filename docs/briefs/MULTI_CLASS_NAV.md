# BRIEF — two navigation classes, as a spike you can watch

Written 2026-10-11 by TERRAIN. Owner: **TERRAIN**. Status: **not started.**

**This is a spike on ONE map, not a rollout.** The point is to put the
behaviour in front of the human — a Bulwark declining a gap a soldier walks
straight through — cheaply enough that a thumbs-down costs nothing.

---

## 1. The problem, measured

Godot's `map_get_path` **takes no agent radius**. Whatever is baked into a
NavigationMesh is the only clearance the engine will ever enforce, so one mesh
serves every body on the map. Our bodies are not one size:

| frame | width | height |
|---|---|---|
| player drone | 0.50 | 1.70 |
| soldier frames (all) | 1.00 | 2.00 |
| reclaimer | 1.50 | 0.80 |
| rover | 1.70 | 1.70 (3.40 long) |
| walker | 1.70 | **3.00** |
| bulwark | **2.26** across the shield | 2.82 |

The visible symptom, and the reason this brief exists: on `mutaha_wip_level`
the bridges' parapets are **1.0 m above the deck and 1.0 m wide on top**, and
the level bakes at `agent_radius = 0.4`. Erosion leaves a **0.2 m ribbon** of
navmesh along the parapet, the pathfinder routes the squad onto it, and
1.70–2.26 m bodies jam on a ledge a fifth of their width.

It is not a Qamareen bug. Radius across the project is **0.4, 0.5, 0.6 and
1.0**, with three levels falling through to Godot's 0.5 default — see the table
in `docs/reports/TERRAIN.md`. Every map except salient describes routes for a
body 0.8–1.2 m wide.

---

## 2. What other engines do, and which of it we can have

- **One navmesh per agent class** — Unreal's `SupportedAgents`, Unity's Agent
  Types. Bake N meshes from the same geometry; each unit queries only its own.
  **Natively available in Godot**, and this is what the spike builds.
- **Clearance-based pathfinding** — one mesh, per-polygon distance-to-border,
  filter at query time. Cheapest at runtime. **Not available**: no radius on
  the query, no clearance field exposed.
- **Separate route graphs** — authored roads for vehicles, navmesh for
  infantry. **We already do this in level design and the nav does not know**:
  salient's route A is an 8.0 m sunken road, route C a 3.0 m infantry trench.
- **Annotated chokepoints** — tag a passage with a max size. Scales badly.

---

## 3. The two classes

Two, not six. Radius is **ceiled to whole `cell_size` units**, so at 0.25 both
0.85 and 0.95 bake identically at 1.0 — finer classes buy nothing.

| class | frames | radius | height |
|---|---|---|---|
| `light` | drone, all soldier frames | 0.5 | 2.0 |
| `heavy` | reclaimer, rover, walker, bulwark | 1.25 | 3.0 |

1.25 because the Bulwark's 1.13 ceils to it at `cell_size` 0.25.

---

## 4. Scope — `mutaha_wip_level` only

That is where the human saw it and where the parapet makes the difference
legible. **Do not touch any other level.** Do not change the shipped
`agent_radius` on anything — the spike adds a second mesh, it does not re-bake
the first.

### Do NOT edit the chassis scenes

`Character/` is another lane's. You do **not** need it: every navigation query
in the codebase already goes through `nav_agent.get_navigation_map()` —
`enemy.gd` in eight places, `drayman.gd` in two — so an agent follows whatever
map it is pointed at.

Point them from **one node placed in the level**: on ready, walk the AI bodies,
look each one up by frame name, and call `set_navigation_map()` on its
`NavigationAgent3D`. Zero edits outside your own files, and the whole spike
reverts by deleting that node.

---

## 5. Three deliverables, in this order

### (a) Headless proof — it must be true before it is pretty

A probe that bakes both classes and, for a list of (from, to) pairs across a
bridge, prints the path on each map. The result that matters:

```
bridge_N  light  path 48 m  via deck
bridge_N  heavy  path 48 m  via deck      <- NOT via the parapet
```

Also print, per class: polygon count, and **whether any navmesh survives on the
parapet top**. The heavy mesh should have none — 1.25 m of erosion per side
deletes a 1.0 m ledge outright.

### (b) Visual proof — the thing the human actually asked for

Render the two navmeshes as coloured overlays on the bridge, from a camera that
shows the parapet. Build a `MeshInstance3D` from each baked mesh's own vertices
and polygons and draw it over the level — light in one colour, heavy in
another. **One frame where the light mesh runs along the parapet and the heavy
mesh stops at the deck edge is the entire deliverable.**

Shoot it **through the signal filter** at the real **1.50 m** eye — uniforms
live in `Character/hud/hud.tscn`, not in the shader's defaults. A render
without the filter is not a picture of this game.

### (c) Playable — so they can watch it

The level loads, chassis get their class's map, and a Bulwark ordered across a
bridge takes the deck while soldiers may take the parapet. Say in your report
exactly what to order and from where, so it can be reproduced in one minute.

---

## 6. The API, and three traps

Verify the surface exists in 4.3 before building on it: `NavigationServer3D
.map_create / map_set_active / map_set_cell_size / map_set_up`,
`NavigationRegion3D.set_navigation_map()`, `NavigationAgent3D
.set_navigation_map()`.

1. **The maps must agree on `cell_size` with what their regions baked**, or
   Godot throws the "merge a navigation mesh polygon edge with another
   already-merged edge" sync error on load. `trench_broom_level.gd` syncs
   `cell_size` and nothing else — read it before you create a second map.
2. **`agent_radius` is ceiled to `cell_size` units; `agent_max_climb` is
   floored to `cell_height` units.** `mutaha_wip` bakes at `cell_size 0.5`, so
   1.25 may land somewhere you did not intend. Print what you actually got
   rather than what you set.
3. **`mutaha_wip` has no `geometry_parsed_geometry_type`**, so it defaults to
   `PARSED_GEOMETRY_MESH_INSTANCES` — it bakes from MESHES, not colliders,
   unlike most of the project. Decorative geometry contributes. Do not
   "correct" this during the spike; it changes what the existing mesh is and
   confuses the comparison.

Also: `agent_max_climb` is unset on this level, so it is **0.9 m** — twice the
bodies' `step_height` of 0.45. That is a second, separate cause of jamming.
**Note it, do not fix it here**; one variable at a time or the spike proves
nothing.

---

## 7. The open question this spike will force, which is the human's

Two classes mean a soldier can reach somewhere a Bulwark cannot. **The squad
moves as a squad.** When half can follow an order and half cannot, the options
are split, refuse, or send the heavies the long way round — and that is a
gameplay decision, not a navigation one.

**Do not implement any of them.** Make the spike surface the case clearly —
print or log when a squad order is unreachable for a subset of frames — and
put the question in your report.

---

## 8. Rules

Do not create or switch branches; three lanes share this checkout. Stage paths
explicitly and commit through a throwaway index. Leave every file you did not
change alone — `tools/shot_ops_table.gd` and `tools/probe_detail_width.gd` are
another lane's in-flight work. Use the `_console.exe` for headless runs; the
plain `.exe` detaches and prints nothing, so a failure looks like a pass.
**Python is not installed.**

## 9. Done means

- `check.sh --changed` PASS, `smoke.sh` PASS
- the headless comparison, with polygon counts and the parapet result per class
- the overlay frames, shot through the filter
- one paragraph saying what to order in-game to watch it
- costs measured, not assumed: bake time and memory for the second mesh, and
  `map_get_closest_point` timing per class. The expectation to test is that
  **per-query cost does not rise** — each agent queries one map, and the heavy
  mesh is far simpler — so this should be a memory and bake-time cost only.
- a one-line revert recipe

## 10. Report back

Whether the heavy class actually refuses the parapet, the measured costs, what
you had to touch outside your own files (ideally nothing), and the squad-order
question from section 7 stated plainly for the human to decide.
