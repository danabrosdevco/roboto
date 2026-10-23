# ATTACK AND DEFEND — every site, both operations

**Written 2026-10-13, out of the campaign-rework audit.** This is the brief for
turning nine sites with one operation each into nine sites with two.

## The hole this closes

`EnemyTurn.pick_target()` picks any site on the frontier. `play()` can return
`IN_DOUBT` for any of them. The operations table then paints that site CRIT red
and the table's own readout says, in these words:

> UNDER ATTACK
> DEFEND IT

**Only `loc_valley_basin` has a `defend_mission_id`.** For the other eight,
`Campaign.available_missions()` has no defence to offer, the card's DEFEND
button never appears, and the player is told to answer a raid with no way to
answer it. Their only move is to walk away and let `EnemyTurn.settle()` roll it
on paper — which is the *decline* branch presented as the only branch.

So this is not "eight maps are missing content". It is **one promise the game
makes and cannot keep, eight times out of nine.**

## What we learned building the first one

Valley Basin is the only site with both operations. Six things came out of it
that should shape the other eight rather than be rediscovered per map.

### 1. A site is a PLACE. The two operations are things you do to it.

`Location` already carries `mission_id` and `defend_mission_id`, and
`LocationCatalogue.for_mission()` resolves either to the same place. The board
draws one pin per Location and hangs the operations off it. Nothing about a
defence should be a second site.

### 2. The attack and the defence are the SAME GROUND and the same objectives

Both basin missions name the identical four cores. That was not a shortcut — it
is what makes the pair legible: you learn a map by taking it and then you hold
the thing you took. **Do not author a separate objective set for the defence.**

### 3. A defence is not a mission you can choose

`available_missions()` filters defences out *before* it looks at the unlock
ladder or the DEBUG switch, deliberately: a defence exists only while a raid is
in doubt at that site. A defence you could pick at will makes losing ground
impossible — you would simply defend a site nobody was attacking, forever, for
free. **Keep that filter. A new defence is authored, not offered.**

### 4. A defence pays NOTHING

`reward_resources = 0`, `compute_reward = 0`, `repeatable = true`. The stake is
the yield you keep. The basin's suite asserts this and the others should match.

### 5. Garrison strength is sized on COMPUTE, not on what the site is worth

`ForceGenerator.garrison_supply() = GARRISON_BASE (8) + player compute × 1.0`.
Flat with respect to site value, on purpose: if a garrison tracked what a place
paid, the richest sites would be the safest and the territory layer would
invert. The garrison may only field frames and weapons the player has unlocked.
**Garrisons are not player-controlled.**

### 6. The attack is won at the BUNKER, not at an extraction

`SiteOperation`: take the ground, stand down, go home. The defence has no
bunker to take — you already hold everything — so it is won by surviving the
assault pool with at least one core still yours, and lost the moment the last
core goes. One consequence that cost a day: **winning only emitted a signal.**
Nothing sent the player home, and `LevelExit.requires_objectives_complete`
refuses to open while any required objective is outstanding — so an operation
won the intended way, with cores still theirs, walked you to a door that would
not let you through. `Campaign.send_home()` is now the shared path and
`SiteSlice` calls it. **A new site inherits this; do not re-wire it per map.**

## What each of the eight needs

Per site, in dependency order:

1. **A site slice** — a subclass of `site_slice.gd` like `basin_slice.gd`
   (60 lines): marker names and fallback positions for the cores and the
   bunker, and their tiers. This is the prerequisite for everything else;
   see `docs/briefs/archive/SITE_CONVERSION.md`.
2. **`defend_mission_id` on the Location**, pointing at the new mission.
3. **A defence `MissionDefinition`** — `defence = true`, `sim = false`,
   `repeatable = true`, pays nothing, `requires` the site's own attack,
   same `active_objectives` as the attack, same `level_scene`.
4. **`garrison_posts`** — at least three tags the garrison digs in on. Measured
   from the level, not guessed; the basin's first cut chose posts by tag NAME
   and put the garrison 250 m from the fight.
5. **Enemy force, all ADVANCE, entering from THREE OR MORE edges.** A defence
   where the enemy starts on a post is an attack with the labels swapped. Late
   waves need `always_active = true` or culling freezes them.

## The ordering problem, and the answer

A defence cannot exist before its site slice, and a slice is the expensive half.
That suggests doing all eight slices first and all eight defences second — but
that leaves the promise broken for the whole of the slice work.

**Do it site by site, slice then defence, in this order**, which is the order
`§11` ranks them by how well they defend:

| | why |
| --- | --- |
| **Three Rivers** | degree 6, the only other map that is clearly defence-shaped |
| **Hillfort** | the first real site; a raid there is the earliest one a player meets |
| **Coast Road** | adjacent to the basin, so the frontier actually moves |
| **Qamareen · Lockside · The Causeway** | corridors; need a second approach invented |
| **Polaris** | drawn as a hold-out, and `§11` notes it has no anchor tags at all |
| **Trenchline** | 365 supply, the hardest site; last for balance reasons |

**Until a site has its defence, it must not be raidable.** `pick_target()`
should skip any Location with an empty `defend_mission_id` — a one-line guard
that keeps the promise honest while the other eight are built, and that deletes
itself naturally as each lands.

## Done when

- Every Location with ground the player can hold has a `defend_mission_id`
- `pick_target()` cannot choose a site that has no defence
- A raid in doubt always offers a DEFEND you can actually deploy to
- Every defence pays nothing, repeats, and is unavailable unless its site is
  the one under attack
- Every defence's attackers enter from three or more edges and advance

---

## DECIDED 2026-10-14 — every map gets both

An earlier draft of this brief argued two sites out of a defence on shape
grounds. **That was overruled: all nine sites get an attack and a defence.**
The reasoning against is kept here rather than deleted, because it is what the
two defences have to work around rather than something that stopped being true.

### Hillfort — one core, one way up

Its briefing says *"one way on"* and the measurement agrees: a single entry at
the trailhead, one core, no flanks, nothing to cover. A defence here is a queue
unless the attackers arrive from more than one side of the hill.

**So the job is to MAKE it defensible, not to skip it.** `hillfort_slice.gd`
carries three entries — `Hillfort_Trailhead`, `Hillfort_Saddle`,
`Hillfort_Shoulder` — and the last two exist precisely so an assault does not
file up the trail in a line. It is the gentlest defence on the board and the
first one a player will meet, which is the right place for both of those facts.

### Polaris — the map that was already a defence

Polaris is the one site drawn as a hold-out before any of this existed. Its own
briefing: *"Not an advance. You go in, you start the drain, and then you
hold."* The five `pol_wave_*` objectives are a hand-built wave director that
predates `SiteHeat` and does the same job, wired into the attack's win
condition. Two commanders committing reinforcements at the same cores would be
a mess.

**It resolves one way: on a defence, `SiteHeat` owns the map.** The wave
director is authored into `polaris_1_siege`'s objective list and stays there for
the attack. The defence simply does not name those objectives, so
`MissionObjective._ready` frees them and only one commander is ever running.

This is the one map where the generic system replaces something hand-built that
already worked, so it is the one to watch in play.

### What this changes about the guard

The `pick_target()` guard above was written for a world where eight sites had
no answer. Once all nine have one it is dead weight — but **keep it**, as the
thing that catches a tenth site being added without one. It costs a line and it
is the difference between a board that promises a defence it cannot deliver and
one that simply does not raid what it cannot offer.

---

## SPAWNING, 2026-10-15 — measured across every mission

Reported from play on Hillfort: *"enemies spawned within the capture objective
and I couldn't get them."*

### What it was

`DISH-1` standing **on the relay core's plinth** — +0.0, +1.6, +0.4 from the
core, dead centre and 1.6 m up, screened from every approach by the core's own
tower. `DISH-2` likewise inside the footprint.

Every structural test called that clean, and every one of them was right to:
a plinth is a surface, so the body overlaps nothing, has a floor, is on the
navmesh and is not enclosed. **Standing on the furniture is not a collision.**

It happens where an authored garrison post and a slice-built core landed on the
same spot. `obj_hillfort_dish` is exactly where `HillfortSlice` seats
`RelayObjective` — the posts predate the cores by a long way, so the overlap was
nobody's mistake.

`EnemyForceSpawner._on_objective_prop` now rejects any seat whose surface
belongs to a `holdable_core.gd` or a `SiteBunker`, reusing the outward search
`_settle_clear` already had. Hillfort's two moved from +0.0/+1.6 to +3.2/+1.1 —
off the plinth, on the ground, and visible from the approach.

### The audit was wrong about 36 of the 39 it flagged

`spawn_geometry_audit.gd` reported 39 bodies BURIED across eight missions.
Every row named the terrain itself with the navmesh 0.0 m away, which is the
shape of a broken test rather than a broken map: it placed its probe capsule at
the body's **origin** and ignored the `CollisionShape3D`'s own offset, so the
few chassis that author an offset capsule read as buried in the floor they were
standing on. `tools/probe_spawn_sink.gd` measures the difference.

Fixed, plus a second false positive — a Bulwark's `ShieldBlocker` is a
StaticBody on its arm, so a body behind a shield read as buried in the level.

**Now: 2 bad bodies out of 2,166, in 21 missions.** Both are authored posts
with no clear seat within 13 m, and both belong to whoever owns the level:

| | | |
| --- | --- | --- |
| `causeway_1_tower` | EXPANSION-3 | (10, 5.0, 0) — post `obj_cway_deck_mid` |
| `salient_1_overthetop` | PRILIV-2 | (191, 1.0, 3) — post `obj_salient_support` |

### Two new categories in the audit

**ON OBJECTIVE** — standing on a core's plinth or the bunker's roof. Mirrors
the spawner's own rule deliberately; the two have to agree or one is lying.

**ENCLOSED** — walled within 2 m in all twelve horizontal directions. Nothing
on any map trips it.

### THE NAVMESH DOES NOT NEED REBAKING

Asked directly, and measured rather than assumed. `tools/probe_nav_vs_art.gd`
samples nine points across every slice-built solid on every map and asks
whether any walkable navmesh sits inside it. **None does.** The cores and the
bunker entrances went in after the last bake, but they landed on ground the
bake had already treated as blocked or had never covered.

The one thing it flagged on all eight maps was the bunker's own `Interactible`
— an Area3D on layer 3 whose entire job is to sit on walkable ground so the
player can stand in it and press F. Walkable navmesh inside *that* is the
feature, and the probe now skips anything owned by an Area3D.

The depot is excluded on purpose: only the player moves at base, so it carries
no navmesh and needs none.
