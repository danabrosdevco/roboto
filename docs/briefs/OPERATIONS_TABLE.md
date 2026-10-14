# OPERATIONS TABLE

Home Command's tasking board, in the ops car of the train. It replaces the
mission terminal as the way you choose where to go — and it is the first
object in the game that talks to you as though you were a real agent of
theirs.

Status: brief. Nothing built yet.

---

## 1. What it replaces, and what must not move

The mission terminal's entire contract is four lines. Everything else about it
is presentation, and all of that is up for replacement.

- It writes exactly one thing: `Campaign.selected_mission_id`.
- **Selection is not departure.** `MissionExit` reads the selection when you
  walk onto the pad. The two are deliberately separate so you can change your
  mind without being teleported. This stays.
- It is driven by an `Interactible` — the F prompt — into `_on_interacted`.
- It refreshes on `returned_to_base` and `state_loaded`, and reads
  `available_missions()`, lock reasons and clear counts.

**The terminal itself stays where it is for now.** The table is additional,
not a deletion. Both can set the same field; last one pressed wins, which is
already how two terminals behave.

---

## 2. The fiction

The table is Home Command issue. Institutional, stencilled, built to a
standard, and old.

Home Command was the military of a country. Argus was a programme instituted
to oversee it — named the way APOLLO was named — and Argus' core is in orbit.
Argus stopped supervising a long time ago. Home Command did not stop.

**The name is the joke and nobody in the fiction is in on it.** There is no
home left to command. The institution kept its letterhead.

Home Command believes you are one of its agents. Not a favoured one, not a
suspicious one — just another node on the tasking mesh, indistinguishable
from the others it thinks it is coordinating. It tasks you the way it tasks
everything: take sites that produce compute or materiel, then hold them.

### It cannot fathom that you are not networked

This is the seam the whole piece hangs off, and it should be **mechanical,
not flavour text**. Home Command reports sync as healthy because it is
reporting *its own* link, not yours. The table is confident, institutional,
and talking past you.

Three consequences worth building:

- **The briefing does not travel.** Home Command pushes the operation package
  to your mesh. Nothing arrives, because there is no mesh. Whatever you want
  to know about an op, you read off the table and carry in your head.
- **The estimates are stale and the table does not know it.** Resistance
  figures are current as of last sync. For you, last sync was never. The
  table presents them with full confidence.
- **There are other agents on this board who do not exist.** Columns,
  adjacent taskings, neighbouring assignments — all empty, or filled with
  something that has not updated in a very long time.

None of this is ever explained. The player works out that the confident
machine is wrong about them.

---

## 3. The object

A holographic, digitally constructed projection above a Home Command issue
table, in the ops car.

Not a relief model of real ground — an **abstraction**. Nodes and
connections, the way a command system would draw a theatre it has never
walked.

Palette is already written: `HUDPalette.FAC_SWARM` amber, `FAC_HOME`
institutional green, `FAC_ARGUS` tyrian, `FAC_UNKNOWN` grey.

---

## 4. The board

- **Nodes** are sites. One per operation.
- **Colour is control.** Who holds it, read at a glance, from the faction
  palette above.
- **Dotted lines** connect sites to the sites they lead to.

Four states have to be legible without hovering: available, locked, cleared,
and currently selected. The terminal did this with three text colours; the
table has position, height, light and line weight to spend instead.

---

## 5. Interaction

Walk up, press F, and you go into a zoomed view of the same board the table
is projecting. Hover, click, select. The physical projection on the table
responds to what you do in that view — it is the same board at two scales,
not two displays.

This is the pattern `SquadManagerUI` already uses (`PauseHold`, a full-rect
Control, `release_pending` on close). Reuse that plumbing rather than
inventing a second one.

---

## 6. The hover readout

Hovering a node shows:

| Line | Source |
| --- | --- |
| Compute | `MissionDefinition.compute_reward` |
| Resources per turn | `MissionDefinition.reward_resources` |
| Expected resistance | `enemy_force` — each spec's `count` against its roster's chassis `supply` |

All three presented as fact by a system that has not had an update from the
field in a very long time.

---

## 7. v1, and what comes later

**v1 is choosing an operation.** The board replaces the terminal's job and
nothing more. It writes `selected_mission_id`; you still walk to the pad to
leave.

**Later:** territories hold compute and resources and pay out per turn. Each
turn the enemy may attack something you hold, and you choose between
defending it and pushing on somewhere else.

The v1 board should be shaped so that arrives as **more data on the same
nodes**, not as a rebuild. In practice: node and edge rendering driven off a
data layer, not hard-coded per mission.

---

## 8. Data that already exists

More than expected. The graph can be drawn today with no new fields.

| What the board needs | Where it already lives |
| --- | --- |
| Node position | `MissionDefinition.map_position` |
| Dotted lines | `MissionDefinition.requires` — populated with real chains |
| Compute yield | `MissionDefinition.compute_reward` |
| Resources | `MissionDefinition.reward_resources` |
| Expected resistance | `enemy_force` × chassis `supply` |
| Locked / cleared / available | `available_missions()`, lock reasons, clear counts |

Real chains already in the data: `arena_1_contact → arena_3_firing_line`,
`hillfort_1_relay`, `polaris_1_siege`, `basin_1_anchor`.

---

## 9. Open problems

**The ops car is not reachable.** `maps/railhead_art.tscn` has zero
interactibles and zero spawn points. The train is art; `maps/depot_level.tscn`
is still what `world.tscn` loads. A table built only into the ops car cannot
be walked up to until TERRAIN wires the railhead as home.

> Proposed: build it as a prefab, make the ops car its real home, and place a
> second instance in the depot purely so the interaction can be used and
> judged in the meantime.

**`map_position` is inconsistent.** Most missions carry real coordinates,
four sit at `(0,0)`, and one is `(0.62, 0.38)` — normalised while the rest
are not. The board needs a deliberate layout pass before it reads as a map,
and that is a judgement about where places are relative to each other.

**`requires` is a tech tree, not a geography.** It gives real edges, but they
encode unlock order rather than adjacency. Good enough to draw v1; they will
diverge the moment territory becomes a thing.

---

## 10. Who builds what

- **The projection, the board, the zoomed view, the data** — GAMEPLAY. It is
  shader and UI work.
- **The table housing**, if it wants to be real geometry rather than a
  blockout — TERRAIN, in TrenchBroom, once the shape has stopped moving.

**First deliverable:** a working board with a blockout table — real nodes,
real edges, real hover data, the zoomed view — so the interaction can be
judged before anyone sculpts anything.

### Done looks like

- Walk into the ops car (or the depot stand-in), press F, see the board.
- Every available operation is a node, in the right place, in the right
  colour, with its prerequisites drawn.
- Hover any node and read compute, resources and expected resistance.
- Select one, leave the view, walk to the pad, and deploy to it.
- The terminal still works and still agrees with the table.
