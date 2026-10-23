# Brief — contacts, freshness and target distribution

Written 2026-10-08 by GAMEPLAY, off an audit of the stimulus bus, the targeting
path and the AI manager's caches. **One build, not a phased rollout.**

Owner: **unassigned**. Status: **not started**.

Three problems, one table:

1. **Everyone shoots the nearest thing.** Five robots facing five enemies all
   unload on the closest, then on the closest of the four.
2. **Nobody acts on what the squad can see.** A contact report reaches idle
   robots only, and all they do is walk at it.
3. **The mortar sees for itself**, when it should be firing at what somebody
   else is looking at.

**Built in one pass, tested by switches rather than by staging.** Every
behavioural term below is a debug toggle and a tunable, so the whole thing goes
in at once and is then turned on one piece at a time in a running game. That is
the trade: more code before the first test, far faster iteration after it.

---

## What is already there

Audited with line references, because several claims about this system turned
out wrong before it was read properly.

**Target selection is `_nearest_hostile()` and nothing else.** Its own comment
says the manager "searches the whole level — it answers *nearest*, never
*near*". One clamp (`reacquire_range()`), no awareness of what anyone else is
shooting. That is problem 1, in one function.

**The only deconfliction in the game** is `_claimed_by_squadmate()` inside
`AIWeapon.acquire()`, used by the one weapon with `Targeting.PATIENT` — the
mortar. Right idea, wrong place: per-weapon, per-squad, O(members) per pick.

**The caching is already good**, which is why this can be nearly free:

| Thing | Where | Shape |
|---|---|---|
| `hostiles_for(faction)` | `ai_manager.gd:172` | one living-hostile list per faction, cached `HOSTILE_CACHE_LIFETIME` = 0.4 s |
| `get_nearest_hostile()` | `ai_manager.gd:191` | scans that list, not `all_ai` — "ten entries instead of three hundred" |
| `_nearest_cache` | `enemy.gd:3328` | per robot, per physics frame |
| `change_combat_target()` | `enemy.gd:3798` | **the single funnel every target assignment passes through** |
| `ekilled` | `ai_manager.gd:15` | every E-KILL — **not a death**, see below |

`change_combat_target()` is why claims can be O(1) to maintain, and
`hostiles_for()`'s `.alive` filter is why eviction is free.

**Contact reporting exists and is inert.** `ENEMY_SPOTTED` is emitted by a robot
that acquires with a clear line (35 m, `enemy.gd:4998`) and by the player's
`Verb.CONTACT` (45 m, 60 m at open sky, `squad_commander.gd:469`). The sole
consumer, `enemy.gd:4708`, runs only for robots **not** in COMBAT or SEARCH,
remembers a position, and walks at it within 20 m.
`StimulusManager.emit_stimulus()` is fire-and-forget. `_remember_last_seen()` is
a rolling four-entry array of positions per robot, no identity, no timestamp.

So there is nowhere to record *who* we know about or *when we last saw them*.

---

## The table

**One dictionary, per faction, on `AIManager`, beside `_hostile_cache`.**

```
_contacts[faction][target_id] = {
    pos: Vector3,        # last known position
    seen_at: float,      # engine time of the last confirmed sighting
    by: int,             # how many of ours are currently targeting it
    incoming: float,     # committed damage per second against it
}
```

Four fields. Everything reads from it; nothing sweeps it.

### Maintained incrementally, never swept

- **`seen_at` / `pos`** — on a confirmed sighting in the vision tick, and on an
  `ENEMY_SPOTTED` stimulus. O(1) per event.
- **`by` / `incoming`** — in `change_combat_target()` only. Decrement the old,
  increment the new. `incoming` adds the robot's own
  `base_damage / fire_cooldown`.
- **Eviction** — when the target leaves `hostiles_for()`, which already filters
  on `.alive`. No new hook, no signal to connect.

**Decay is computed on READ**, from `seen_at`. Never by ticking entries. The
vision tick is already LOD'd (`vision_interval * lod`) because it was expensive;
a per-frame sweep would undo that for nothing.

### Do NOT evict on `ekilled`

`ekilled` is emitted by `_tick_ekill_edge()` on the **edge into**
`SignalState.EKILL`, with `alive` still **true**, and its comment says the flag
clears when the robot climbs back out — "a robot knocked down twice is two
events."

**An e-killed robot is stunned, not dead.** It still has to be killed and
recovers at 0.08 signal a second. Dropping its contact would make the squad
forget a helpless enemy at the moment it is easiest to finish.

So e-kill is a **priority bonus, not an eviction**. What removes a contact is
`alive` going false, set in both `enter_downed()` and `destroy()`, so wrecks and
corpses alike fall out of `hostiles_for()` on its next 0.4 s rebuild.

### Freshness

`fresh = (now - seen_at) < CONTACT_FRESH_SECONDS`. Refreshed by three things,
and the third is the point:

- a robot's own vision tick,
- **a squadmate's `ENEMY_SPOTTED` callout**,
- the player's `Verb.CONTACT`.

Seeing comes from your squad talking, not only from your own eyes.

One registry per **faction**, not per squad: the Watcher and the Spotter spot
for a whole force, and the bus is already faction-filtered.

---

## Target distribution

Replace `get_nearest_hostile()` with `get_best_hostile()` at its single call
site in `_compute_nearest_hostile()`. **Same scan, same cached list, same
cost** — only the comparison changes. `_nearest_cache` stays as it is.

```
score  =  -distance
       +  W_SATURATION * overkill_ratio      # negative weight
       +  W_EKILL       if stunned
       +  W_DESIGNATED  if the player called it
       +  W_FRESH       if the contact is fresh
       +  W_IN_RANGE    if inside this weapon's effective band
       +  W_STICKY      if it is already this robot's target
```

```
overkill_ratio = clamp(incoming * TTK_WINDOW / max(health, 1), 0, 2)
```

**Saturation, not headcount, and the catalogue shows why.** A Rifle Trooper is
60 HP; one Soldier with a Squad Automatic is ~164 DPS, so a single shooter is
already overkill and the second should look elsewhere. A Walker is 320 HP, so
five Soldiers on it is only just enough and they should all stay. One rule, both
behaviours — and counting claims could never tell a mortar (20 DPS) from a Heavy
MG (183 DPS).

`W_STICKY` is not a nicety. Without hysteresis a score flipping between two
near-equal candidates re-aims every targeting tick and hits nothing;
`aim_settle_time` and `_aim_tracking` exist precisely because settling matters.

**Both factions use it.** It lives in the shared manager. This is the part most
likely to make firefights *look* right — instead of four riflemen converging on
one Soldier while the rest of your squad stands unshot, contact spreads and the
whole line is engaged. It is also a real difficulty change, not polish: enemy
squads stop wasting fire.

---

## The rest of the system

**The mortar depends on somebody else's eyes.** PATIENT `acquire()` today picks
from `_visible_candidates()`, which despite its name is every hostile the
manager knows about, unfiltered by sensing. Restrict it to **fresh** contacts.
This is a nerf: the mortar gets worse alone and lethal with a spotter. It also
retires `_claimed_by_squadmate()` — `incoming` says the same thing cheaper.

**The mortar as a fire mission.** `Verb.CONTACT` already passes the target node
and lights `activate_enemy_marker(target, 8.0)`, so the game knows what you
pointed at and for how long. `W_DESIGNATED` in PATIENT `acquire()` swings the
tube onto it without an order being issued — which is what that verb's comment
says it is for. The 8 s marker is the natural duration.

**Accuracy from a fresh contact.** `get_aim_spread_multiplier()` already stacks
settle time, movement and suppression. One more term. This makes the Spotter a
squad-wide damage multiplier without moving any range or sensor value.

**Engagement beyond your own eyes.** A fresh contact lets a ranged robot engage
something it cannot personally see. Today firing is gated on FOV and a raycast
inside `sight_range()`, and the squad code says plainly: *"Ranged members are
untouched — they still need to see what they shoot at."* Changing that sentence
is the riskiest thing here, so it is gated three ways: **per-weapon opt-in**
(`spotter_assisted`, long weapons first), **FRESH only**, and **line of fire
still applies** — being told where something is does not shoot it through a
wall. This is a sensing exemption, not a geometry one.

**Denial, without which the above is only a buff.** Smoke stops a contact
refreshing through it. EMP strips a radius of its eyes for a few seconds.
Suppression finally has a job — `suppressive_fire` is false on all thirteen
weapons and `SUPPRESSIVE_SPREAD` already exists in the aim code, and firing at a
STALE contact is exactly what it is for. The Watcher (350 HP, immobile, 170 m,
built-in literally named `RELAY`) spots for its force, so killing it blinds
them.

---

## The switches, which are how this gets tested

Because it all lands at once, **nothing is judged by rebuilding — everything is
judged by toggling.** `Settings.SCHEMA` already carries `debug.*` keys read live
by the thing they affect, and `options_menu._build_debug()` already renders
them. Add:

| Key | Default | What it gates |
|---|---|---|
| `debug.contact_distribution` | **on** | the saturation term — off reverts to nearest-target |
| `debug.contact_enemy_distribution` | **on** | distribution for the hostile faction only |
| `debug.contact_mortar_needs_eyes` | **on** | the PATIENT freshness restriction |
| `debug.contact_accuracy` | **on** | the fresh-contact aim bonus |
| `debug.contact_engage_unseen` | **off** | engagement beyond personal sight |
| `debug.contact_overlay` | off | the debug readout |

Defaults are the shipping configuration, so playing with everything untouched is
playing the intended game. `contact_engage_unseen` defaults **off** because it
is the one that could make sensor range stop mattering.

**And the weights are exported, not constants.** `W_SATURATION`, `W_EKILL`,
`W_DESIGNATED`, `W_FRESH`, `W_IN_RANGE`, `W_STICKY`, `TTK_WINDOW`,
`CONTACT_FRESH_SECONDS` all live where they can be changed without a rebuild.
Tuning this by editing constants and relaunching would cost more time than
writing it.

**A debug overlay** drawing each live contact with its `by`, `incoming`,
freshness and current score. This is not optional garnish: with every term
landing together, an overlay is the only way to tell which one is responsible
for a behaviour.

---

## How to tell it worked

**Headless, and these go in `tools/test_targeting.gd`:**

- Five on five: targets spread. Count distinct targets engaged on the first
  tick.
- Five on one Walker: still concentrates. **The regression test for the whole
  idea.**
- `by` and `incoming` return to exactly zero for every target when an
  engagement ends. A leak here poisons every later decision and is invisible on
  screen.
- A target going `alive = false` mid-aim releases its claims.
- An e-killed target stays in the table and gains priority.
- A mortar with no spotter holds fire; it engages the moment one sees something.

**In the Laboratory**, which is the only honest way to answer "did fights
change":

```bash
godot --audio-driver Dummy --path . --script res://tools/lab_run.gd -- open_30v30 8 5
godot --audio-driver Dummy --path . --script res://tools/lab_run.gd -- mixed_squads 8 5
```

Run both with `debug.contact_distribution` off, then on, and compare. `lab_run`
prints results as JSON and takes a repeat count. `open_30v30` is the plan most
likely to show dogpiling; `mixed_squads` is the one most likely to show the
saturation rule doing the right thing across frames of different health.

**RUN IT ON A QUIET MACHINE** — `lab_run`'s own header warns that competing
processes do not merely slow it, they can wedge it.

**By hand**, because some of this is only judgeable by feel: a firefight should
look like a line engaging a line, not a queue forming on one robot.

## Definition of done

- `bash tools/check.sh --changed` prints PASS
- `bash tools/test.sh` — **count the failures explicitly**; the exit code of a
  pipeline is not the suite's verdict
- `bash tools/smoke.sh` boots clean
- A Laboratory A/B on two plans, before and after, recorded in the commit
- Every new `debug.*` key defaults to the shipping configuration

## What should not happen

- **No per-frame sweep of the table.** Decay on read, maintenance on event. If
  something needs a sweep, the design is wrong.
- **No second target-sharing path.** `_on_combat_triggered` and
  `_tick_aggressive_pull` already work; this adds *knowledge*, not orders.
- **No claim bookkeeping outside `change_combat_target()`.** The moment two
  places can assign a target, `by` and `incoming` drift silently.
- **No silent early returns.** House rule, and this system is mostly "we do not
  know about that one" branches. Every one says why.
- **Nothing in the save.** Contact is runtime state that dies with the mission.
  The `debug.*` keys are machine preferences, which is where `Settings` already
  puts them.

## Open question

**Does the player see the table?** `activate_enemy_marker(target, 8.0)` already
fires on the CONTACT verb, and 8 seconds is suspiciously close to a freshness
window somebody will want to tune. If freshness is real the marker should show
it decaying. Worth deciding during the build rather than after, because it sets
whether this is a system the player reads or only feels.
