# Teaching the AI to use smoke, drones and mines

Four items a player can buy, fit to a squadmate, and then watch never be used:
`smoke`, `drone_pack`, `mine_cluster`, `mine_heavy`. All four are
`usable_by_ai = false` with no `ai_scene` at all — fittable by you, never by a
robot.

This is the plan for each, and the shared work that has to happen first.

---

## What exists already

`AIEquipment` is a small, good contract:

```gdscript
class EquipmentContext:
    var owner_ai: Enemy
    var combat_target: CharacterBody3D
    var target_position: Vector3
    var nearby_hostiles: Array          # within 5 m of the OWNER
    var time_since_target_moved: float
    var owner_is_reloading: bool

func can_use(context) -> bool            # may I, right now?
func execute(context) -> void            # do it
@export var cooldown: float
```

`Enemy._evaluate_equipment_use()` runs on a recon timer, walks the fitted
slots, instantiates each one's scene, asks `can_use()`, and the first one that
says yes gets `execute()` and is consumed. Adding an item is therefore: subclass,
scene, set `ai_scene` on the `.tres`, flip `usable_by_ai`.

Only two subclasses exist — `ai_grenade.gd` and `ai_repair_kit.gd`. EMP and
Hatchling are the grenade scene with a different projectile swapped in, which is
why an EMP gets thrown at a lone stationary target exactly as a frag would.

## THE BLOCKER — read this before planning any of the four

```gdscript
func _evaluate_equipment_use() -> void:
    if combat_target == null:
        return
```

**Equipment is only ever considered when the robot already has someone to
shoot.** That is fine for a frag. It makes three of our four items impossible:

- mines are laid *before* contact, or while breaking it
- smoke is for when you want to STOP being in a firefight
- the drone pack is for a target you cannot currently engage

So the first piece of work is not any of the four items. It is widening the
context and the gate.

### Context additions needed

| field | why |
|---|---|
| `squad_objective` | DEFEND / FALLBACK / ADVANCE — the single biggest signal for mines and smoke |
| `under_fire_seconds` | taking hits with no target, which is exactly when smoke is wanted |
| `downed_friendly_nearby` | screen a casualty so the mechanic can work |
| `threat_bearing` | a direction to put smoke or mines *between* us and them, rather than on our feet |
| `hostiles_near_target` | the current `nearby_hostiles` is a 5 m ring around the OWNER; clustering decisions need it around the TARGET |
| `recent_equipment_by_squad` | so four soldiers do not all smoke the same corner on the same frame |

That last one matters more than it looks. Every item below is rationed (2 per
mission) and a squad has no shared memory of what it just spent.

---

## 1. Smoke Canister — 7 m, 14 s, blocks sight not bullets

**What it is for:** leaving a fight, not winning one. The suite confirms rounds
pass straight through, so this never buys protection — only time.

**The gate that matters is negative.** Smoke blinds US too. A robot that smokes
a fight it is winning has thrown the fight away. So:

```
can_use when ALL of:
  we are NOT winning this exchange      (taking damage faster than dealing it,
                                         or outnumbered within ~20 m)
  AND one of:
    squad objective is FALLBACK/REPOSITION and we are under fire
    a squadmate is DOWNED within ~12 m and the area is under fire
    we are ordered across open ground with no cover and are being hit
```

**Placement:** not at our feet and not on the enemy — on the line between, at
roughly 60% of the way toward the threat. That puts the cloud closer to them, so
it covers more of our arc than theirs, and leaves us able to back out of it.

**Cooldown:** long. Two per mission means the second one must still exist when
the squad actually needs to disengage.

**Risk to watch:** a squad that smokes every time it takes a hit will spend both
canisters in the first thirty seconds and look panicky. The "not winning" gate is
what stops that, and it is the part to tune first.

## 2. Drone Carrier Pack — 2 Divers, 50 hull, 90 m sensor

**What it is for:** killing something the squad cannot reach. The Diver already
self-targets — it climbs and picks the most expensive frame it can see — so the
AI decision is only *when* and *roughly where*, not *at what*.

```
can_use when ALL of:
  a high-value hostile is known to the squad   (supply >= 2: walker, rover,
                                                reclaimer — not a rifleman)
  AND we cannot deal with it ourselves         (beyond our max_effective_range,
                                                or no line of sight to it)
  AND it is within the Divers' reach           (~90 m, their sensor range)
```

**Placement:** toward the high-value target, so the Divers come out with it
already inside their sensor radius.

**The known hazard:** "most expensive frame it can see" is the Diver's rule, not
ours. Thrown short, a Diver may top out over a cheap rifleman and spend 60
resources on it. The targeting is not ours to change here, so the `can_use`
distance check is doing double duty — it is also what makes the Divers find the
right thing.

**Cooldown:** very long. This is the squad's answer to armour; spending it on
the wrong frame is worse than not spending it.

## 3. Cluster Mine — 5 submines, 45 dmg, 2 m blast, **45 s lifetime**

**That 45-second lifetime is the whole design.** It is not fortification, it is a
tactical denial tool with an expiry, so it should be laid when contact is
*imminent or happening*, never speculatively.

```
can_use when one of:
  withdrawing under contact            — lay it on the ground we are giving up
  holding, and hostiles are closing    — lay it on their approach, 8-15 m out
```

**Placement:** between us and the threat bearing, or directly behind us when
falling back. Never within our own trigger radius of where the squad is standing.

**The classic use is the withdrawal**, and it is the one worth building first:
a squad that mines the ground behind it as it pulls back reads as competent in a
way almost nothing else does.

## 4. Heavy Mine — 160 dmg, 4.5 m blast, **permanent**

**Permanent and lethal — this one is fortification.** 160 damage kills most
things in the game outright.

```
can_use when ALL of:
  squad objective is DEFEND / HOLD
  AND a chokepoint exists on the approach   (narrow navigable width, a doorway,
                                             a bridge mouth)
  AND no friendly mine is already within ~8 m   (do not stack)
```

**This is the one that does not fit the existing model.** Every other item is
instantaneous — instantiate, execute, free, all on one frame. A heavy mine wants
to be placed *at the chokepoint*, which is somewhere the robot is not standing.
Two options:

- **Place at feet only.** Trivial, works today, and much weaker — a mine where
  the defender stands is a mine behind the thing it should be covering.
- **A short placement errand.** The robot walks to the chokepoint, places, and
  returns to its slot. Needs an intent that survives a few seconds and yields to
  anything more urgent.

The errand is the right answer and it is also a new behaviour, so it should be
costed separately from the other three.

**Finding the chokepoint** is the other open question. Candidates: narrow
navmesh width along the approach path, the bridge nodes levels already carry, or
the squad's own objective geometry. Worth prototyping against Qamareen, which has
bridges and doorways and is the map where defence actually matters.

---

## Suggested order

1. **Widen the context and drop the `combat_target == null` early return.** Nothing
   else is possible until this is done, and it is also what would let EMP and
   Hatchling stop behaving like frags.
2. **Cluster Mine on withdrawal.** Smallest honest win, uses only the new squad
   objective field, and reads instantly in play.
3. **Smoke.** Most valuable to the player fantasy; the tuning risk is real but the
   gate is simple.
4. **Drone Pack.** Simple logic, but the most expensive mistake when it misfires.
5. **Heavy Mine.** Last, because it needs the placement errand.

## How to tell whether any of it worked

The Laboratory is the instrument — `tools/lab_run.gd -- <plan>` is five minutes a
sample. A plan that pits a withdrawing squad against a pursuing one would show
whether mines-on-withdrawal and smoke actually change outcomes, rather than
merely happening. Note from current experience: run every comparison twice
before believing it, because the engagement-range plan's own repeats disagree by
several points.

---

# Ordering it: can the player say "smoke there"?

Yes, and the shape is already decided by a choice the commander made before us.

`squad_commander.gd` killed a five-item wheel on purpose:

> The wheel used to carry MOVE TO / DEFEND / ATTACK / FALL BACK / CONTACT. Those
> weren't five orders, they were two questions collapsed into one list: WHERE and
> HOW. The aim point already answers WHERE in every case, so the verb only ever
> had to answer HOW.

And CONTACT came off it because "by the time you have held, scrubbed and
released, the thing you spotted has moved."

**So: no equipment wheel.** Anything that makes the player choose smoke from a
list before pointing has lost the argument that file already settled.

## The grammar that fits

One new key. The aim point answers WHERE, exactly as T does. **The squad answers
WHICH**, from where you pointed and what is happening:

| you point at | while | the squad reads it as |
|---|---|---|
| ground between you and contact | under fire | **smoke** — screen it |
| ground behind the squad | withdrawing | **cluster mine** — deny the ground you are giving up |
| a chokepoint on the approach | holding | **heavy mine** — fortify it |
| at or near a heavy hostile | it is beyond your reach | **drone pack** — send the Divers |
| anywhere | nothing fits | say so, out loud |

This is the same trick T already plays: the player states intent by where they
look, and the squad is competent enough to pick the tool. It costs one key and no
menu, and it degrades honestly — if nothing fits, it says nothing fits rather
than guessing.

If that proves too ambiguous in play, the fallback is a modifier (a held key
plus the aim) to force a kind. Worth trying the inferred version first: the whole
character of this command system is that you point and your robots are good at
their jobs.

## THE SQUAD IS THE ALLOCATOR — not "everyone who has one"

The obvious implementation is "every soldier carrying smoke throws one". That is
wrong, and it is wrong in a way that will not look like a bug:

- Smoke is **two per mission, per soldier**. Four soldiers answering one order
  spends four canisters on a 7 m gap and leaves the squad with nothing when it
  actually has to disengage.
- Four clouds on the same point is one cloud. The frontage needed rarely matches
  the number of people holding the item.

So `Squad` works out **how many** the job needs and spends exactly that:

```
clouds_needed = ceil(frontage_to_screen / (cloud_radius * 1.6))
```

...then picks that many holders, nearest-first, who are in range and have a
throw. Same for mines across a chokepoint: enough to cover the width, not one per
carrier. For the drone pack, one is the answer — never two packs at one target.

This is the piece that makes ordered use feel deliberate rather than like a
button that empties your pockets.

## Where it hooks in

The commander already calls `squad.receive_player_order()` directly — the old
600 m sphere sweep is gone — so the path is short:

1. **`SquadCommander`** — new input, resolves the aim point it already resolves
   for T, calls `squad.receive_player_equipment_order(position, target)`.
2. **`Squad`** — infers the kind from aim point plus its own objective and
   contact state, computes how many, selects members, and issues each a slot and
   a position.
3. **`Soldier`/`Enemy`** — `order_use_equipment(slot_index, at_position)`. It
   runs the SAME `AIEquipment.execute()` as the autonomous path; what differs is
   the gate. **`can_use()` is not consulted — the player has decided** — but range
   and friendly-safety are still checked, because the player cannot see that a
   throw is blocked or that a mine would land on a squadmate.

That split is what makes the autonomous plan above worth doing either way: both
paths share `execute()`, and only the decision to use it differs.

## It has to say why when it refuses

Four refusals, each of which must reach the player rather than being a key that
did nothing:

| case | what the player should get |
|---|---|
| nobody is carrying it | "NO SMOKE" — and it should be visible on the squad HUD *before* they press |
| the point is out of throw range (~30 m) | either refuse with a reason, or send the nearest holder closer first — an errand, like the heavy mine's |
| the throw is blocked | refuse; do not lob it into a wall |
| a squadmate is inside the blast or trigger radius | refuse, always, for mines especially |

The out-of-range case is the interesting one, and it is the same question the
heavy mine raises: does the squad **walk to do what you asked**, or tell you it
cannot? Walking is better and is new behaviour; if it is built once, both the
heavy mine and the long-range smoke order get it.

## What this buys

The autonomous plan makes robots competent. This makes them *directable*, which
is the actual fantasy of the game — and it is the cheaper half, because the
hard part (deciding whether throwing is a good idea) is exactly the part the
player is doing for them.

---

# The precision problem, and the thrown marker

An aim-point order is exact at ten metres and a guess at eighty. The crosshair
ray hits a wall edge, a hill behind the one you meant, or sky; and for MINES a
single point is wrong in principle, because a minefield that covers a crossing
beats five mines in a dot.

## What other games do about it

| game | approach | what it teaches |
|---|---|---|
| **Helldivers** | you physically THROW a beacon; the stratagem lands where it lands, bounces included | the throw IS the input. Converts an aiming problem into a throwing problem, which an FPS player already has the skill for — and bad throws are texture, not failure |
| **Full Spectrum Warrior** | orders snap to authored cover positions, not arbitrary ground | precision stops mattering if the world has meaningful places to snap to |
| **Brothers in Arms** | point, and the fire team suppresses what is there | the model `T` already uses, and it works because the squad is competent |
| **Ghost Recon** | tag targets first, order second | a persistent referent beats a one-frame ray |
| **Deep Rock Galactic** | thrown flares as physical light | a thrown object is a shared, visible anchor both sides can see |
| **Company of Heroes** | click a point for a smoke barrage | trivially precise — but it has an RTS camera, which we do not |
| **Arma** | 3D command menus | the cautionary tale, and the reason `squad_commander.gd` killed its wheel |

The two that matter here are **Helldivers** and **Full Spectrum Warrior**, and
they solve the same problem from opposite ends: make the input physical, or make
the world snap.

## The proposal: the marker becomes throwable

`squad_commander.gd` already notes the CommandMarker "is now purely a visual",
and `CommandMarker` still exists as a class. So we already have the referent —
it just gets placed by a raycast.

**Give the same marker two ways to be placed, on one key, with the tap/hold
grammar `T` already teaches:**

- **TAP** — place at the crosshair. Instant. Right at close range where a ray is
  reliable, and in a firefight where a second of flight time is a second you do
  not have.
- **HOLD** — throw it. It arcs, bounces, settles on real ground. Slower, exact at
  range, and visible to you while it flies so you can see where it is going.

One key, two costs, the player picks which they are paying. It mirrors `T` (tap
= advance, hold = follow) so there is nothing new to learn.

**NOT on G** — G cycles which team the orders go to, and that has to stay one
press.

**The flare should be free, with a cooldown, not an inventory item.** Commanding
is not ordnance. Making the player trade a smoke canister for the ability to ASK
for smoke is a bad trade; the thing that should be scarce is the thing that goes
bang.

## Spread: one primitive serves both

The user instinct that "the more spread out mines are, the better" is right, and
it generalises — smoke wants it too. Four clouds in a dot is one cloud; five
mines in a dot is one mine with a bigger bill.

Both want the same thing: **points spread along a line perpendicular to the
threat bearing**, through the marked point.

```
_spread_points(centre, threat_bearing, count, spacing) -> Array[Vector3]
```

- **Smoke** — spacing ~1.6 x cloud radius (≈11 m), so the clouds overlap into a
  wall rather than leaving gaps to be shot through.
- **Heavy mines** — spacing above the 4.5 m blast radius, ≈5-6 m, so one
  detonation does not take its neighbours with it, and the covered frontage grows
  with every mine spent.
- **Cluster mines** — the canister already scatters its own five submines, so
  the canisters themselves want wider spacing still.

**Better still for mines: let the navmesh decide the width.** At the marked
point, measure the navigable width across the approach and lay across *that*.
That is what makes it a minefield covering a crossing rather than a decoration —
and it is the same chokepoint measurement the autonomous heavy-mine plan needs,
so it gets built once.

## The latency question

A thrown marker takes a second or two to land. For smoke-as-withdrawal that is
fine — it is pre-emptive by nature. For "smoke NOW, we are pinned", it is not.

Two mitigations, in order of preference:

1. **The tap exists for exactly this.** Pinned at close range, tap the crosshair;
   the ray is reliable at the distances where panic happens.
2. **Commit on throw, not on landing.** The squad begins turning and preparing
   the moment the marker leaves your hand, and only the final position waits for
   it to settle. Costs nothing and makes the order feel answered immediately.

## Open question worth prototyping

Should the marker be an **instant order** (it lands, the squad acts, it is gone)
or a **persistent focus** (it lands and stays; subsequent orders key off it until
you throw another)?

Instant is simpler and matches Helldivers. Persistent is more flexible — "that is
the spot" as durable state — and would let one throw anchor a defence while the
squad does several things around it. Start instant; persistent is a superset and
can come later without changing the input.

---

# THE BUILD PLAN

What was decided, in the order it should be built. Each phase is shippable on
its own and answers a question before the next one is worth starting.

## Already done

`Character/weapon/models/designator_model.tscn` — the tool itself. Primitives
only, so no import step and it loads immediately. A raked screen on a slab with
a grip, an emitter at the front and a visible cycle button. Deliberately not
gun-shaped: everything else in the player's hands is a weapon and this has to
read as a different KIND of object in the half-second it comes up.

Two things learned building it that the live display must not repeat:

- **The screen is a `PlaneMesh`, not a `BoxMesh`.** A box gives every face its
  own slice of the UV rectangle, so a texture put on one is cropped, not mapped.
  Three layout rewrites chased a problem that was never in the layout.
- **The UVs are flipped on the material** (`uv1_scale = Vector3(-1, -1, 1)`),
  because a plane raked back toward the player reads mirrored and upside down.

### All four are now AI-usable *(done, out of plan order)*

Phases 1–4 below are about the player **ordering** equipment. Separately from
that, all four items can now be fitted to a squadmate and are used on the
squad's own judgement — which the plan had put off to Phase 4 and deferred
entirely for the mines.

Why it jumped the queue: `usable_by_ai` was false AND `ai_scene` was null on all
four, and that failed quietly in two places at once. The squad page greyed the
row with "YOU ONLY", and `squad_spawner.gd` dropped the slot on any save where
one had been fitted anyway — so the item cost supply and never appeared in a
mission. Nothing warned.

| item | script | opens when |
|---|---|---|
| Smoke Canister | `ai_smoke.gd` | withdrawing under fire; a casualty within 12 m; crossing open ground while losing |
| Drone Carrier Pack | `ai_deploy.gd` | two hostiles in 45 m **and** one of them has ≥120 hull |
| Cluster Mine | `ai_mine.gd` | holding/withdrawing, contact located 14–60 m out |
| Heavy Mine | `ai_mine.gd` | same, from 10 m out, laid nearer in |

Three decisions in there worth keeping:

- **None of them could have been pointed at `ai_grenade.tscn`.** A grenade wants
  a target that is stationary, clustered and behind cover at 4–30 m — a robot in
  that position is *winning*. Smoke is for the opposite situation, a mine is laid
  before there is a situation, and a pack answers a target you cannot engage.
  Reusing the grenade would have made all four "AI-usable" and never used, which
  is what the Hatchling already was.
- **The drone pack's gate is hull, not bodies.** Two Divers cost 95 supply;
  spent on a rifle trooper (60 hull) that is a worse trade than the rifle the
  robot is already holding. `min_target_health = 120` makes the pack *wait* for a
  Rover or a Walker. The Hatchling keeps 0 — it is cheap and it swarms.
- **Mines need no friendly-fire rule**, and that is not an oversight.
  `Mine._candidates` asks `AIManager.hostiles_for(whoever placed it)`, so a
  squad-laid mine cannot answer to the squad or the player. That is the only
  reason an AI can be trusted to lay these at all.

Found while building it: **`AIGrenade.can_use` has never been able to tell
whether it can see its target.** It calls `is_path_clear(own_position,
target_position)` with no body excluded, and a ray cast at something's own
position stops inside its collider — so `los_clear` is false in an empty field
and the "don't grenade someone you can plainly see, just shoot them" rule has
never once fired. Every other sight test in the game passes the body to exclude
(`enemy.gd` does it in nine places). **Now fixed** — cast from eye height and
exclude the target. Expect the AI to throw *fewer* grenades: the rule it
restores is "don't grenade someone you can plainly see, just shoot them", and
clustered targets are still grenaded in the open. That is a feel change, so it
is the first thing to watch in play.

## Phase 0 — unblock the context  *(prerequisite, nothing works without it)*

`Character/characters/ai/enemy.gd`

```gdscript
func _evaluate_equipment_use() -> void:
    if combat_target == null:
        return          # <- this
```

Equipment is only ever considered when a robot already has something to shoot.
Smoke is for when you want to STOP shooting; mines are laid before contact or
while breaking it. Widen `AIEquipment.EquipmentContext` with `squad_objective`,
`under_fire_seconds`, `downed_friendly_nearby`, `threat_bearing`,
`hostiles_near_target` (the current `nearby_hostiles` is a ring around the
OWNER, which is the wrong end for clustering decisions) and
`recent_equipment_by_squad`, then drop the early return.

**Done when:** EMP and Hatchling stop behaving like frags. They currently run
`ai_grenade.gd` with a different projectile swapped in, so an EMP gets thrown at
a lone stationary target where it is wasted. This phase improves equipment the
AI **already carries**, with no new verbs in the game — it is worth doing even
if everything below is cancelled.

## Phase 1 + 2 — BUILT. The designator, and the squad allocating

Shipped together, and wider than "smoke only": the mode list is built from what
the squad is **actually carrying**, so it covers every item at once rather than
needing a pass per item.

| piece | where |
|---|---|
| the tool | `Character/equipment/player_designator.gd` + `Character/weapon/designator_hud_weapon.tscn` |
| its screen | `Character/weapon/models/designator_screen.gd` — a SubViewport on the slab |
| the order | `SquadCommander.issue_equipment_order` → `Squad.receive_player_equipment_order` → `Enemy.order_use_equipment` |
| the aim override | `AIEquipment.placement_or()`, honoured by all four `execute()`s |

**It is key 7, by reservation.** The first attempt gave it `equipment_order = -1`
so it would sit at a stable key 4 — which pushed a Utility Harness's third
throwable off the end of the row where nothing could select it.
`tools/test_equipment.gd` caught that. The row is positional and a built-in has
no position in it, so `PlayerEquipment.fixed_slot_action` now reserves an action
outright and leaves keys 4-6 to what the player bought.

**`can_use()` is not consulted on an ordered use, and that is the point.** It
answers "is this a good idea", which the player has just overridden by pointing
at something. What still applies is what the player cannot see: a use left, off
cooldown, and within throw range — and each of those refuses *out loud*
(`NO ANSWER`, `NONE LEFT`, `TOO FAR`, `NOBODY CARRYING`) through
`equipment_refused` onto the squad toast.

**One point is one answer.** `Squad.receive_player_equipment_order` sizes the
response to the frontage asked for rather than letting every holder throw: four
robots answering one mark spends four canisters on a seven metre gap, and four
clouds on one spot is one cloud. A frontage wider than one cloud spreads the
answers along a line *perpendicular* to the threat bearing — the primitive a
line of mines will reuse.

Two bugs this shook out, both of the silent kind:

- **Reserved-key items were never initialized.** Pulling them out of `equipment`
  also pulled them out of `_all`, which is what the loadout drives the lifecycle
  from — so the designator existed, drew, and had never had `initialize()`
  called on it. `tools/test_designator_live.gd` exists because of this.
- **The screen rendered as a solid green slab.** `emission_operator` defaults to
  ADD, so the material's base emission was added across the whole surface before
  the readout texture was considered. MULTIPLY, with a white emission colour.

### Phase 1 — the original plan, for reference

**Files:** a new `Character/weapon/designator_hud_weapon.tscn` following the
pattern of `scanner_hud_weapon.tscn` (`display_name`, `equipment_order`,
`consumes_charge = false`, `equippable_when_empty = true`); a small display
scene for the screen's SubViewport; one new method on `Squad`; one on `Enemy`.

**It is a BUILT-IN, like the repair tool on KEY 3.** It costs the player no
equipment slot and is never bought. Commanding is not ordnance — the thing that
should be scarce is what goes bang, and a squad capability must not depend on
the commander's loadout.

- **Screen** — built from the squad's real `equipment_ids`, deduplicated.
  `Icons.item()` already serves the Armorer, so every item gets a readout free.
  When the squad carries nothing, it says so, which quietly teaches the shop.
- **Reload cycles the mode.** Reuses a bind everyone has, is physical, cannot be
  spammed mid-firefight.
- **Hold to designate, with a LIVE preview.** The mark follows the crosshair
  while held so you can scrub onto the right spot and release when it is right.
  That preview — not the hold duration — is what fixes aiming at range.
- **~1.2 s, not 2.5-3.** `T` is instant; twenty times slower is unusable under
  fire, and a verb that fails when you need it is a verb nobody learns. Start at
  1.2 and raise only if it feels casual.
- **Only smoke.** No allocation cleverness: the two nearest holders throw at the
  mark. That is enough to answer the only question that matters — do you reach
  for this, or forget it exists?

**Hook:** `SquadCommander` already calls `squad.receive_player_order()` directly,
so add `receive_player_equipment_order(position, target)` beside it.
`Enemy.order_use_equipment(slot, at_position)` runs the SAME
`AIEquipment.execute()` as the autonomous path — what differs is the gate.
`can_use()` is NOT consulted, because the player has decided; range and
friendly-safety still are, because the player cannot see that a throw is blocked
or that a mine would land on a squadmate.

**It must say why it refuses.** Nobody carrying it, out of throw range (~30 m),
blocked line, or a squadmate inside the blast. A key that does nothing is worse
than a key that says no.

## Phase 2 — the squad allocates

The squad decides HOW MANY, not "everyone who has one". Smoke is two per mission
per soldier; four soldiers answering one order spends four canisters on a seven
metre gap and leaves nothing for the disengage that actually needs it — and four
clouds on one point is one cloud.

```
clouds_needed = ceil(frontage / (cloud_radius * 1.6))
```

Then that many holders, nearest first, in range. The spread primitive is shared
with mines later: points along a line **perpendicular to the threat bearing**
through the mark.

## Phase 3 — drone carrier

**No designation.** The Diver climbs and picks the most expensive frame it can
see, so the mode is a confirm rather than a point — the one mode you can fire
off instantly, which fits it being the emergency answer to armour. One pack is
always the answer; never two at one target.

## Phase 4 — autonomous use

The squad uses smoke on its own judgement: not winning the exchange, AND
(falling back under fire, OR a downed squadmate nearby under fire, OR crossing
open ground while being hit). Place at ~60% of the way toward the threat so the
cloud covers more of our arc than theirs.

Shares `execute()` with Phase 1, so this is a `can_use()` rule rather than a new
system.

## Deferred — mines

Both kinds, and the reason is honest: they reward static defence in a game of
assaults, they need the enemy to walk a predicted route, the heavy mine needs a
placement errand nothing else needs, and a minefield is fun to watch laid exactly
once. Revisit when there is a mission type that wants them.

## How to tell whether any of it worked

`tools/lab_run.gd -- <plan>` is five minutes a sample. Run every comparison
TWICE before believing it — the engagement-range plan's own repeats disagree by
several points, which is wide enough to swallow a real effect either way.
