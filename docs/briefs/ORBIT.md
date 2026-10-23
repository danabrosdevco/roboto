# ORBIT — redoing the home base and the departure

Written 2026-10-23 by GAMEPLAY, off one line from the human: *"entirely re-do
the campaign / railhead? the whole train / lever thing sucks. maybe instead
you're in orbit? and launch down from a pod."*

**Status: brief. Nothing is built and nothing is deleted.** Every number below
is read out of the repo rather than estimated.

Sibling briefs, all of which this would supersede in part:
`DEPARTURE_RIDE.md`, `OPS_TABLE_LEVER.md`, `PLATFORM_DOOR_TO_OPS.md`,
`OPS_TABLE_FURNITURE.md`.

---

## 0. What I am taking "the campaign" to mean — correct me here first

**The place you stand between operations, and the ritual of leaving it.** Not
the board: turns, locations, income, garrisons, heat and the 9 → 15 → 19
act structure are `CAMPAIGN_REWORK.md`'s design, most of it is built, and
none of it is what a train is.

If you meant the board as well, say so and this brief is the wrong document —
that one wants rewriting rather than extending.

---

## 1. The fiction already says orbit. The train is the divergence.

`lore.txt`, line 31, on Argus / COMSTAT / Home Command:

> Central command **orbital station** for a pre-STATE advanced military.

And line 33: Argus cares only about "launches of energy and **orbital
machinery** for it to grow its reward centers."

So Home Command — the thing you are an unauthorised process inside — is an
orbital station in the only document that is the world. The armoured train
came from somewhere else entirely, and `tools/block_railhead.gd` says so in
its own header, at line 12:

> THE FICTION decided the plan. A machine intelligence copied a doctrine
> manual and built a headquarters that moves.

That is a good invention. It is not the invention `lore.txt` describes, and
the two have been sitting beside each other since.

**This matters because it changes the argument.** "Put the base in orbit" is
not a new idea to be judged on taste. It is the base rejoining the fiction it
drifted out of, and the pod is what an orbital station already has to have.

---

## 2. What is wrong with the ride, measured

**It is 12.1 seconds, every operation.** `departure_ride.gd`: accelerate 2.5 +
cruise 5.0 + brake 3.0 + doors 1.6. Plus the walk from the table to the lever,
and the walk from the lever to the door.

**And it hides nothing, on purpose.** Its own header, emphasis theirs:

> THE RIDE COVERS NO LOAD, AND THAT IS THE WHOLE POINT. [...] **Nothing here
> loads anything.**

The reasoning is sound — `World.load_next_level` frees the current level
before instantiating the next, so a ride that loaded would be a ride on a
train being deleted underneath you, and getting off first removes the need for
threaded loading, arrival staging and a hidden cut. But the consequence is
that the game spends **twelve seconds of ceremony to avoid a cut**, before
every single operation, for the rest of the campaign.

**It already lies often enough to need a suite.** `test_same_site_ride.gd`
exists because defending a site you are standing at played the full journey:

> ten seconds of tunnel going past the windows and the doors open onto the
> same platform they shut on.

**And two of its seven cars are now empty rooms.** The Armoury car was the
Armorer's, and the Armorer was deleted on 2026-10-22 (step 7b). The
Fabrication car was Tooling's, deleted the same day. Both systems are tabs in
the squad manager now. The train has a room each for two things that no longer
exist, and nothing to put in them.

---

## 3. What the train does that a menu cannot, and that MUST survive

This is the part worth protecting, and it is easy to lose in a rewrite.

`railhead_level.gd` `_post_the_squad()` and `_station_by_size()`: your squad
is physically posted around the base. Infantry go in the barracks racks,
sorted by name so they fill in order; anything whose frame costs two or more
supply goes to a repair bay or a fabrication mount instead, because — their
words — a Reclaimer in a bunk "stands half inside the bedding and reads as a
bug". Twelve robots, and the thirteenth standing in the corridor is a
deliberate, visible prompt that you have run out of beds.

**You walk past your squad.** That is the one thing the base does that the
SQUAD tab cannot, and the orbital station has to keep it or the rewrite is a
downgrade wearing better fiction.

---

## 4. The shape

**A station in orbit, and a pod you ride down.**

**THE BOARD IS BELOW YOU, LITERALLY.** The operations table is currently a
holo slab in a railway carriage. In orbit it is a window — the board is the
ground, seen from the thing that is looking at it, which is what Argus is for
and what COMSTAT means. The mission you pick is a place you can see.

**THE COMMIT IS THE POD, NOT A LEVER.** You board it and it goes. The lever
exists because the table and the door were in different cars and something had
to happen between them; a pod needs no such invention, because getting into a
thing that is about to be fired at a planet is already a commitment and
already a physical act.

**THE DROP IS SHORT AND IT POINTS SOMEWHERE.** The ride's problem is not that
it is a transition, it is that it is a lateral one with no destination in
view: a tunnel wall going past. A drop has an end you can see from the
beginning.

**AND COMING HOME IS THE SAME MOVE.** Extraction is already the bunker, on
every site, since §12.7. The pod goes back up.

---

## 5. The ritual, beat by beat

What it replaces, in order, with the current beat in brackets:

1. **Wake at the window**, looking down at the board. *(wake at the holo
   table in the ops car)*
2. **Choose the operation** on the glass. The ops table survives whole — it is
   1,095 lines and the best screen in the game. *(same)*
3. **Walk to the pod bay, past the squad.** This is the barracks/bay walk, and
   §3 is why it stays. *(walk the rake to the platform car)*
4. **Board.** The hatch is the commit. *(throw the lever at the table, then
   walk to the door)*
5. **Drop.** Short. Seconds, not twelve. *(12.1 s of tunnel)*
6. **Out, onto the site.** *(out, onto the departure pad)*

**THE WALK PAST THE SQUAD IS THE ONE BEAT THAT EARNS ITS TIME** and the one I
would protect at the cost of the others.

---

## 6. What survives, what moves, what dies

| | |
|---|---|
| **Survives whole** | `ops_table.gd` (1,095 lines), `level_exit.gd`'s departure gate, the induction's eight objectives, `_post_the_squad` / `_station_by_size`, the whole campaign board |
| **Moves** | the ops table's housing (carriage → window), the squad's posting furniture (racks and bays → whatever the station has) |
| **Dies** | `departure_lever.gd` (289), `departure_ride.gd` (516), `tunnel_scroll.gdshader`, `test_departure_lever.gd`, `test_same_site_ride.gd` — the last one because the lie it guards against stops existing: you always go down |
| **Becomes set dressing** | the seven cars, `block_railhead.gd` (1,317 lines) and its `.map` files |

**THE RAIL INFRASTRUCTURE ON THE GROUND SHOULD NOT BE DELETED, AND THIS IS A
GIFT RATHER THAN A COST.** `railhead_station.tscn` is instanced by the
Hillfort and Salient maps, and the Salient has an objective tagged
`obj_salient_railhead`. A world where the player used to live on a train and
now does not is a world with abandoned railheads in it — which is exactly the
setting `lore.txt` describes. The cars stop being the home base and become
what the collapse left behind. **Nothing in `maps/blocks/railhead/` needs to
be thrown away.**

---

## 7. The one engineering prize, and its real cost

**A pod can cover a level load. The train provably could not.**

The train could not because it is part of the base level, and
`World.load_next_level` frees that level before instantiating the next. A pod
is a sealed box with no window — the one transition in this game that can
legitimately exist while the world outside it does not.

**THIS IS NOT FREE AND I AM NOT ASSUMING IT.** For the pod to survive the
swap it has to be its own thing rather than a node in the base level, and
`load_next_level` would need to not free it. That is real work in
`world.gd`, and threaded loading may still be needed for the larger maps. The
honest version: **it is a prize worth testing early, not a reason to start.**
Test it in phase 1 and let the answer shape phase 2.

If it works, the drop is not a transition the game pays for. It is the loading
screen, and it is the only one.

---

## 8. What it costs

**71 files** mention the railhead, the lever, the ride or the tunnel shader.
Most are probes and shot tools that go with their subject. The ones with
weight:

- `tools/block_railhead.gd` 1,317 and seven `.map` files — **TERRAIN's**, and
  the single biggest piece. A station is a new build, not an edit.
- `maps/railhead_level.gd` 447 — rewritten against new markers. The marker
  contract is the pattern to keep: nothing here is a typed coordinate, and the
  Polaris objective that was typed ended up inside a wall.
- `Env/world_objects/departure_*.gd` 805 — deleted.
- `Campaign/induction.gd` — the first-visit tutorial is eight objectives set
  at base, two of which were re-aimed yesterday. It is written against rooms.
- Suites: `test_departure_lever`, `test_same_site_ride`, `test_opening`,
  `test_induction`, `test_teams`, plus `probe_home_base` and four shot tools.

**This is a TERRAIN-led job with a GAMEPLAY tail**, which is the opposite of
most work here and worth saying out loud on the board before anybody starts.

---

## 9. Phases, so an interruption lands somewhere shippable

1. **Kill the lever and shorten the ride, in the train.** Two numbers and one
   deletion. Proves how much of the complaint is the ritual and how much is
   the twelve seconds — and that is worth knowing before anybody builds a
   station. **Also: test whether a sealed box survives `load_next_level`.**
2. **The pod, in the train.** Replace the platform car's door with a pod bay.
   Still a train, drops instead of riding. Ugly, and it answers whether the
   drop feels better than the ride without a single new map.
3. **The station.** TERRAIN builds it. The board becomes a window.
4. **The cars become ground.** Re-home `railhead_station` as abandoned
   infrastructure on the maps that already instance it.

**Phase 1 is a day and tells you whether phases 3 and 4 are worth a fortnight.**

---

## 10. Open, and belonging to the human

1. **Is the squad in orbit with you, or on the ground?** §3 says the walk past
   your robots is the best thing the base does. If they are in orbit, the
   station needs a bay deck and the pod carries five. If they are garrisoned
   below and you meet them on site, the walk is gone and something has to
   replace it. **This is the question that shapes the whole station** and I
   have no business guessing it.
2. **Does the drop have a view?** A window makes it a descent and makes the
   place you are going legible. A sealed box makes it a loading screen that
   works (§7). You probably cannot have both.
3. **How long is the drop?** The ride is 12.1 s and that is too long. I would
   start at 3 and let you push it.
4. **What happens when you lose?** The train had you ride home. A pod that
   does not come back is a stronger ending than a train that always arrives,
   and `CAMPAIGN_REWORK.md` already wanted a way to lose.
5. **Does the station get damaged?** Argus is corrupting and Home Command runs
   unattended. A base that degrades over the campaign is free fiction and a
   lot of work; it belongs in this document only if you want it.

---

## 11. What I did not do

I did not touch anything. No file in the repo has changed for this brief, and
the train still works exactly as it did — including the suites that guard it,
which should stay green until somebody decides to start.
