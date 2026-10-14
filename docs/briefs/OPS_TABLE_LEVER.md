# THE DEPARTURE LEVER

For TERRAIN. A small addition to the operations table you already built.

Why it exists: `docs/briefs/DEPARTURE_RIDE.md`. The table and its contract:
`docs/briefs/OPS_TABLE_FURNITURE.md`. Geometry: `tools/block_railhead.gd`
→ `_car_ops`.

---

## 1. What it is for

You queue an operation at the table. Then you commit to it, and the train
takes you there. **The lever is the commit** — a physical throw rather than a
menu, and the last thing you touch before the doors close.

It was put on the table rather than in the motive car on purpose. You commit
where you chose, and the only walk left is the one you have to take anyway:
table to door, with the train already moving around you.

## 2. It CANNOT stand on the table top

I checked before asking, because the obvious reading of "a lever on the
table" is a lever on the slab, and that is the one place it cannot go.

The projection is generated at runtime at `board_size` 5.6 m with a lit plate
of **6.6 × 2.7 m**. Your slab is **7.0 × 3.0**. That leaves 0.20 m of bare
slab at the ends and 0.15 m at the sides, and `TABLE_LIP`'s brass eats 0.04
of it. **0.16 m and 0.11 m of clear surface** — not a footprint for anything.

Everything else inside that rectangle is under the projection, and the
projection draws additively with no depth test, so geometry over it does not
occlude it, it reads as broken. The clear air above `TABLE_TOP` is still the
rule from the furniture brief and still absolute.

So the lever goes **on the table but below the working surface**, bolted to
the end of it.

## 3. Where: the −X head of the table

`_door_furniture(-1.0, 1)` puts the ops car's doorway at −X, and the consist
runs Operations at Godot z = +64 down to Platform at −96 — so −X is the end
of the car you leave through, and everything from the Repair car to the
platform door is that way.

Which means: **you throw the lever facing the way out.** The walk to the door
starts in the same motion as the commit. That is the whole reason for this
end rather than the other one.

The floor is clear there. The well's two mesh-only terraces run out to
X = −4.5 (tops 0.125 and 0.25 m, nothing the baker reads as a step), and the
seating bay does not start until X = +8.25.

## 4. What to build

A **quadrant housing** bolted to the table's −X end, in the family of the
brass lip and the stencilled plate that are already on this table. Issued,
bolted, old. Not a control panel.

| Part | Where |
| --- | --- |
| Housing / quadrant plate | On the plinth's −X end face at X = −3.1, under the slab's 0.4 m overhang |
| Its vertical span | Inside Z 0.12 … 0.89 — the plinth face. Not above 0.89 |
| Projection outward | To about X = −3.9 at most. See §5 |
| The throw slot | A cut or a raised arc in the housing, with a detent notch at each end |
| Designation number | On the **plinth's** end face, not the slab's. See §5 |

Materials: `BRASS` for the housing and the quadrant, `GREEN_P` for anything
structural, `STENCIL` for the number. The table's existing designation plate
is `STENCIL` for a reason — brass and the green panel are within 0.03 of each
other in mean luminance and a brass numeral on a green plinth photographed as
nothing at all.

### Do NOT build the handle

The handle has to move, and FuncGodot welds worldspawn brushes into one
merged mesh, so a handle drawn in the `.map` cannot be animated. It would
also be wiped by the next rebuild — `tools/block_prefabs.gd` builds that
scene from scratch every time, which is why `tools/fit_ops_table.gd` exists
at all.

So the handle is **generated at runtime by GAMEPLAY**, the same way the
holographic board is. You build the thing it comes out of: the housing, the
slot, the detents, the legend. I will extend `fit_ops_table.gd` to seat an
`OpsLeverAnchor` empty and its own Interactible, the same re-appliable way
the table's anchor is seated.

## 5. Three traps, all previously paid for

**The table's interact volume will swallow it.** `fit_ops_table.gd` sizes the
table's Interactible to the slab footprint, 1.4 m tall and centred 0.05 above
the anchor, so it spans **Z 0.30 … 1.70 over the whole 7.0 × 3.0**. An
interact ray is a `RayCast3D` and returns the closest collider, so anything
inside that box is unreachable — F gets the table every time.

The lever's own volume therefore has to live **outboard of X = −3.5**,
clear of the slab footprint. Leave the air from the slab's end face out to
about X = −4.1, from Z 0.3 to 1.7, free of collision geometry. The well
terraces are mesh-only so they already are; just do not put anything solid
there. That gap is a contract, like the clear air above the slab.

**No lettering routine exists.** There is `_digit` and `_number` and nothing
for letters, so the lever is labelled with a number, not the word DEPART.
Which is better fiction anyway: Home Command issues movement-order numbers,
not English verbs.

**And a number below h = 0.5 renders as a solid block.** `_digit` builds each
segment h/8 thick and `solid()` snaps every coordinate to 1/32 m, so below
0.5 the segments snap into each other. At 0.22 it photographed as a
featureless square. The slab's end face is only 0.06 m tall and cannot carry
a legible digit at all — the plinth's end face is 0.77 m and can. Pass
`ax: true` for an X-normal face.

## 6. BUILT SINCE THIS WAS WRITTEN — the pivot is now fixed

The gameplay half is done and in the tree, so two things in §4 changed from
requests into facts. Build to these rather than choosing them.

**The pivot is at X = −3.70, Z = 0.80**, seated by `tools/fit_ops_table.gd` as
`OpsLeverAnchor` and already in `railhead_car_ops.tscn`. Re-running that script
after a rebuild puts it back; it is idempotent. The housing goes AROUND that
point — §4 asked you to tell me the height, and that is no longer open, because
the handle's arc had to be solved against the table's interact volume before it
could be built at all.

**The handle exists and is 0.35 m**, swinging from −20° to −80° about the car's
width axis, so it sweeps X −3.82 to −4.05 at Z 0.86 to 1.13. Your housing needs
to look like something that arc comes out of, and must not occupy it.

**The clearance in §5 is now an enforced invariant**, not a warning:
`tools/test_departure_lever.gd` computes both volumes and the arc from the
constants and fails if they ever touch. If you move the table, run it.

### One thing that is yours and is worth knowing

**Every glass material in the project is opaque.** `glass_dark.tres`,
`glass_window.tres` and `glass_broken.tres` are plain `StandardMaterial3D` with
an albedo texture and no `transparency` set, so nothing outside a window has
ever been visible from inside one — which quietly defeats the reason the cars
have windows at all: *"They exist to show MOVEMENT during a transition."*

It cost a full debugging pass to find, because the tunnel plates were correct,
correctly placed and correctly lit the whole time. `tools/shot_departure_ride.gd`
photographs a flooded plate from inside the car (nothing) and from outside the
hull (a wall of light).

`departure_ride.gd` works around it per-surface at runtime so the ride is
visible today, and does NOT edit your `.tres` — the material is shared by every
glazed thing in the project and whether glass in general should be see-through
is your call, not mine.

## 7. What I still need back

1. The housing on the table's −X end, in the ops car, around the pivot above.
2. Confirmation that nothing solid sits between X = −3.5 and −4.1 at
   Z 0.3 … 1.7, so the lever's Interactible has somewhere to live.
3. A note if the housing had to go anywhere other than the −X end, because
   the lever facing the exit is the point of §3 and I would rather re-plan
   than quietly lose it.
