# OPS TABLE — THE FURNITURE

For TERRAIN. The projection and all its behaviour are built and working; what
is missing is the thing it stands on.

Design brief for the whole feature: `docs/briefs/archive/OPERATIONS_TABLE.md`.
Code: `Env/world_objects/ops_table.gd`, `holo_board.gd`, `site_icons.gd`.

---

## 1. What exists already

A working holographic campaign board. Twelve sites drawn as line-art
landmarks — the relay dish, the tether anchor, the ferris wheel, the horned
tower — joined by dotted borders, each wearing three gauges. Press F and you
go into a zoomed view with a mouse.

All of that is code and needs nothing from you. **What it has no idea about
is what it is sitting on.** Right now it floats in mid-air wherever the test
harness puts it.

## 2. What to build

**A Home Command issue operations table, in the ops car.**

Institutional, stencilled, built to a standard, and old. It was requisitioned
and bolted down by an organisation that has a form for everything; nothing
about it was chosen, it was issued. See `docs/briefs/` for the Home Command
material.

The one thing it must NOT look like is new.

## 3. The numbers that matter

The projection is generated at runtime and sized in metres. These are the
real figures, from the code, not estimates.

| What | Size |
| --- | --- |
| Board, corner to corner | **1.10 m** |
| Plate (the lit grid under it) | **1.38 m** (1.25× the board) |
| Projection floats above the node origin | 0.04 m |
| Tallest landmark (the Causeway tower) | **0.165 m** |
| Readout strip, in the board's near margin | about 0.33 × 0.20 m |

So: **a top surface at least 1.5 m × 1.1 m, and 0.25 m of clear air above
it.** Nothing may overhang the surface — no lamp, no hood, no raised rim
above 30 mm. The projection is drawn additively with no depth testing
against the room, so anything over it does not occlude it, it just looks
wrong.

**Working height 0.95 m**, standard for a table somebody stands at. Not a
desk — nobody sits at this.

## 4. Where the anchor goes

Put an empty at **the centre of the top surface**. That is where the
`OpsTable` node is placed and everything is generated from it. Name it
`OpsTableAnchor` or tell me what you called it.

## 5. The Interactible

The table needs an `Interactible` child — an instance of
`Env/world_objects/components/template_interactible.tscn` — or F does
nothing. Three gotchas, all previously learned the hard way:

- **Size its Area3D to the table's footprint and no bigger.** The player's
  interact raycast is 2 m and does not register from *inside* a volume, so
  an oversized box means the prompt vanishes as you walk up to it.
- **`box = box.duplicate()` before resizing.** A shape authored in a scene is
  one shared resource; resize it in place and every other instance of that
  prefab changes with it.
- Leave `destroy_on_use` and `disable_on_use` alone — the script clears both
  on ready. A table you can only use once is not a table.

## 6. What it should have on it

Suggestions, not requirements — your call entirely:

- A stencilled plate or decal with a unit designation and an issue number.
  Home Command labels everything.
- Cable runs going INTO the table from the floor or the car wall. The thing
  draws power from somewhere and the projector is in the plinth.
- Wear where hands go: the long edges, the corners.
- A rail or lip at 30 mm or less to stop things sliding off a moving train —
  which is a nice detail, since the car is one.

Things to avoid:

- No screens, no monitors, no keyboards. The projection IS the display.
- No chairs.
- Nothing above the surface. See section 3.

## 7. Where it goes

`maps/blocks/railhead/railhead_car_ops.tscn`, which is yours.

**It cannot be reached yet.** `maps/railhead_art.tscn` has zero interactibles
and zero spawn points, and `world.tscn` still loads `maps/depot_level.tscn`.
Until the railhead is wired as the playable base, the table has no way in.

So, so that this is testable in the meantime, I will drop a second instance
in the depot. That is temporary and comes out when the ops car is live — it
is not a second table in the fiction.

## 8. What I need back

1. The ops car with the table in it, and the anchor empty on its top surface.
2. The name you gave that empty.
3. A note if the working height has to change — the camera for the zoomed
   view is positioned relative to the board and I will retune it.

Nothing else. The projection does not care what the table looks like, which
is the point of giving it to you.
