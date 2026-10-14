# THE DEPARTURE RIDE — concept

How the train takes you to the operation, instead of the screen cutting to it.

**BUILT, 2026-10-11.** This was the concept; the gameplay half now exists and
runs. `Env/world_objects/departure_lever.gd`, `departure_ride.gd`,
`tunnel_scroll.gdshader`, the `requires_arming` gate on
`Env/world_objects/level_exit.gd`, and the two anchors
`tools/fit_ops_table.gd` seats. Proven on a real boot by
`tools/probe_home_base.gd` and photographed by `tools/shot_departure_ride.gd`.

Still outstanding: the lever's housing, which is TERRAIN's —
`docs/briefs/OPS_TABLE_LEVER.md`. And no audio, and no camera sway (§4): the
sway means fighting the player script for its own rotation, and it is the one
part of this nobody can judge without taking the controls.

Sibling briefs: `docs/briefs/OPERATIONS_TABLE.md`,
`docs/briefs/OPS_TABLE_FURNITURE.md`.

---

## 1. Most of this already exists, and it was built on purpose

`tools/block_railhead.gd`, on the car shell:

> **WINDOWS.** Eight apertures a side, 2.0 m wide on a 4.0 m pitch, between
> 1.25 m and 3.0 m above the floor. **They exist to show MOVEMENT during a
> transition**, so they are regular: a passing backdrop reads as motion
> across eight openings and as a porthole across one.

So the train already has:

- **Eight windows a side**, deliberately rhythmic, with a rule that nothing
  tall may stand across one.
- **A tunnel wall** — a backdrop plate 20 m out on each side
  (`BACKDROP_Y`), with `Backdrop_Left` / `Backdrop_Right` markers.
- **A door that opens** — `PlatformDoor_LeafClosed` and
  `PlatformDoor_LeafOpen` markers, 3.25 m clear.
- **21 tungsten lamps** on the same 4 m module as the windows.
- **The departure pad already outside that door**, at
  `PlatformDoor_Outside`.

The art is waiting for the sequence.

## 2. The beats

1. **Queue an operation** at the table. The ring appears. *(built)*
2. **Pull the lever.** A physical act, not a menu. This is the commit.
3. **The doors close.** Lamps drop to a running state: dimmer, cooler, the
   tungsten warmth gone out of them.
4. **The tunnel starts moving** past the windows. Slow, then quick.
5. **The ride.** Eight to twelve seconds of light strobing across the eight
   apertures, a low rumble, the faintest sway.
6. **Deceleration.** The strobe slows to individual lights passing, then one
   stops level with a window and sits there.
7. **The doors open.**
8. **You walk out** onto the platform and onto the departure pad. *The level
   loads there, exactly as it does today.*

## 3. THE RIDE COVERS NOTHING, AND THAT IS THE WHOLE TRICK

The obvious way to build this is to load the destination during the ride.
That way is much worse, and it was the first thing I reached for.

Loading destroys the train — `World.load_next_level` frees the current level
before instantiating the next — so a ride that covers a load means riding a
train that is being deleted underneath you. It forces threaded loading,
arrival staging in every mission, and a cut hidden inside a door animation.

**Getting off the train first removes all of it.** The ride happens entirely
inside the railhead level. Nothing loads, nothing is freed, nothing is
covered. Then you step out of a door onto a pad that already works, and the
load happens there, the way it has always happened.

What this costs: nothing. What it buys:

- **No threaded loading required.** Nice to have — see §6 — not needed.
- **No per-level arrival staging.** Missions start where they already start.
- **`World` and `Campaign` are untouched.** `begin_deploy()`, the
  requisition refusal, the destination push: all unchanged.
- **The hitch lands where hitches are forgiven** — on a loading transition
  the player just triggered by walking through a door, not in the middle of
  a moving shot.

## 4. How the motion is faked — no moving geometry

**Nothing in the train moves.** Moving it would mean moving the player, the
squad and the physics with it.

- **The tunnel scrolls.** A shader on the backdrop plates with a repeating
  tunnel-light stripe, speed on one uniform. Ramp up, hold, ramp down, and
  that is the ride.
- **The lamps answer it.** The 21 interior lamps flicker on the same clock,
  so light sweeps along the car in step with what passes the windows. This
  is what sells it: the inside reacting to the outside.
- **A sway, not a shake.** A couple of centimetres of camera roll on a slow
  sine, with a judder at the start and the stop.
- **Sound carries half of it.** Rumble, rail joints on a rhythm matched to
  the stripe, brakes at the end.

One shader, one curve, one audio bus. No geometry, no navmesh, no physics.

## 5. The door is the gate

The one piece of real logic. The door is **shut by default**, and the pad
outside it is unreachable until the train has arrived.

That single rule does a lot of work:

- You cannot leave without travelling, so the ride is never skippable
  scenery — it is the way out.
- Queueing an operation and committing to it become two separate acts, in
  two different cars, which is the difference between choosing and going.
- Coming home, the door is shut again and the train is somewhere else. The
  base is wherever the train is, which is the thing the whole fiction is
  built on.

`LevelExit` already has the machinery: `live_parts` and `_refresh_live()`
dim the pad's chevrons and beacons until it is usable. It currently lights
when a mission is queued. It should light **when the train arrives.**

## 6. What it costs, in order

**v1 — the ride.** Lever, door animation, backdrop shader, lamp clock, sway,
audio, and the pad gated on arrival. End to end, no changes outside the
railhead level.

**v2 — hide the hitch.** Kick off `ResourceLoader.load_threaded_request` for
the queued mission when the lever is pulled. By the time you have ridden and
walked to the door the level is in memory and the pad is instant. Purely an
optimisation now, rather than the load-bearing requirement it would have
been.

## 7. Who builds what

- **Lever, sequence, shader, lamp clock, door gate, timing** — GAMEPLAY.
- **The lever as an object, the door leaves, the tunnel plate's material** —
  TERRAIN. Small: the markers are already there.

## 8. Decided: the lever is on the table

Not in the motive car. You commit where you chose, and the only walk left is
the one you have to take anyway — table to door, with the train already
moving around you. That turns the dead time into the ride rather than adding
to it.

It sits at the table's exit end, so the throw and the walk out are the same
motion. Brief for TERRAIN: `docs/briefs/OPS_TABLE_LEVER.md`.

## 9. What the ride is really for

It is the only point in the loop where the player is captive, moving, and
has nothing to do — so it is the one place **Home Command can talk to you**
with nothing competing for attention.

A tasking confirmation read out to a mesh that is not there. A manifest for
a unit that does not exist. Eight seconds of an institution addressing an
agent it has never once queried.

That is worth more than the travel.
