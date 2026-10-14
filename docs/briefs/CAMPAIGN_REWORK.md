# CAMPAIGN REWORK

Everything decided across the design conversation of 2026-10-11, as a plan.
The campaign stops being a list of operations with rewards attached and
becomes a board you take, hold and lose ground on, with the thing hunting you
changing twice along the way.

Concept. Nothing here is built.

**One document on purpose.** The design, the phases, the lane plan and the
briefs are all here — the tech tree, capture and heat as Appendices A to C at
the end. Scattering them is how a plan this size goes out of sync with
itself.

**The opening is soldiers and nothing else** — four of them, the rifles they
were issued, 500 resources, and a locked catalogue. Everything after that is
bought.

**And the game gains a way to lose.** Fail to take and hold a site's bunker
and the squad does not come back. Today a failed operation resets to before
it, which is why none of them has ever been frightening.

**Settled:** a turn is a mission, not a span of time · the enemy moves every
2–3 turns · garrisons are free with the ground and only the frontier can be
attacked · the Sim Arenas are a practice track, not territory · the board
grows 9 → 15 → 19 across three acts · 20 hours ≈ 55 operations.

---

## THE PLAN

Ordered by dependency, not by appeal. Each phase says what it is worth on its
own, because a plan this size gets interrupted and the interruption should
land somewhere shippable.

---

### PHASE 0 — The opening: soldiers and nothing else

**Goal.** A fresh campaign is four soldiers, the rifles they were issued, 500
resources, and a catalogue where everything else is shut.

**Tasks**

1. `Env/world.tscn` → `starting_stock` drops `frag ×3` and `repair_kit`.
   **Keep the four `m4`.** The chassis ships with no gun by design, and
   without them the squad musters holding nothing.
2. Pre-open exactly three lines in the tree: `soldier`, `m4`, `ancient_rifle`.
3. Everything else — 36 items, 26 chassis — starts locked.

**TWO TRAPS IN THE INDUCTION, both load-bearing**

- `induct_buy_rifle` requires an Ancient Rifle **purchasable on turn one**. If
  that line is locked the induction cannot complete and the campaign cannot
  start. That is why it is pre-opened above.
- The player starts **unarmed on purpose**, and `induction.gd` says why: *"the
  seed issues a rifle to every roster record and the player's record is not in
  the roster, so the squad arrives holding rifles and you do not. That is what
  keeps these two from completing themselves."* Do not "fix" it.
- `induct_repair_self` is safe — the repair tool is built into the frame
  ("built in on 3"), not drawn from `starting_stock`.

**Done when** a fresh save shows four soldiers carrying m4s, the player
carrying nothing, 500 resources, and the armoury listing everything bar those
three as locked — and the induction still completes end to end.

**Consequence worth planning for:** with nothing issued, the **first unlock is
the first real decision in the game**, so the tree needs an opening tier cheap
enough to reach in two or three operations. At 2× unit cost that is frag (50),
repair kit (75), scanner (75), smoke (85), scout carbine (110). Author that
tier deliberately rather than letting it fall out of the multiplier.

---

### PHASE 1 — State foundations · *invisible, blocks everything*

**Goal.** The campaign can say what turn it is and what you hold.

**Tasks**

1. `CampaignState`: `turn: int` and `held: Array[StringName]`, both exported.
2. `SAVE_VERSION` bump and migration: every entry in `completed_missions`
   becomes `held`. Approximately true today, and it takes nothing away from a
   player mid-campaign.
3. `advance_turn()` as the single mutation point, emitting `turn_advanced`.

**Trap.** Ownership cannot be derived from `completed_missions` —
`campaign_state.gd` already says so: *"completed_missions only answers 'ever',
which is not enough."* Do not try.

**Done when** a save round-trips turn and holdings, and an old save loads with
its cleared sites held.

**Needs the save sign-off** (§8) before a line is written.

---

### PHASE 2 — Income from holding · *ships alone, felt immediately*

**Goal.** Ground pays. Clearing stops paying.

**Tasks**

1. **A `Location` resource** — owner, `resources_per_turn`, `compute`,
   `resistance`. Maps associate with one. The location owns the economy; the
   mission owns the fight (§2).
2. `resources_per_turn` paid on `advance_turn()` for every location held.
3. **Compute is held, all or nothing**: a location's compute is yours in full
   while you hold it and gone in full when you lose it, exactly as
   `compute_held` already works. Losing a site can put you over your supply
   cap.
4. `reward_resources` stops being the economy and becomes the operation's
   one-off payout, scaled off resistance.
5. **Resistance is total enemy supply, not squad count.** `OpsTable` already
   computes `"resistance": force["supply"]`.
6. **Delete `OpsTable._per_turn()`** and read the real figure.

**Why this is worth shipping alone.** The board already prints `RES n /turn`
and that function is literally `one_off × 0.1` — **it is advertising income
the game does not pay.** This is the phase that stops it lying.

**Done when** holding a site for three turns pays three times, taking it pays
compute once, and the board's numbers match the ledger.

---

### PHASE 3 — Paid unlocks and the fab car · *ships alone*

**Appendix A** in full.

**Tasks**

1. `unlock:<id>` allocation keys; `state.unlocked` retires into them.
2. Migration: existing unlocked ids become **zero-cost** allocations.
3. **Cost is a function of supply, uniform within a tier** — see the table in
   §3a. Every supply-2 chassis costs the same as every other supply-2 chassis,
   and equipment is tiered the same way. `unlock_cost` derives from that.
4. `unlock_requires: Array[StringName]` for the Mark One → Mark Two chains.
5. The catalogue moves into the fabrication car, with four line states: open,
   affordable, short, prerequisite missing.
6. `mission.unlocks` retires.

7. **`required_rank` is deleted.** Not kept as a loadout rule, not
   repurposed — removed from `item_definition.gd`, `chassis_definition.gd`,
   `campaign_state.gd` and the two UI call sites. Rank gating and purchase
   gating were two answers to the same question, and the catalogue is the one
   that stays.

**Blocked on one balance call, not eleven.** Cost by supply tier (§3a) means
nobody prices twenty-seven chassis individually — **three numbers settle the
whole table**, and the eleven currently at 0 stop being a blocker the moment
those three exist.

**Leave alone:** `in_shop = false` means cut from the game.
`debug.unlock_all_gear` keeps working.

---

### PHASE 4 — Force generation · *the reframing, and the long pole*

**Goal.** `enemy_force` stops being a constant and becomes
`compose(budget, roster, posture, site)`. §10.

**Tasks**

1. Keep every authored `EnemySquadSpec` as the map's **positions** — tags,
   postures, wake triggers. Generate only `roster`, `count`, `forced_weapons`
   and `kit_variance`.
2. A budget function of site value × holder economy × act.
3. Faction rosters. **Home Command fields the player's own catalogue** — free
   to implement, and the most chilling thing in Act 2.
4. Split the briefings: authored text describes the **place**, a generated
   line reports the **opposition**.

**Done when** the same site produces a visibly different force in act 1 and
act 3, and the authored set-pieces still fire in the authored order.

**Risk, and the mitigation is the design.** Generated encounters are usually
worse than authored ones — Coast Road's *"bombers for the bridge, armour for
the craters"* is good because somebody wrote it. The split above is what keeps
it: the shape stays authored, only the composition scales.

---

### PHASE 5 — Defend variants · *doubles the value of every map*

**Goal.** Every site is two operations.

**Tasks**

1. A defence flips the flow: you start on the ground, your garrison spawns
   with you, the attacker enters from the frontier edge.
2. `repeatable` goes true on defences. It exists on every mission and is false
   everywhere.
3. Defences pay **nothing** — the stake is the yield you keep.

**Depends on** Phase 1 for ownership, Phase 4 for the attacking force, and
**reversible capture points (§12.1)** — a defence is meaningless while an
objective cannot be lost.

**The content gap this exposes:** eight of nine maps are corridors with an
entrance and an exit, which makes them poor defences. §11.

**And it needs §12 first.** A defence is
meaningless while objectives cannot be lost — there is no `uncomplete`
anywhere in `Campaign/`, so the enemy can stand on a point you took and never
have it. §12 also deletes extraction and makes the adjacency edges
physical, which is what decides where a defender enters.

---

### PHASE 5b — Reversible capture, heat, and connections

**Goal.** Ground can change hands inside a mission, and a map has doors.

**Tasks**

1. Capture becomes **state**: you work the terminal, a tap docks, and the tap
   is a shootable object whose death reverts the core. The point itself
   already exists — `compute_core_point.tscn` in three sizes, scripted
   `interact_objective.gd` at `channel_duration 3.0`, `channel_range 4.5`.
2. **DYNAMIC ALLOCATION AGAINST A SUPPLY POOL.** The change is not "add a heat
   number" — it is that the enemy stops being `spawn X at Y with posture Z`
   and becomes a **supply budget committed over the course of a mission** in
   response to which cores are still theirs, what the player is doing, and how
   long it has gone on. The location's `resistance` is that budget. The
   postures already exist; what is missing is anything deciding.
3. The failstate: lose the bunker, lose the squad, lose the operation. No
   withdrawal. **This game has never had a way to lose.**
4. Connection markers on every map, resolved from the adjacency graph. Entry
   comes from the campaign; extraction is deleted.
5. Two drone classes, the bunker kit, and arrival by air or rail — §12.8–12.9.

**Owned by FORCES, except the drones, the bunker kit and the stop, which are
TERRAIN with a GAMEPLAY trigger.** §12, and it is blocked on two briefs that
are written as **Appendices B and C**. CONNECTIONS, which it also needs, is
not — see §13.1.

---

### PHASE 6 — The turn loop · *the board comes alive*

**Goal.** The other side plays too.

**Tasks**

1. A turn is **an operation** — an attack or a defence. Nothing else advances
   it, which is what closes the farming hole in §5.
2. The enemy acts every 2–3 turns, and most attacks **auto-resolve** against
   the garrison. A playable defence only when the result is in doubt, or when
   the player chooses to take it.
3. The frontier rule: a site can only be attacked if it borders ground you do
   not hold. Straight off `OpsTable.ADJACENCY`.
4. **THE SIM ARENAS BECOME THEIR OWN MODE**, not a mission type. Free actions —
   no turn, no pay, no risk — with their own icon and their own loadout, where
   the player can run their own labs: watch chassis fight each other, or take
   a squad of their choosing against sim opposition.
5. **The tutorial lives here**, and is the one exception to the departure
   lever: throwing it enters the sim rather than moving the train.

---

### PHASE 7 — Acts and escalation · *the campaign gets a shape*

**Goal.** Three opponents with different armies and different objectives — not
one opponent with three sets of special rules.

**Tasks**

1. Exposure is cumulative compute. Thresholds 8 and 16 against a total of ~23.
2. **Home Command**: a green faction, better equipped and more aggressive than
   the Swarm, fielding the same frames the player does. **It controls nothing
   of yours — you are unnetworked from it.** What changes is the quality of
   the opposition, not the rules.
3. **Argus**: a faction with real ground presence, already holding a large
   share of the world's compute, defending **orbital launch sites** because
   what it wants is to put more compute and materiel into orbit.
4. Map reveals at each act boundary.

---

### PHASE 8 — Ten new maps · *parallel, TERRAIN, start now*

Six Home Command installations for Act 2, four orbital launch sites for Act 3,
filling
the variety gaps in §11 as they go: at least two drawn **defence-shaped**, at
least one interior, at least one small and fast, at least one at night.

Longest duration, least blocked, and the only item that cannot be compressed
by working harder on the others. **Start it alongside Phase 4.**

---

### What each phase is worth if you stop there

| Stop after | You have |
| --- | --- |
| 0 | A game where everything is earned |
| 2 | An honest economy and a reason to keep ground |
| 3 | A tech tree. The squad-building game is complete |
| 5 | Twice the operations from the same nine maps |
| 6 | A conquest game |
| 7 | A campaign with a beginning, a middle and an end |

---

## STAGE 1 — WHAT IS BUILT, as of 2026-10-12

The vertical slice is on Valley Basin and plays. Everything campaign-side is
still faked, which is the point: this exists to answer whether the in-mission
loop is worth building a campaign around.

### The files

| | |
| --- | --- |
| `Env/world_objects/holdable_core.gd` | Capture as STATE. Three channel beats, contest, grace, one anchor per core. Drives the authored MissionObjective it stands on, both ways |
| `Env/world_objects/capture_tap.gd` | The delivery drone. Flies in across the view, lands, frees itself |
| `Character/characters/ai/capture_anchor.gd` + `.tscn` | What it leaves: a Nest-derived structure, PLAYER faction, 160 HP, that the enemy can actually target |
| `Env/world_objects/site_operation.gd` | The win condition and the failstate. Stand-down on the bunker; losing the frame ends the operation |
| `Env/world_objects/site_heat.gd` | Pressure from enemy-held cores plus incursion, spent from a finite supply pool |
| `Env/world_objects/enemy_commander.gd` | Turns committed supply into squads, from 13 templates across 3 tech tiers |
| `Env/world_objects/bunker_objective.gd` | The bunker as an objective HUD row, stand-down as its progress |
| `Env/world_objects/core_signal.gd` | Light and sound. The band climbing the shaft, the deck collar, the held beacon, six cues |
| `Env/world_objects/basin_slice.gd` | Assembles all of it onto Valley Basin at runtime |

Suites: `tools/test_holdable_core.gd`, `tools/test_site_operation.gd`,
`tools/test_enemy_commander.gd`, `tools/test_core_signal.gd`,
`tools/probe_basin_slice.gd`,
`tools/shot_basin_slice.gd`.

### How it attaches to the map

`maps/valley_basin_level.tscn` gained **four lines** — one `ext_resource` and
one node. Everything else is built at runtime.

The four authored capture points keep their meshes, ids and places; a
HoldableCore parents to each and takes its terminal over. **Removing the slice
is removing one node.**

> **DO NOT re-save an authored level from an instantiated copy.** The first
> attempt wrote the nodes in with a fit script, the way `fit_ops_table.gd`
> writes into the ops car. That works there because the car is generated and
> flat. Valley Basin is hand-authored and full of prefab instances, and
> `PackedScene.pack()` BAKES THOSE INSTANCES IN — 8,199 lines to 9,692, every
> `uid` dropped, every prefab link replaced by a copy of its contents.
> Reverted from a backup.

### Known gaps, in the order they matter

**Closed 2026-10-12.**

1. ~~**No audio anywhere.**~~ `core_signal.gd` listens to all six of the core's
   signals. Each of the three beats has its own sound, pitched apart, plus an
   interruption, a dock and a loss — six cues from streams already in the
   project, all `@export`ed so swapping one is an inspector edit and not a code
   change. They are the closest fits that exist, not a final answer.
2. ~~**No FX.**~~ A band climbs the shaft with the channel and the light rides
   with it; a collar at the deck brightens alongside; a held core parks the
   band at the top and pulses it as a beacon; an interruption drops all of it
   rather than snapping. All three states take their colour from `HUDPalette`,
   so a core in the world and a site on the operations table agree.
   **Procedural, like the departure lever's handle** — §13.2 still has the real
   article, and replacing this touches no gameplay file.

**Still open, and deliberately so:**

3. **Placeholder geometry** for the cores, the anchor sits on Nest art, and the
   bunker is a pad and a lit post. TERRAIN's, whenever there is time.
4. **`act` is faked at 1** and **resistance is hardcoded at 82**. Not defects:
   Stage 1's own brief says *"hardcode a location, hardcode a resistance
   pool"*. `act` cannot be real until Phase 7 and resistance cannot be real
   until a `Location` exists in Stage 2. They are listed so nobody mistakes
   them for finished.

The one thing this stage cannot close is its own gate. **Whether the loop is
fun is a question only playing it answers**, and the two stakes it was missing
on the first attempt — heat that spawns, cores that can be lost — both exist
now.

### Four initialisation bugs found here, all one family

Worth reading before extending any of this, because the same shape bit four
times in one feature:

- **Wiring in `_ready` loses races.** `HoldableCore` disconnected other
  handlers from a terminal before `InteractObjective` had connected itself, so
  both stayed live and the old mission completed underneath the new one. Fixed
  with `call_deferred`.
- **So does writing another node's property in `_ready`.** The interact volume
  was sized directly and `dummy_terminal.gd` put its default straight back from
  its own `_ready`. Fixed by setting that node's `reach_size` knob instead —
  **when an authored node exposes a knob, set the knob.**
- **A property set after `add_child` is read by nothing.** `_ready` runs
  synchronously on parenting and has already consumed it. Hit twice.
- **GDScript lambdas capture locals BY VALUE.** A closure that wrote to `best`
  and `best_d` updated copies; the function always returned "". Nothing
  errored — reinforcements simply never had anywhere to go.


---
---

## STAGE 2 — WHAT IS BUILT, as of 2026-10-12

**Phases 1 and 2 are in.** The campaign knows what turn it is, who holds what,
and ground pays for being held. Map production (the other half of Stage 2) is
descoped for now — *"we're not making 10 new stages now"*.

### The files

| | |
| --- | --- |
| `Campaign/location.gd` | A place on the board: owner, what it pays, its compute, its resistance, its edges |
| `Campaign/location_catalogue.gd` + `.tres` | All nine, resolvable by id or by the operation fought over them |
| `Campaign/locations/loc_*.tres` | The nine places |
| `Campaign/campaign_state.gd` | `turn`, `sites`, `advance_turn()`, income, derived site compute |
| `Campaign/campaign.gd` | Hands the catalogue to state; clearing an operation advances the turn and takes the ground |
| `Env/world_objects/ops_table.gd` | Reads the real per-turn figure. `_per_turn()` **deleted** |
| `tools/measure_resistance.gd` | Where every resistance number came from |

Suite: `tools/test_campaign_spine.gd`, 26 checks.

### No migration, and no SAVE_VERSION bump

§16.1 took wipe-and-restart, so neither was written. The fields still load into
an old save without one — `from_dict` defaults every field — and `site_owner()`
falls back to each location's authored `start_owner`, so a save with no
territory at all reads every place as theirs. Both paths are in the suite.

### The board, measured rather than invented

`resistance` is **total enemy supply including the reserve**, read off the
authored forces by `tools/measure_resistance.gd`:

| Location | res/turn | compute | resistance | degree |
| --- | --- | --- | --- | --- |
| Hillfort | 8 | 1 | 79 | 1 |
| Valley Basin | 13 | 1 | 82 | 5 |
| Coast Road | 18 | 1 | 141 | 2 |
| Over The Top | 23 | 1 | **365** | 2 |
| Three Rivers | 23 | 2 | 171 | 6 |
| Qamareen | 25 | 1 | 250 | 2 |
| Lockside | 30 | 1 | 264 | 2 |
| Polaris | 35 | 2 | 266 | 2 |
| The Causeway | 55 | 2 | 351 | 2 |
| | **230** | **12** | | |

**Two independent routes to 82.** Valley Basin's authored force totals 82
supply, and 82 is what was hardcoded into `basin_slice.gd` weeks earlier by
counting the garrison by hand. The slice now reads the Location instead, so
there is one number.

**The degrees fit the maps exactly.** Every tagged map's degree in this table
equals the number of edge markers already authored on it (§16.3) — Three
Rivers 6, Valley Basin 5, Hillfort 1. That was not forced; the graph was drawn
by difficulty and the fit fell out.

**Over The Top is the balance problem.** It is the hardest place on the board
by a distance — 365 supply, against The Causeway's 351 and Qamareen's 250 —
and it pays 23 a turn, less than half the Causeway's 55. Either its force is
overstated or its rate is. Worth a look before the rate table is trusted.

### What this changes that a player would notice

**The operations table stops lying.** It has been printing `RES n /turn` from
`_per_turn(one_off)` — literally `reward_resources × 0.1` — for income the
game never paid. That function is deleted and the figure now comes off the
Location. An operation that is not a place (the three Sim Arenas) reads 0
rather than a flattering invention.

### Still faked

- **`act` is 1 everywhere.** Phase 7's, and nothing before it can supply a real
  one.
- **Nobody loses ground yet.** `set_site_owner` is the single mutation point
  and the enemy has no turn in which to use it — that is Phase 6.
- **`reward_resources` is untouched.** Phase 2.4 wants it rescaled off
  resistance; it is already semantically a one-off payout, so this is a balance
  pass rather than a change of meaning.
---

## STAGE 3 — WHAT IS BUILT, as of 2026-10-12

**Phase 3 in full.** Kit and frames are bought, not granted. An operation hands
over nothing; you open a line once and then pay per copy.

### The price table, as decided

**Everything is a multiple of a BASE of 50.** Set by the human 2026-10-12,
overruling §16.2's role-based banding. The five bands fell out of those
multipliers rather than being imposed — the weapon tiers reuse the equipment
shapes exactly:

| Band | Open | Buy | What is in it |
| --- | --- | --- | --- |
| **ISSUED** | — | ×1 · 50 | Ancient Rifle |
| **STANDARD** | ×2 · 100 | ×1 · 50 | frag · smoke · EMP · repair kit · repair tool · armour plating · hardened uplink · utility harness · light cannon · Ancient MG · Mark One · grenade launcher |
| **UPGRADED** | ×3 · 150 | ×1.5 · 75 | cluster mine · heavy mine · nanite reboot · cyclic feed · hatchling charge · overclock servos · repair lance |
| **CREW** | ×3 · 150 | ×2 · 100 | heavy MG · squad automatic · mortar · rocket pods · cluster launcher |
| **ADVANCED** | ×4 · 200 | ×2 · 100 | autocannon · sensor relay · drone pack · recoilless |
| **UNBUYABLE** | — | — | hatchling launcher |

**CREW and ADVANCED differ only in the unlock.** Both cost ×2 a copy; a crew
weapon opens for ×3 and an advanced one for ×4. That is the knob that says
"this is a reach" without making the thing dearer to field.

**Frames are priced by supply, uniform within a tier** — ×1 / ×2.5 / ×5, so
50 / 125 / 250, and opening a frame costs twice building one. Super-linear on
purpose: supply measures ROOM and cost measures CAPABILITY, so flat pricing
would make big frames strictly efficient and collapse the roster onto them.

> **The three chassis multipliers are the one number here nobody signed off.**
> BASE and every kit multiplier came from the human; §3a's super-linear shape
> was carried over into their vocabulary. One edit in `pricing.gd` to change.

**Two items were not in the list** and had to land somewhere: Overclock Servos
(a module at 60) and the Repair Lance (a weapon at 90) are both UPGRADED, the
nearest band to each. **Nanite Reboot was named in two bands in the same
message** — upgraded and higher — and sits in UPGRADED, among cyclic feed and
the hatchling charge rather than the sensor relay and the drone pack.

**Nothing had to be retired.** The four old guns — marksman rifle, carbine,
shotgun, pistol — were ALREADY `in_shop = false`. The project had reached the
same conclusion before anyone said it.

### THE TOOLING FABRICATOR — where lines are opened

**Named and split out 2026-10-12.** Buying a copy and opening a line are two
different decisions, and putting both on the armourer made it read as a shop
that sometimes refuses to sell to you. So they are three screens with one job
each:

| | Shows | Does |
| --- | --- | --- |
| **TOOLING FABRICATOR** | Everything for sale, open or not | Opens a line. Pay once |
| **ARMORER** | **Only what is already open** | Buys and sells copies |
| **FACTORY** | **Only frames already open** | Builds robots |

A fifth tab in the squad manager, beside SQUAD · ARMORER · FACTORY · SOFTWARE.

**The filtering was already there.** `SquadManagerUI.shop_items()` and
`.buildable_frames()` both skip a shut line, so the armourer and the factory
were never going to list a locked thing — the four-state catalogue line simply
moved out of them wholesale rather than being duplicated. What is left on those
two pages is a plain statement of where to go.

**Opened lines stay listed in Tooling, struck through rather than removed**,
with a `n / m OPEN` count per section. A catalogue that silently shrinks as you
buy from it gives no sense of how much tree is left, and no way to see what a
chain is waiting on.

Suite: `tools/test_tooling.gd` — including the one that matters, that the
armourer never lists something it would then refuse to sell.


| | |
| --- | --- |
| `Campaign/pricing.gd` | The whole balance surface. Bands, assignments, chassis-by-supply |
| `campaign_state.gd` | `unlock_key` · `is_unlocked` · `grant_unlock` · `unlock_item/chassis` · `unlock_requires` · `line_state` |
| `campaign.gd` | `is_locked()` replaces `locked_by()`; a new campaign opens what it is issued |
| `squad/tooling_page.gd` | **THE TOOLING FABRICATOR.** The catalogue line in four states — the only place a line opens |
| `armorer_page.gd` · `factory_page.gd` | Buying and building only; both list what is already open |
| `chassis_hologram.gd` | The fab car's bays show OPEN LINE and its price |
| `item_definition.gd` · `chassis_definition.gd` | `unlock_requires`; **`required_rank` deleted** |

Suites: `tools/test_pricing.gd` (19 checks, pins every number above),
`tools/test_tooling.gd` (the three-screen split),
`tools/test_ledger.gd` (168 checks, up from 167).

### `required_rank` is gone

Removed from both definitions, both gate sites, two UI call sites and **62
authored `.tres` files**. Rank still exists and still drives stats; it just
stopped being a second answer to "can this robot have this", which the
catalogue now answers on its own.

**Six resources carried a real gate** and lost it. If any should come back as
an `unlock_requires` chain rather than vanish, these are they:

| | was |
| --- | --- |
| Marksman Rifle | rank 1 |
| Kite · Spotter | rank 1 |
| Walker · Helicopter | rank 2 |
| Bulwark | rank 3 |

### Two traps worth knowing

**Recruiting bypassed the gate.** The factory's BUILD button calls
`state.recruit()` directly, which never consulted the unlock — so the four
line states would have been decoration. `recruit()` now refuses a shut line,
the same as `buy_chassis`.

**A new campaign could not build anything.** With every line shut by default, a
fresh save had no frame and no weapon it was allowed to use. What you are
ISSUED is now opened for free at campaign start: the starting frame, the
starting weapon, and everything in `starting_stock`.

### A stale file, found on the way

**`Campaign/item_catalogue.tres` is not the catalogue.** It holds 10 items and
one chassis and nothing loads it. `Env/world.tscn:94` wires the CampaignManager
to `Campaign/items & catalogue/test_item_catalogue.tres` — 34 items, 12
chassis — which despite the name is the shipped catalogue. Worth renaming, or
deleting the leftover, before someone edits the wrong one.

### Not done

**Task 5, the second half.** The TOOLING FABRICATOR exists as a page in the
squad manager, and the fab car's chassis bays show line state and price.
PHYSICALLY SITING the panel on a terminal in the fabrication car — so you walk
to it rather than opening it from anywhere — is placement work, not mechanism,
and is left alone. The name is in the fiction now either way.
---

## STAGE 4 — WHAT IS BUILT, as of 2026-10-12

**Phase 4, less the briefing split.** `enemy_force` has stopped being a
constant: what a site fields is now a function of the site, the act and who
holds it.

### The rule that keeps it from being worse than authored content

**THE SHAPE STAYS AUTHORED. ONLY THE COMPOSITION SCALES.**

Every authored `EnemySquadSpec` survives with its callsign, tags, posture, wake
triggers and faction intact. What is rebuilt is the four fields that say WHAT
is standing there — `roster`, `count`, `forced_weapons`, `kit_variance`. A
squad authored to garrison the north trench still garrisons the north trench;
it is made of different robots.

**And the budget is shared out in proportion to the authored supply.** A spec
authored at 4 against one authored at 30 keeps that ratio whatever the total
becomes, so a picket stays a picket and the hard point stays the hard point.
Scaling every squad equally would flatten the map's own pacing, which is the
second way this breaks.

### The numbers

`budget = location.resistance × act × holder`, rooted in the figure
`tools/measure_resistance.gd` measured off the authored force:

| | |
| --- | --- |
| Act | 1.0 · 1.15 · 1.35 |
| Holder | Swarm 1.0 · Home Command 1.1 · Argus 1.25 |

**Act 1 is the authored number exactly**, so the maps as they ship ARE the
Act 1 experience and none of them needs re-tuning.

Measured on Valley Basin:

| | Supply | Frames |
| --- | --- | --- |
| Act 1, Swarm | 82 | chaser · leaper · rifleman · shotgunner |
| Act 3, Swarm | 112 | **bastion · see_engine** · chaser · rifleman |
| Act 2, Home Command | 103 | **drayman · mechanic · picket · rover · soldier** |

That last row is Phase 4.3 working: **Home Command fields the player's own
catalogue.** Free to implement, and the first time a Walker is on the other
side the act change needs no dialogue.

### The files

| | |
| --- | --- |
| `Campaign/force_generator.gd` | Budget, faction rosters, proportional refill |
| `Campaign/enemy_force_spawner.gd` | Calls it, behind `generate_force` |

Suite: `tools/test_force_generation.gd`, 19 checks.

### A parse-time cycle, worth knowing about

`campaign.gd` names `EnemyForceSpawner`, which names the generator, which
originally **preloaded** the chassis `.tres` — whose script is
`ChassisDefinition`, which `campaign.gd` also names. That closes a loop at
PARSE time, and every file in it fails to compile with an error naming none of
them. The frames are loaded lazily and cached instead.

`enemy_commander.gd` hits the same wall from the other side and solves it with
`DirAccess`, which does not survive an export. This does.

### Not done

**Task 4, the briefing split** — authored text describing the PLACE, a
generated line reporting the OPPOSITION. The briefings still read as written.

**`act` is still 1 everywhere.** `state.act()` does not exist until Phase 7, so
the generator asks for it, does not find it, and uses 1. Every act path is
built and tested; nothing supplies a real act yet.
---

## STAGE 5 — WHAT IS BUILT, as of 2026-10-12

**Phase 5, proven on Valley Basin.** Every site is two operations; this is the
first second one.

### `Valley Basin — Hold`

Unlocked by taking the basin, **repeatable**, and it **pays nothing** — §2, the
stake is the yield you keep. Four columns converge on the cores from four
different edges, two of them held back to 90 s and 150 s.

### The garrison

**Free, comes with the ground, sized on COMPUTE** — §6. 8 supply at zero
compute, 40 at a finished campaign's 32. One squad per core, dug in.

**Flat across every site**, which §6 is emphatic about: if garrison strength
tracked site value your richest sites would be your safest and your poorest
would churn. Compute is player-wide, so the enemy picks its target by value
instead.

**Built only from frames the player has OPENED.** Opening the Walker line
changes what defends your ground. A garrison fielding kit you never unlocked
would hand you through the back door what Phase 3 charges for at the front.

**And it is NOT yours to command.** `player_commandable = false` was not
enough — `SquadCommander.refresh_squads()` also admits anything
`_is_friendly_squad()` calls non-hostile, which a PLAYER-faction garrison is.
There is now `Squad.autonomous`, checked before the friendly test.

### What the first watch found, and what it cost

Fifteen minutes of watching it run found four things no test could have:

1. **The garrison was 250 m from the fight.** Posts were picked by tag NAME —
   `trench_n`, `trench_s`, `tower` all *sound* defensive and all sit at the far
   west end, while the attackers came in at the east pass. The ring that
   actually surrounds the cores is `obj_valley_garrison_1..5`.
   **Measure the map before authoring against it** —
   `tools/probe_basin_geography.gd` now prints every tag's position.
2. **Forty attackers stood by the bunker doing nothing.** The two late waves
   had `wake_after_seconds` but not `always_active`, so they spawned far out,
   were culled, and never walked.
3. **The cores started HOSTILE and orange** — copied from the attack. So the
   attackers arrived at things already theirs, and the map had no win or lose
   condition at all. On a defence the cores now start PLAYER-held with their
   anchors standing, and the attackers take them by shooting those off, which
   needed no new AI behaviour (§12.3 predicted exactly that).
4. **`active_objectives` was empty**, which means ALL of them — so the defence
   listed the attack's extraction and hive objectives too.

### How a defence ENDS

An attack is won at the bunker. A defence has no bunker to take, so the first
cut had **no win condition** and ran until the window was closed: the garrison
killed every attacker by five minutes, then heat refilled the field and it
began again.

> **A defence ends when the attacker runs out.** SiteHeat already spends from a
> finite pool, and that pool IS the assault — so when it is spent and the field
> has been clear for 8 s, you have held. No timer and no new concept, and the
> pressure readout the player is already watching becomes the clock.

**Lost** by losing the ground: all cores back in their hands, which is reachable
precisely because an anchor can be shot off.

### The files

| | |
| --- | --- |
| `Campaign/missions/mission_basin_2_defend.tres` | The operation |
| `Campaign/force_generator.gd` | `garrison()`, `garrison_supply()`, `unlocked_frames()` |
| `Env/world_objects/site_operation.gd` | `defence`, the pool-spent win, the ground-lost loss |
| `Env/world_objects/holdable_core.gd` | `start_held()` — a core that begins yours |
| `Managers/AI/squad.gd` · `squad_commander.gd` | `autonomous` |
| `tools/watch_defence.gd` | Watch one run, windowed, at 1x |
| `tools/probe_basin_geography.gd` | Where everything on the basin actually is |

Suite: `tools/test_defence.gd`.

### Not done

**The other eight maps.** §11 is right that eight of nine are corridors and
make poor defences — a defence wants several approaches converging on
something worth standing on. Three Rivers (degree 6) is the only other one
clearly suited. Polaris is drawn as a hold-out and has no anchor tags at all.

**Nothing generates a defence yet.** Until the enemy takes ground on its own
turn — Phase 6 — a defence is a mission you pick from the board by hand.
---

## STAGE 6 — WHAT IS BUILT, as of 2026-10-13

**Phase 6 tasks 1–3 in full, and task 4's mechanics.** The board comes alive:
clearing an operation moves time, and the other side takes ground.

### The loop

**A TURN IS AN OPERATION.** Nothing else advances it — not a clock, not a
button — which is what closes §5's farming hole. You cannot sit at base earning
income, because income only arrives when you go and do something.

Clearing an operation now: advances the turn, pays every held site, takes the
ground it was fought over, **and then the other side moves.**

### The frontier rule, which turned out to be the good part

> A site can only be attacked if it borders ground you do not hold.

Hold Hillfort alone and it is exposed. Take Valley Basin — its only neighbour —
and **Hillfort becomes interior and untouchable.** Consolidating is a real
strategy with no new data and nothing to explain, exactly as §6 said it would
be.

They target **by value**, because garrisons are flat: holding Hillfort (8/turn)
and the Causeway (55/turn), they go for the Causeway. Ties break toward the
longest held, so somewhere just taken is not instantly snatched back.

They move **every 2 or 3 turns, never less, never more** — it counts turns
since the last move rather than rolling each turn, so a six-turn drought cannot
happen. Seeded on the turn number, so a reload is the same campaign.

### In doubt is an INVITATION

A clean win or loss resolves on paper. A close one does **not** change hands —
the site is marked `UNDER ATTACK / DEFEND IT` in CRIT red on the operations
table and the defence becomes deployable.

**A defence is not a mission you can pick.** It exists only while a raid waits
on an answer; otherwise you could defend a site nobody was attacking, forever,
free, and never lose ground. That gate sits BEFORE the DEBUG unlock-all switch,
because that switch opens the ladder — it is not meant to conjure an attack.

**Declining is a real choice.** Doing anything else settles it on paper,
seeded on the site and turn, so walking away twice cannot reroll a bad answer.

### A balance bug worth remembering

The paper fight first pitted the garrison against the site's FULL resistance —
82 for Valley Basin, 365 for Over The Top. A finished campaign's 40-supply
garrison sits at odds of 0.49 against that and **loses every site, every time,
for the whole game.**

A counter-raid is not an invasion. §6 settled that garrisons are flat so the
enemy can target by value; the other half has to be true too — **the raid is a
standard force and value decides WHICH site they hit, not how hard.** It is now
18 / 30 / 46 supply by act, which against a garrison of 8 → 40 gives: early you
bleed ground, mid-campaign it is genuinely in doubt, late you hold — until the
act turns over and it is in doubt again.

### Sim arenas are free actions (6.4)

No turn, no pay, no ground, no enemy move, and repeatable. Practising must
never cost you the campaign, and now that a turn IS an operation it would have.
They still record their clear, because the `requires` ladder runs through them
and they are still what opens Hillfort.

> **THE 3 COMPUTE THEY USED TO PAY IS GONE, and that is not cosmetic.** §6
> sizes total map control on a campaign total of 32; it is now 29.
> `garrison_supply` is `8 + compute`, so every garrison in the game is 3 supply
> weaker, and EnemyTurn's raid curve was calibrated against a 40-supply ceiling
> that is now 37. A practice track should not pay — but that compute needs to
> come back somewhere, most naturally spread across the nine real sites.

### The files

| | |
| --- | --- |
| `Campaign/enemy_turn.gd` | The rhythm, the frontier, targeting, the paper fight, settling |
| `Campaign/campaign.gd` | Plays the turn in the debrief; gates defences; sim runs cost nothing |
| `Campaign/campaign_state.gd` | `under_attack`, `under_attack_turn`, both persisted |
| `Campaign/mission_definition.gd` | `sim` |
| `Env/world_objects/ops_table.gd` | UNDER ATTACK in CRIT, one tint rule everywhere |

Suites: `tools/test_enemy_turn.gd` (18 checks), `tools/test_turn_loop.gd` (13).

### Not done

**Tasks 4 and 5's UI half.** The arenas behave as free actions but are still
pins on the operations board rather than their own mode with their own icon and
loadout, and the tutorial does not yet enter the sim from the departure lever.

**One pin per MISSION, not per SITE.** A place with two operations draws two
markers on the same spot. The board should draw one marker per site with its
available operations on it — that belongs with the board work, and
`basin_2_defend` is given the attack's coordinates as a stopgap.

## EXECUTION — four lanes, one checkout, risk order

**The phases above are a dependency map. This is the running order**, and it is
deliberately not the same thing.

### Why not just build the phases in order

Phases 1 to 3 are campaign plumbing — state, income, catalogue. None of it
changes what playing the game feels like, and you would not touch the thing
this whole rework is betting on until Phase 5b.

**That bet is the risky part.** Nobody knows whether capture–tap–heat–bunker is
fun. The campaign layer is spreadsheet work with low fun-risk: turns, income
and a tech tree will probably work, because that kind of thing usually does.
The in-mission loop is a new mechanic in a new shape, and it is the one that
cannot be rescued by tuning a divisor.

So: **sequence by risk, not by dependency.** Prove the mission before building
the campaign that schedules it.

---

### STAGE 0 — three decisions. ANSWERED 2026-10-12; one yes each.

All three were written down as *"the human's, all three block, none of them is
code."* That was right about the blocking and wrong about the work: two of them
shrank to almost nothing once the relevant code was actually read, and the
third had already been answered by the maps themselves. §16 has each in full.

| | Was | Is now |
| --- | --- | --- |
| **Save format** | A format change and a migration | No format change. One backfill question |
| **Three tier prices** | Three numbers | A rule, plus a dial the balance pass turns |
| **What a connection is** | Undefined, gating every map | Defined, and eight of nine maps already carry theirs |

### STAGE 1 — the vertical slice, and nothing else

**One map. The whole in-mission loop. Everything campaign-side faked.**

Hardcode a location, hardcode a resistance pool. No turns, no income, no
unlocks, no board. Build reversible capture, the tap, the three channel beats,
the bunker, the failstate, and a crude heat spawner. Then play it, repeatedly.

**Use Valley Basin.** Not arbitrarily — its own briefing describes most of this
already:

> *"Land at the west pass… then the anchor itself: up either ramp to the deck
> at the foot of the tower, and **ten seconds at the console**. Taking it
> brings the north and south trenches down on you, and more of them are
> waiting at the east pass, where you get out."*

A channel capture, a counter-attack triggered by capturing, and two passes
that are plainly the connections. Mid-sized at 1.3 MB. It is nearly the slice
already.

**ONE AGENT DOES THIS.** Not three. Parallelising a prototype is how you get a
prototype nobody can change.

> **This is a gate.** If the loop is not fun, stop and fix it before anything
> else is built, because every other stage assumes it works. A two-thousand-line plan
> is downstream of a question only this stage can answer.

### STAGE 2 — ~~two things, in parallel~~ · spine BUILT 2026-10-12

- **The campaign spine** — **done.** `Location`, turn counter, held state,
  income (Phases 1–2). See *STAGE 2 — WHAT IS BUILT* above.
- **Map production** — **descoped.** Ten new maps are not being made now. The
  nine that exist carry the board; three of them need a tagging pass before
  they can be sites (§16.3), which is a chore rather than a dependency.

### STAGE 3 onward — now dependency order is correct

| Stage | | Why here |
| --- | --- | --- |
| **3** | ~~Catalogue and fab car (Phase 3)~~ **BUILT 2026-10-12** | Shipped alone, as predicted. Only the panel's physical move into the fab car is left |
| **4** | ~~Force generation (Phase 4)~~ **BUILT 2026-10-12** | Done but for the briefing split; act is still faked at 1 until Phase 7 |
| **5** | ~~Defend variants (Phase 5)~~ **BUILT 2026-10-12** | Proven on Valley Basin. The other eight wait on map shape, not mechanism |
| **6** | ~~Turn loop, board, sim mode (Phase 6)~~ **BUILT 2026-10-13** | Loop and frontier done; the sim MODE and the tutorial move are still UI work |
| **7** | Acts (Phase 7) | Last — tuning on top of a working game |

Map production (Phase 8) runs underneath all of it, start to finish.

---

### Lanes, by what they may write

`docs/BOARD.md` → Protocol already governs this: one item per lane, per-lane
report files so two agents can close at once without conflicting, the file on
disk is truth, nobody switches branches. What follows fits inside that.

**The protocol assumes ONE gameplay lane.** Three on one checkout collide
unless ownership is written down.

| Lane | Owns, exclusively | Phases |
| --- | --- | --- |
| **LEDGER** | `campaign_state.gd`, `campaign.gd`, `item_definition.gd`, `chassis_definition.gd`, `Campaign/items/*.tres`, `Campaign/chassis/*.tres`, the new `Location` | 0, 1, 2, 3 (data) |
| **FORCES** | `enemy_squad_spec.gd`, `enemy_force_spawner.gd`, `mission_definition.gd`, `Campaign/missions/*.tres`, capture, taps, heat, defend wiring | 4, 5, 5b |
| **BOARD** | `ops_table.gd`, `holo_board.gd`, `ops_table_ui.gd`, the fab-car catalogue, the turn driver, sim mode | 3 (UI), 6, 7 |
| **TERRAIN** | `maps/**`, `tools/build_*.gd`, `tools/block_*.gd`, both drone classes, the bunker kit | 8 |

**During Stage 1 this does not apply.** The slice is one agent across whatever
files it needs, because a prototype with four owners is not a prototype.

**Two seams cross lanes and need naming:**

- `campaign.gd` is LEDGER's. BOARD calls its API and never edits it; a change
  BOARD wants is a request, not an edit.
- `MissionDefinition` is shared by field — **LEDGER owns the economy fields**,
  **FORCES owns the force fields**. Same file, different lines, which works
  only if they are not open in the same session.

### The contract — stub it all on day one of Stage 2

This is what makes the parallelism real instead of nominal. Every signature
lands as a stub returning a sensible default before any of it is implemented,
so FORCES and BOARD compile and run from the first hour.

```gdscript
# LEDGER implements
Location.owner / resources_per_turn / compute / resistance
CampaignState.turn: int
CampaignState.held: Array[StringName]
CampaignState.is_held(id: StringName) -> bool
CampaignState.advance_turn() -> void
Campaign.exposure() -> int          # compute held
Campaign.act() -> int               # 1, 2 or 3
signal turn_advanced(turn: int)
signal site_taken(id: StringName)
signal site_lost(id: StringName)

# LEDGER implements, BOARD presents
Unlocks.is_open(id: StringName) -> bool
Unlocks.cost(id: StringName) -> int     # from supply tier, §3a
Unlocks.open(id: StringName) -> bool

# FORCES implements, BOARD and the level loader consume
ForceGen.compose(site: StringName, holder: int, act: int, defending: bool) -> Array[EnemySquadSpec]
ForceGen.budget(site: StringName) -> int    # the location's resistance, in supply
```

Without these stubs, three gameplay lanes are one lane and two spectators.

### Four-agent hazards, from this checkout specifically

**`test.sh` CANNOT BE RUN BY TWO LANES AT ONCE.** Its own header says why:
*"every suite points Settings and SaveSlots at the same `user://` probe paths,
so two at once would race on the same files and produce flakiness that looks
like a real failure."* This happened on 2026-10-11 and cost an hour chasing two
compile errors that were artefacts of the race.

> **`check.sh --changed` is the per-lane gate. A full `test.sh` run is claimed
> on the board before it starts**, and nobody else runs one while it is going.

**The Godot editor is open, and a half-finished multi-file edit makes it write
`null` into scenes.** On 2026-10-11 a two-file revert left an inconsistent tree
for seconds and the editor wrote four null exports onto the HUD node in
`Env/world.tscn` — which, because scene values beat script defaults, would have
replaced real floats with null. With four agents the odds go up. **After any
multi-file change, `git diff` the `.tscn` files too, not just the scripts.**

**Anything gameplay adds to a TERRAIN-generated scene gets deleted.**
`tools/block_prefabs.gd` rewrites those scenes from scratch. The working
pattern is already in the tree: `tools/fit_ops_table.gd` is idempotent, re-run
after every rebuild, and seats its nodes by script. Every new objective, spawn,
core or connection marker on a generated map goes in one of those — and with
TERRAIN rebuilding maps continuously through Stage 2 onward, this will bite
constantly otherwise.

**One item per lane, per the board.** Four lanes with two items each is eight
things in flight on one branch, which is how the checkout becomes
unreviewable.

### What the coordinator holds

The board, the contract above, arbitration when two lanes want the same file,
and the full `test.sh` slot. Everything else is lane-local.

---

## 1. THE SPINE: compute is your army AND your exposure

Everything below hangs off one idea, so it goes first.

Compute is already the cap on how much force you can field —
`supply_cap` rises by 1 for each point of compute `buy_supply()` holds, and a
Bulwark eats 3 of it. And in the fiction, compute is the one thing Home
Command is winning ground to secure **for Argus**. Every point you take is a
point that does not arrive.

So let the same number do both jobs:

> **The compute you have diverted is how visible you are.**

That turns the escalation from a timer into a decision. A player who takes
only what they need stays unnoticed and under-equipped for longer. A player
who seizes the whole board fields a real army and brings Home Command down on
themselves at turn ten. Neither is wrong, and the game never has to explain
the rule — *you are stealing more, so they noticed* is not a mechanic anyone
needs taught.

It also means the act structure is not punishment for playing. It is the bill
for how much you took.

## 2. Holding, not clearing

**Taking a site** pays a one-off, much reduced from today — enough to cover
the operation, not to fund the campaign.

**Holding a site** pays every turn. This is the whole economy now.

**Defending pays nothing.** The reward for a successful defence is that the
yield keeps arriving. This is deliberate: a defence that paid would make
farming attacks the optimal strategy, and the point of a defence is that it is
a thing you would rather not have had to do.

### A LOCATION IS A THING. A MISSION IS SOMETHING YOU DO TO IT.

The first draft derived income from `reward_resources`, which was wrong,
because it made the economy a property of **an operation** when it is a
property of **a place**. A site keeps paying long after the operation that
took it is over, and it pays the same whether that operation was easy or
hard.

So they separate:

| **Location** — new, persistent | **Mission** — an operation run against one |
| --- | --- |
| `owner` | which location it is on |
| `resources_per_turn` | assault or defence |
| `compute` | the force that holds it |
| `resistance` | its completion reward |

Maps are associated with a location. **The location owns the economy.** The
mission owns the fight.

#### Compute is ALL OR NOTHING

A location's compute is yours **in full while you hold it, and gone in full
when you lose it.** Not accrued per core, not banked on capture and kept
afterwards — held, exactly the way `compute_held` already works for seats and
software.

Which has a consequence worth stating plainly: **losing a site can put you
over your supply cap**, and something has to come off the roster. That is the
sharpest version of "territory is your army size" and it is the stake that
makes a defence matter.

There is no partial ownership. You take a location or you fail (§12.7), so
there is nothing for a fraction to describe.

#### RESISTANCE IS MEASURED IN SUPPLY, NOT IN SQUADS

The other thing the first draft got wrong, and it reaches into force
generation, heat and the briefing text.

**A squad is not a unit of anything.** Five Walkers and two riflemen are both
"one squad", and they are not remotely the same problem — the first is
**supply 15** and the second is **supply 2**. Rating a mission by expected
squad count describes nothing.

> **A location's resistance is the total supply of the enemy's spawn pool**,
> however it is divided up.

That single number does four jobs at once:

- **It rates the mission.** 15 is hard, 2 is not, and no one has to interpret.
- **It is the budget force generation spends** (§10) — compose squads from it
  however the site and posture want.
- **It is the pool heat commits** (§12.4). Dynamic allocation needs something
  finite to allocate.
- **It is what the player reads on the board.** Already true: `OpsTable`
  computes `"resistance": force["supply"]` today.

#### Mission rewards are separate, flat, and scaled by the fight

Taking a place pays a one-off that has nothing to do with what the place
yields afterwards. It is the operation being paid for, not the ground.

**Scale it off resistance** — what you seized was defended by that much, so
that is what it was worth. A 1–10 band derived from supply is enough; the
exact curve is a balance pass, not a design decision.

### The numbers, and where they come from now

`reward_resources` stops being the economy's input and becomes the operation's
payout. **`resources_per_turn` and `compute` are authored on the location**,
and the nine that exist today can be seeded from the old rewards as a starting
point rather than invented:

| Location | res/turn | compute | resistance |
| --- | --- | --- | --- |
| Hillfort | 8 | 1 | TBD — read from the force |
| Valley Basin | 13 | 1 | " |
| Coast Road | 18 | 1 | " |
| Over The Top | 23 | 1 | " |
| Three Rivers | 23 | 2 | " |
| Qamareen | 25 | 1 | " |
| Lockside | 30 | 1 | " |
| Polaris | 35 | 2 | " |
| The Causeway | 55 | 2 | " |
| **All nine** | **230** | **12** | |

Resistance is left blank deliberately: it should be **measured from the
authored forces**, not typed, and once force generation lands it is computed
rather than stored.

### Why these numbers, and the sanity check

Sized against a 20-hour campaign — ~55 operations (§9) on a board grown to
**19** locations:

| | |
| --- | --- |
| 19 locations at this rate | ≈ 480 res/turn at full control |
| × ~50% average ownership × 55 turns | **≈ 13,200** |

Against what the player has to buy:

| | |
| --- | --- |
| Squad of ~8, mixed sizes | ≈ 2,000 |
| Kit, 2–3 items each | ≈ 2,400 |
| Attrition, ~0.4 losses an operation net of scrap | ≈ 5,500 |
| ~15 unlock lines | ≈ 3,000 |
| | **≈ 12,900** |

Which is the fit. **The rate is a function of campaign length and board
size**, so it is the first thing to recompute if either moves.


## 3. The three acts

The escalation only works if the three enemies play differently. But
**differently means different armies with different objectives** — not three
sets of special rules. An earlier draft had Home Command withholding your
yield and recalling your garrisons, which was wrong on the fiction before it
was wrong on the design: **you are unnetworked from Home Command. It does not
control anything of yours.** It cannot recall what it never issued to a
process it has never queried.

### Act 1 — THE SWARM. A war over ground.

What the game is now. They want territory, they take it, you take it back.
Attritional and legible, and it teaches the loop.

### Act 2 — HOME COMMAND. The same war, against professionals.

Green. Better equipped and more aggressive than the Swarm, fielding tiers the
Swarm never had — and **the same frames you do**, because you are a Home
Command AKR and so are they. Free to implement, and the most chilling thing in
the act.

What changes is the quality of the opposition and the weight of the response,
not the rules. A location Home Command holds has a higher resistance for its
size and spends it on better things.

**It is not hunting you, exactly.** It is prosecuting the same war you are, in
the same direction, and you have become something standing in the way of it.
Nothing in the game ever says you were noticed.

### Act 3 — ARGUS. The thing the war was always for.

Also a faction, also on the ground, and holding **a large share of the world's
total compute** already.

What makes it different is what it wants. Argus is not trying to win a
territorial war — it is trying to **increase compute and hold orbital launch
sites**, so that it can put more compute and more materiel into orbit. Its
ground presence exists to protect launch capacity.

Which gives Act 3 its own map type and its own shape of fight:
**launch sites and the ground around them.** Those are locations with enormous
compute values and garrisons to match, and taking one is the only thing in the
campaign that meaningfully reduces what Argus can do.

It also closes the fiction. The player has spent the whole game diverting
compute from a thing that spends everything on itself — and Act 3 is finally
arriving at where that compute was going, which is up.

### Where the acts turn

Primary trigger is diverted compute; a count of operations is the floor so the
story cannot stall for a player who stays deliberately small.

| | Exposure (compute held) | or operations |
| --- | --- | --- |
| Act 1 → 2 | 8 | 14 |
| Act 2 → 3 | 16 | 30 |

Against a campaign total of about 23 compute those land near the thirds. Tune
the thresholds, not the structure.

Since a turn is a mission (§5), the right-hand column is **operations played,
not time elapsed.** Exposure is the real trigger and should fire first for
anyone expanding at all.


## 3a. COST IS A FUNCTION OF SUPPLY

Twenty-seven chassis priced individually is twenty-seven balance arguments and
twenty-seven chances to get one wrong. **Price the tier, not the frame.**

> **Every chassis of the same supply costs the same.** Equipment is tiered the
> same way.

Supply already measures what a frame takes up — it is the game's own answer to
"how much room does this thing need" — so letting it set the price means a new
frame added next year is priced correctly by existing, without anybody
remembering this section exists.

### The three tiers, as they fall out of what is authored today

| Supply | Count | Chassis |
| --- | --- | --- |
| **1** | 10 | Soldier · Chaser · Leaper · Mechanic · Lance · Marksman · Rifle Trooper · Shotgun Trooper · Spotter Drone · Quadcopter Bomber |
| **2** | 9 | Rover · Reclaimer · Drayman · Picket · Kite · Broodcarrier · Heavy Rifleman · Lobber Rover · Mortar Track |
| **3** | 5 | Walker · Vessel · Bulwark · Bastion · See-Engine |

Three at supply 0 — **Nest** and **Watcher** are structures and not bought,
and **Diver is almost certainly an authoring slip** at supply 0 with a cost of
60. Worth checking before the table is applied.

### Placeholder prices, and the shape they should have

The exact numbers are a balance pass. The **shape** is a design choice and
should be settled now:

| Supply | Buy | Open the line |
| --- | --- | --- |
| 1 | 100 | 200 |
| 2 | 260 | 520 |
| 3 | 520 | 1,040 |

**Super-linear on purpose.** Supply measures *room*; cost measures
*capability*. A Bulwark takes the space of three riflemen and is worth a great
deal more than three riflemen, so it should cost more per point of supply, not
the same. Linear pricing would make big frames strictly efficient and the
roster would collapse onto them.

Today's authored costs are all over the place inside a tier — Soldier 50 and
Quadcopter Bomber 220 are both supply 1 — so this is a real change and not a
tidy-up.

### Equipment, the same way

Items currently run 0–260 with no structure. Band them, and price the band:

| Tier | What belongs in it | Buy | Open |
| --- | --- | --- | --- |
| **I** | Grenades, smoke, scanners, repair kits | 40 | 80 |
| **II** | Carbines, side-grade weapons, armour plate, harnesses | 110 | 220 |
| **III** | Launchers, autocannon, mortars, the Mark line | 240 | 480 |

**Unlock is 2× buy throughout**, which keeps the rule from `PAID_UNLOCKS`:
you commit two copies' worth before owning one, so a line pays off across a
squad and never for a one-off.

### What this is worth beyond tidiness

- **One number changes a whole tier.** Rebalancing is three edits.
- **New content prices itself.** The ten new frames need a supply value, which
  they need anyway, and nothing else.
- **It reads.** A player learns "supply 2 costs 260" once, and then knows the
  price of everything they have not unlocked yet.


---

## 4. The map grows with the acts (9 → 15 → 19)

A reason to expand that is not "more content":

- **Act 1 (9)** — the nine authored territorial sites, Swarm-held.
- **Act 2 (+6)** — Home Command's own installations appear: depots, relay stations,
  the places that were notionally *yours*. That is the act's whole idea
  rendered as geography.
- **Act 3 (+4)** — **orbital launch sites**, which is what Argus is actually
  defending. Enormous compute, garrisons to match, and the only targets in the
  campaign that reduce what Argus can do.

This also gives TERRAIN a planning horizon rather than a list.

## 5. A TURN IS A MISSION. Not a span of time.

Decided, and it removes the worst risk in the design. There is no clock. You
attack a place, that is a turn. You defend a place, that is a turn. Nothing
happens between them because there is no between.

Why this is the right call and not just a simplification:

- **The strategic layer cannot out-run the player.** In Galactic Conquest a
  turn costs a few seconds, so the enemy acting every turn is free. Here every
  action is twenty minutes of play, and a time-based campaign would generate
  two missions per turn of progress. Tying the turn to the action makes that
  mismatch structurally impossible.
- **Nothing happens while you are not playing**, so you can never return to a
  campaign that got worse in your absence.
- **The player holds the clock.** Stop acting and nothing advances — but
  nothing pays either, because income only arrives on a turn.

**Which reframes the economy, and the new framing is better.** Holding ground
does not pay you while you sleep. It pays you more for every operation you
run. Territory is a multiplier on operating, not a salary.

### The enemy moves every 2–3 turns

Not every turn. So the texture is a run of your own operations punctuated by
having to answer for one, rather than alternating tit-for-tat.

**Most of those answers auto-resolve against the garrison.** A playable
defence is generated when the result is genuinely in doubt, or when you choose
to take it rather than accept the auto-resolve. Playing one is therefore
something you do to *save units*, not to collect — which is consistent with
defences paying nothing.

### THE HOLE THIS OPENS: farming turns

If a turn is any mission, and holding pays per turn, then **the cheapest
mission available becomes the optimal way to collect income.** Hold ten sites
at 400 a turn, replay something trivial, bank 400. That is a farm, and it is
the one thing this model makes easy that the time model did not.

The fix is that a turn is a **board action**: attacking a site you do not
hold, or resolving a defence. Re-running a site you already own is not a board
action, so it advances nothing and pays nothing.

Which leaves a gap worth filling deliberately rather than by accident: there
is then no way to play without committing. **Make that the Sim Arenas.** Three
of the twelve sites are literally simulations, they are the three cheapest on
the board, and a simulation is the one place where running an operation can
cost nothing and change nothing. A safe room to test a build before taking it
somewhere real.

And the board already agrees: `OpsTable.ADJACENCY` has **nine** sites in it.
The three arenas are not on the graph at all, so they were never territory —
which means nine holdings, not twelve, and the yield curve in §2 is measured
against the richer nine rather than padded by three trivial ones.

## 6. GARRISONS ARE FREE AND COME WITH THE GROUND. Decided.

No pool, no distribution, no build cost, no screen. Take a site and it is
defended. The player can never have a bad campaign because they forgot to
garrison something, and there is nothing to implement beyond a number the
auto-resolve reads.

It also settles the old question by making it moot: garrisons were never going
to fit in `supply_cap` anyway — the campaign pays **32 compute in total**, the
cap starts at 4, and a point of compute buys a point of supply, so total map
control is **36 supply, twelve big frames**, for every garrison *and* the
strike force. Now nothing competes: the strike squad stays entirely the
player's, which is right for robots you have named, kitted and carried.

### But "free" does not say HOW STRONG, and that is where the whole game is

The obvious sizing is wrong. If garrison strength tracks site value, your
richest sites are your safest and your poorest churn — so the thing worth
losing is never threatened and the thing not worth defending is nibbled
forever. That is the worst of both: no tension where it matters, irritation
where it does not.

**Flat strength, and let the enemy target by value.** Then Causeway at 110 a
turn is as attackable as Hillfort at 16, the enemy goes for the throat, and
losing a site actually costs something.

### Depth is the defence, and the board already knows it

`OpsTable.ADJACENCY` is a nine-site graph with eleven borders. Use it:

> **A site can only be attacked if it borders ground you do not hold.**

Interior sites are untouchable. The frontier is the entire defensive game.

Two things fall out of this for free, with no new data and nothing to explain:

- **Consolidating is a real strategy.** A compact holding has a short frontier.
  A sprawling grab has a long one and bleeds.
- **The map's existing shape becomes meaningful.** Causeway — the richest site
  at 110 a turn — has **degree 1**, sitting behind Polaris as a dead end. Take
  Polaris and Causeway can never be touched. Reach for Causeway first and it
  is a salient with an open flank. The campaign rewards doing it in the right
  order, and the graph was already drawn that way.
- Pittsburgh is the hub at **degree 4**: the crossroads, and the hardest thing
  on the board to hold.

So the answer to "what stops you taking everything" now has two halves, one
strategic and one tactical: **exposure** is who is looking at you (§1), and
**frontier length** is how much of that attention you can survive.


## 7. What does not exist yet

Honest inventory before anyone estimates this:

- **No turn counter.** Nothing in `CampaignState` tracks elapsed time.
- **No ownership.** `completed_missions` answers "ever cleared", and the code
  says so itself: *"completed_missions only answers 'ever', which is not
  enough"*. Held-vs-cleared is not modelled anywhere.
- **No per-turn income.** The board already prints `RES n /turn`, but
  `OpsTable._per_turn()` is literally `one_off × 0.1` — **it is advertising
  income the game does not pay.**
- **No second or third faction in the campaign layer.** `Enums.Factions`
  already has `SWARM`, `HOME` and `ARGUS`, so the vocabulary exists and
  nothing uses the latter two.
- **`repeatable` exists on every mission and is false everywhere.** It is the
  flag a defence mission needs.
- **Eleven of twenty-seven chassis are priced at 0**, which a derived economy
  cannot work around.

## 8. The save question, which needs signing off

A turn counter and a held-sites set are both new persisted state, and
ownership cannot be derived from `completed_missions` without losing the
distinction the whole layer depends on. `SAVE_VERSION` exists to switch on,
and existing saves can migrate by treating every completed mission as held —
which is approximately true today and is the only reading that does not take
anything away from a player mid-campaign.

**ANSWERED in §16.1, 2026-10-12.** It is not a format change: `from_dict`
defaults every field and `migrate()` is a passthrough, so new fields load into
old saves untouched. The only live question is whether an old save's completed
missions backfill as sites it holds. **Answered: wipe and restart**, so no
migration is written and `SAVE_VERSION` stays at 1.

## 9. SIZED: 19 maps for 20 hours, and there are 9

A turn is a mission, so campaign length is a content budget. Measured against
10–20 minutes an operation plus 5–10 minutes in the squad manager and the
factory between them, and the enemy moving every 2–3 turns so roughly 40% of
operations are defences:

| | |
| --- | --- |
| Minutes per operation | 14 fast · 29 slow · **~22 centre** |
| 20 hours | **≈ 55 operations** (41 fast, 85 slow) |

**What exists: twelve missions on ten maps, and the three Sim Arenas share
`proving_level.tscn` — so nine territorial maps.**

55 operations across 9 maps is **6.1 plays of each**. Defences play
differently from attacks, but it is the same terrain either way, and about
3–4 plays is what a map carries before the player is walking a route they
already know.

| | |
| --- | --- |
| At 3.5 plays a map, 9 maps gives | 32 operations ≈ **11.5 hours** |
| 20 hours at 3.5 plays a map needs | ≈ 16 maps |
| **20 hours at 3 plays a map needs** | **≈ 19 maps — TEN MORE. This is the plan.** |
| So one new map is worth | 3–3.5 operations ≈ **1.1–1.3 hours** |

Which turns the act expansion in §4 from flavour into the content budget:
**9 locations in Act 1, +6 Home Command installations in Act 2, +4 orbital
launch sites in Act 3. Nineteen.**

If environment art is cheap, **buy breadth rather than repetition**: more
sites played fewer times each is strictly the better experience, and it is
the difference between a chain of nine and a theatre of nineteen. A
nineteen-site board also makes the frontier rule in §6 bite properly — you
cannot hold everything, so which direction you expand becomes the campaign.

And if it is not cheap, say so and stop at nine: **a tight 11-hour campaign on
nine strong maps is a better game than a padded 20-hour one on the same
nine.**

## 10. REFRAMING MISSIONS: one place, two operations, generated forces

Today a mission is a place *and* a fixed opposition welded together. Under the
conquest layer the place is permanent and everything else is a variable: who
holds it, how rich they are, which act it is, and whether you are the one
arriving or the one already there.

### THE GOOD NEWS: the schema already has the seam

`EnemySquadSpec` separates **where and how** from **what**:

| Authored — the set-piece | Generated — the composition |
| --- | --- |
| `post_tag`, `route_tag`, `spawn_tag` | `roster` |
| `posture` (PATROL / GARRISON / ADVANCE) | `count` |
| `wake_after_kills`, `wake_after_seconds` | `forced_weapons`, `kit_variance` |
| `reinforcement_tag`, `always_active` | |

So the reframing does **not** mean throwing out the authored encounters. The
Coast Road's "bombers for the bridge, armour for the craters, everything they
have left for the town" is expressed in tags and wake triggers — the *shape*
of the fight — and that survives untouched. Only which chassis stand in those
positions, and how many, becomes a function.

That is the difference between a rewrite and a substitution, and it is the
reason this is Phase 4 rather than Phase 1.

### What a force is a function of

> **force = compose(budget, roster, posture, site)**

- **Budget** — what the holder can afford to garrison this site with. Scales
  with the site's own value, the holder's economy, and the act.
- **Roster** — what that faction fields. The Swarm has its own frames. **Home
  Command fields yours**, because you are a Home Command AKR and so are they —
  which costs nothing to implement and is the most chilling thing in Act 2.
- **Posture** — defenders get emplaced and static, attackers get mobile. The
  same site plays differently depending on which way the operation runs.
- **Site** — a trench map and a city want different compositions out of the
  same budget.

### Worked: Coast Road, turn 45, Home Command holding, you attacking

| | |
| --- | --- |
| Site value | 700 one-off → 18 res/turn, a mid position |
| Act | 3 — budget multiplier at its highest |
| Holder | Home Command, so the roster is the player's own catalogue |
| Posture | GARRISON at the authored relay posts, ADVANCE on the authored wake triggers |
| Result | The same four relay positions, the same escalation triggers, now held by Bulwarks and Walkers with cluster launchers instead of early Swarm infantry |

The bridge is still the bridge. What is standing on it is not.

### The two operations

**Assault** is what every mission is today: you arrive, the holder is dug in,
you take it.

**Defence** reverses the flow — you start on the ground, your garrison spawns
with you, and the attacker arrives from the frontier edge. It needs from each
map: an attacker approach, and a thing worth standing on. §11 notes that
**eight of the nine maps were drawn as corridors with an entrance and an
exit**, which makes them poor defences, and that this is the single biggest
content gap the conquest layer creates.

### The briefings go stale, and that is fixable in a good way

Every briefing today describes a specific force — *"Four hives, armour at
every relay, repair crews behind their line."* Generated forces make those
lies within one patch.

**Split them.** The authored briefing describes the **place** and the shape of
the operation, which never changes. A generated line underneath reports the
**opposition**, which does. That is also how a real tasking reads: the ground
is known, the garrison is intelligence.

## 11. The nine maps you have, and what is missing

### As vibes

| Map | What it is | Tactical register |
| --- | --- | --- |
| **Hillfort** | A relay dish on an iron-age hillfort, 130 m up. One way on and it is uphill the whole way: cistern, standing stones, old gate, terrace under the walls. Watcher masts on the flanks keep calling groups down on you while they have eyes. | Vertical corridor. A climb under observation. |
| **Valley Basin** | A tether anchor in a bowl, trenches round it, a watchtower south. In at the west pass, ten seconds at a console, out at the east. | Open bowl, dug-in garrison, timed hold. |
| **Coast Road** | A road east with everything dug in along it — bridge relays, a crater field, a town. Each relay you take calls something different: bombers, then armour, then everything left. | Linear corridor, escalating set-pieces. |
| **Over The Top** | Held nine weeks, shelled for six. Four lines in depth with the tubes behind the last. | Frontal assault through layered defence. |
| **Three Rivers** | Three rivers, a fort on every bend, five relays in separate valleys, gunships over the ridges. The biggest map in the game. | Sprawling theatre. You choose the order. |
| **Qamareen** | A city, second pass. Dense enough that its navmesh needed a coarser bake to stop costing 0.69 ms a query. | Dense urban. |
| **Lockside** | The canal on its terrace, mills along it, town above, waterfront below. Four flat benches, not a slope. Ashore at the bottom, uphill all of it. | Terraced waterfront, vertical town. |
| **Polaris** | A mall as one irregular mass with its anchors as lobes. "Not an advance. You go in, you start the drain, and then you hold." | Siege. The only hold-out on the board. |
| **The Causeway** | Two kilometres, three fights, none of them the same. Spans end to end, one cracked, one broken. | Long crossing. Chokepoints over water. |

Plus **Proving Ground**, shared by the three Sim Arenas: three lanes, low
walls you can shoot over and tall ones you cannot, a tower in the middle. The
practice track.

### The gaps, in the order they matter

**1. EVERY MAP IS SHAPED LIKE AN ATTACK, AND 40% OF OPERATIONS ARE DEFENCES.**

Land at one end, push through, exit at the other. Polaris is the single
exception and it says so in its own briefing. Under the conquest layer, two
operations in five are played on ground you already hold against someone
coming to take it — and a corridor with an entrance and an exit is a bad
defence, because there are no flanks to cover and no reason to be anywhere in
particular.

A defence map wants **several approaches converging on something worth
standing on**. None of the nine were drawn that way. This is the biggest gap
and it is the one the conquest layer creates. §10 is where the two
operations are specified.

**2. NOTHING IS INDOORS.** Nine outdoor maps. The only interior in the project
is the railhead, and that is the base. Interior fighting is a different game —
no long sightlines, doorways as chokepoints, orders given at a range where
you can see what you are ordering. For a squad-command shooter that is a
whole register currently unused.

**3. EVERYTHING IS THE SAME SIZE AND THE SAME LENGTH.** Hillfort pays 8 a turn
and Causeway 55, but both are a full operation. **Cheap sites should be small
maps.** If every one of 55 operations is twenty minutes the campaign is 25
hours, not 20 — the short ones are what make the budget work, and they also
make losing a minor holding something you shrug at rather than resent.

**4. ONE LIGHTING CONDITION.** All daylight. A night or weather map would
change what the scanner, the optics and the Watcher masts are worth, and the
game already has the screen filter to sell it.

**5. NO HOME COMMAND ARCHITECTURE, WHICH IS SIX OF THE TEN NEW MAPS.** Act 2
is your own side turning on you, so its sites are **Home Command
installations** — and they should read like the railhead does, in green panel,
brass and stencil, not like Swarm-held ruin. That is a new visual family, and
it is the act's whole idea rendered as geography.

**6. NO MAST SITES.** Act 3's four. The vocabulary exists — `block_railhead.gd`
calls the station mast *"the one Home Command object with a reason to exist,
because it is why you still get briefings"* — and a mast is a landmark
visible across a map, which makes the Act 3 sites instantly readable as a
different kind of target.

### So the ten new maps roughly write themselves

| | |
| --- | --- |
| **Act 2 — six Home Command installations** | a depot, a marshalling yard, a fabrication works, a relay station, and **two deliberately defence-shaped** |
| **Act 3 — four launch sites** | at least one interior, at least one small and fast, at least one at night |

Which fills the content budget and the variety gaps with the same ten maps,
rather than treating them as separate problems.

## 12. IN-MISSION GROUND: what you take, how, and what it leaves behind

Everything above is the board. This is what happens on a map once holding
ground is a thing that can be lost — and it reaches back into the board,
because what a captured site looks like next time you stand on it is the
clearest signal in the game that it is yours.

### 12.1 The root cause is one line long

**Objectives are a checklist, not a state.** There is no `uncomplete`, no
`completed = false`, nothing in `Campaign/` that can take a finished objective
back. `EliminateObjective`, `InteractObjective` and `ReachObjective` are
monotonic by construction.

So when the enemy pushes onto a relay you took on Three Rivers, they can stand
on it. They cannot have it. Everything below follows from fixing that.

### 12.2 WHAT A CAPTURE POINT IS — and it is already built

The question "what are the objectives actually, and how does capture work" has
an answer already sitting in the repository:

`Env/world_objects/compute_core_point.tscn` — a node called **CapturePoint**,
made of a **Core**, a **Terminal** and a drift of **Motes**, scripted with
`interact_objective.gd`, configured `channel_duration = 3.0` and
`channel_range = 4.5`. It ships in three sizes:

| | footprint | height |
| --- | --- | --- |
| small | 1.88 m | 4.19 m |
| medium | 3.38 m | 6.97 m |
| large | 5.19 m | 12.38 m |

**So a capture point is a compute core, and that is exactly right**, because
compute is what the entire war is for. Home Command wins ground to secure
compute for Argus; the player is an error diverting it. Taking a site means
standing at its cores and turning them over. Nothing has to be invented and
nothing has to be explained.

**It also makes site value visible from across the map.** A site's yield is
the cores standing on it: an outpost at 8 a turn has one small core, the
Causeway at 55 has large ones. You can read what a place is worth by looking
at it, which is worth more than any number on a board.

### 12.3 How capture works — YOU work it, THEY shoot the ANCHOR

**You run the channel yourself.** Not a squadmate, and not an order — the core
loop of the game cannot depend on an AI pathing to a terminal, and a capture
that fails because a robot got stuck on a doorway is a capture that fails for
no reason the player can see or fix.

Then:

1. You work the terminal. Short — 4–6 seconds. A hostile in
   `channel_range` contests it; `channel_resume_grace` already covers stepping
   out and back.
2. Completing it **calls a tap**. A drone flies in across your view and comes
   down on the core.
3. **It lands and becomes a CAPTURE ANCHOR** — the pod is a delivery, the
   anchor is the thing that holds the core. The core is yours from the moment
   it lands, and starts paying.
4. **The anchor is a structure with health that the enemy can target.** Bring
   it down and the core goes **back to whoever held it before you took it**.
   Shooting the anchor off simply undoes the capture.

#### BUILT, and the anchor has to be a Nest

The original plan said "a shootable object", which turned out to be the wrong
shape for this codebase. `AIManager.hostiles_for()` only ever scans `all_ai`,
and `register_enemy()` is typed `AI` — so a thing has to BE an AI to be
targeted at all. A StaticBody3D with `apply_damage` can be shot by the player
and will never be shot by anyone else.

So `Character/characters/ai/capture_anchor.gd` extends the **Nest**, which
`docs/BOARD.md` already calls "a structure that does not move, and the first of
many enemy structures", and whose own header says that with no hatchlings it is
"an ordinary building with health". It is a CharacterBody3D on the PLAYER
faction with 160 HP, registered the way every other body is — so it is
acquired, shot, downed and counted for free.

#### Why the two sides capture differently, and why that is right

This asymmetry is deliberate and it is what makes the whole thing buildable:

| | You | Them |
| --- | --- | --- |
| Take a core | Work the terminal | — |
| Take one back | Work the terminal again | **Shoot the tap off** |

**No AI capture behaviour is needed anywhere.** Shooting a thing is something
every enemy in the game already does. Recapture-by-channel would have meant a
new AI behaviour, new pathing reliability requirements, and a failure mode
nobody could read; recapture-by-shooting needs none of it.

It also reads correctly: you are a precision instrument working a terminal,
and they are a mass that pulls your equipment off the wall.

#### The vulnerable window is the DOCKED tap, not the flight

An earlier draft had the drone contestable on approach. That is not fun — a
tap shot down five hundred metres away, by something you cannot see and could
not have reached, is a loss you had no play against.

**So the flight is spectacle and the dock is gameplay.** The drone arrives
reliably. What you then have to defend is a thing sitting on the core in front
of you, which you can see, shoot back around, and station the squad on.

#### Taps are unlimited — but one per core, and only one

No inventory, no carrying, no counting. **What you cannot do is stack them:**
one tap per core, and a second cannot be called while the first lives.

So losing a tap costs you the walk back and the terminal again, under whatever
pressure the map is under by then. That is the right cost — it is paid in
exposure and time rather than in a number, and it keeps the decision on the
map instead of in a loadout screen.

#### Feedback belongs in the world

The prefab already carries a `Motes` particle system. That is the channel:
Swarm amber drifting out, stalling and reversing while contested, settling to
Home green when the tap lands. A bar on the HUD is fine, but **the thing you
are looking at is the thing that should tell you** — and a core's state must
be readable from across a map, because the whole mission is about which ones
you still hold.

### 12.4 Heat — the in-mission mirror of exposure

The campaign has exposure: take more, they come harder (§1). A mission wants
the same curve on a shorter clock.

**Heat rises with time and with how much of the site you hold**, and is spent
directing counter-attacks at your weakest held point. Not a timer punishing
slow play — pressure that grows *because you are winning*, which is a very
different feeling and the right one.

The parts exist. `EnemySquadSpec.Posture` already has **GARRISON** (*"dig in
at post_tag"*) and **ADVANCE** (*"push to post_tag"*), with waves on
`reinforcement_tag` and `wake_after_kills`. What is missing is something that
picks the target instead of an author picking it. Authored waves stay for
set-pieces; the ambient pressure between them is generated.

### 12.5 THE REAL PAYOFF: this is what makes squad command matter

Today the squad is an escort. You capture, they follow, you move on, and
nothing you leave behind can be lost — so no mission ever asks you to divide
them.

With capture-back, holding means **leaving people on the taps**. Two of Bravo
stay covering the one you just landed while you go and work the next terminal
yourself. A cost, a risk and a decision, three times a mission, in a game
whose entire premise is commanding a squad — and it needs no new order verb,
because DEFEND already does exactly this.

It costs nothing extra: the orders exist, the capture points exist, and DEFEND
is already a squad objective.

### 12.6 CONNECTIONS: the adjacency graph is physical

**A site's edges on the board are real places on its map** — tunnel mouths,
rail cuts, lift heads.

- **You enter through a connection you already hold**, not a fixed spawn.
- **You win by taking the site's connections**, which is what owning a place
  on a rail network means.
- **A map has as many entrances as its degree.** The Causeway has one. **Three
  Rivers has four** — which is exactly why the graph already made it the
  hardest thing on the board to hold.
- **The frontier rule stops being abstract.** You can attack a neighbour
  because you hold a tunnel into it. Not a rule, a route.

And it closes the loop with the railhead: the train arrives at a mouth you
hold, which is what the departure ride was already built to do.

### 12.7 THE BUNKER: take it and hold it, or lose the squad

Extraction is deleted, and **so is withdrawal.** There is no leaving early,
no taking what you got and going home. An operation ends one of two ways.

**The bunker is a separate, always-marked place on every map** — the way down
into the network. Not the last capture point in a chain, which would force
all nineteen maps into the same beat order. A place.

| | |
| --- | --- |
| **Assault** | Arrive from outside. Take the cores. Take the bunker. Hold it. |
| **Defence** | You start at the bunker, having come up from below. You end by going back down. |

#### A real failstate — and YOU DO NOT LIVE JUST IN YOUR BODY

Fail to take and hold the bunker and the operation fails. What that costs is
**materiel, not you**: some of the squad does not come back, and the frame and
kit you were wearing have to be rebuilt.

That is not a softened punishment, it is the correct one for this fiction. The
player is a process, never authorised and on no roster — a chassis is hardware
it is running on. Losing the body is expensive. It is not death, because there
is nothing in the premise that dies.

Today a failed mission resets to before it, which costs nothing and is why no
operation has ever been frightening. This is where the attrition the economy
assumes (§2) actually comes from.

#### AND THE CORES ARE WHY. The win condition is causal, not a checklist

Here is the part that makes the structure work rather than just be a list:

> **Every core still in their hands feeds the counter-attack on your bunker.**

Take the bunker with three cores still theirs and they will come and take it
off you, from three directions, for as long as you stand there. Clearing the
cores is not box-ticking — **it is how you turn the pressure off** so the
bunker can be held at all.

So the order is yours to choose and the consequence is legible either way:
go straight for the bunker and you will hold a doorway against everything the
site can still produce, or clear first and walk into a quiet one. Both are
playable. Only one is survivable late in the campaign.

This also means §12.4's heat has a source rather than a schedule: **heat is
what enemy-held cores emit.** A site at one core left is a trickle. A site
untouched is a flood.

### 12.8 ARRIVAL: by air to attack, by rail to defend

Right now you appear. That is the weakest moment in the loop and it is load
bearing — it is the first ten seconds of every operation.

> **Assault = you arrive by air. Defence = you arrive by rail.**

An assault is on a site you do not hold, so there is **no connection to come
through** — you have to come from outside. A defence is on ground you hold, so
you come up out of the ground. **How you arrive tells you what kind of
operation this is before anything is said**, and taking a site visibly
converts it: the first time you fly in, every time after you come up the
stairs.

The approach also does real work beyond looking good. An aerial run-in over
the site is a **free tactical read** — the terrain, the cores, the shape of
the defence, the bunker you will have to reach — which is what Arma and Squad
get out of the same shot. It can carry the briefing, and the briefing screen
can then die.

### 12.9 TWO DRONE CLASSES, and they are new models

Both are new art. They are also the same family, which is the argument for
building them together.

| | **Heavy lifter** | **Tap** |
| --- | --- | --- |
| Job | Carries the squad in and out; services the bunker | Docks on a core and holds it |
| Scale | Large. Outdoors only | Small. **Must work indoors** |
| Seen | Arrival, stand-down, and building the stop | Every capture, on every core |
| Shootable | No — it is a cutscene, not a target | **Yes. That is the recapture.** |

The tap being small is not a detail — **interiors are one of the content gaps
in §11**, and a capture mechanism that only works under open sky would rule
out every interior map before one is drawn.

#### The stop, and what persists

Once the site is yours, lifters bring in the stop: a platform and a lit portal
where there was a blast door, in the green and brass the railhead already
uses. You watch it happen on stand-down; you do not defend it. Making every
operation end with "survive while the builders work" would make all nineteen
end identically, and §12.7 already supplies that tension where it belongs.

Then it **stays**. Next time you are on that map the stop is there and it is
your entrance. Nineteen sites that visibly become yours is the strongest
ownership signal a conquest game has, paid for once each, from a kit of parts
TERRAIN already owns the vocabulary for.

**Taps do not change across the acts.** An earlier draft had Home Command
denying tap requests in Act 2 and recalling them in Act 3; that is cut. The
escalation lives where §3 puts it — better-equipped opposition in Act 2, and
in Act 3 a faction defending launch capacity with everything it has — and the
capture mechanic stays the one thing the player can always rely on.

### 12.10 What it does to the nine maps

| Map | Degree | The change |
| --- | --- | --- |
| **Valley Basin** | 3 | The east pass stops being an extraction and becomes an onward connection |
| **Three Rivers** | 4 | Four mouths, four ways the counter-attack arrives. The hub earns its degree |
| **The Causeway** | 1 | One connection at the far end of two kilometres. The map is the approach to it |
| **Hillfort** | 2 | In at the trail, on over the top — the climb now goes somewhere |
| **Coast Road** | 2 | Already a corridor with ends. The least work of the nine |
| **Polaris** | 3 | Already a hold-out. Closest to the new shape as authored |

The other three need connections placed, which is small TERRAIN work: a mouth
is a marker and a kit piece, not a new map.

### 12.11 What does not exist

- **Reversible objectives.** Capture as *state* rather than completion. The one
  structural change; everything else hangs off it.
- **The tap** — as an object, as a finite carried resource, and as a thing with
  hit points that reverts a core when it dies.
- **An in-mission commander.** Nothing accumulates heat or picks a target;
  waves are authored triggers.
- **A failstate.** A lost operation resets today. Losing the squad does not
  exist.
- **Connection and bunker markers**, and any notion in the adjacency graph that
  it is describing places.
- **Arrival modes.** `SpawnPoint` is a fixed node; nothing passes "you came
  from Polaris, by rail" into a level load.
- **Both drone classes**, as models and as sequences.

### 12.12 Settled, and what is left open

**Settled in this pass:** you work the terminal, they shoot the anchor it
leaves · the
vulnerable thing is the docked tap, never the drone in flight · **taps are
unlimited, but one per core at a time** — you cannot stack them, and a dead
one can be replaced by going back and working the terminal again · no
withdrawal, ever · failing to hold the bunker costs materiel and the squad,
not the campaign · enemy-held cores are what generate the pressure on it ·
assault arrives by air, defence by rail · taps behave identically in all three
acts.

**Open:**

- **Where the failstate lands in the campaign.** Losing the squad costs the
  roster, the turn and the site — but whether it can cost the *campaign* is
  the difference between a tense game and a cruel one.
- **How many taps per operation.** This is the dial that decides whether a
  five-core site is a stretch or a formality.
- **Does heat have a ceiling?** With cores as the source it self-limits —
  clear them and it stops — so it may need none, which would be the tidy
  answer.

---

## 13. THE BUILD — split by the kind of work it is

Three categories, because they are three different people and they block each
other in one direction only: **conceptual gates art, art gates nothing, and
gameplay can start against stubs.**

### 13.1 CONCEPTUAL — still to be designed or decided

Nothing below can be estimated, because nobody has decided it yet. **This is
the critical path**, and most of it is cheap in hours and expensive in
calendar if it waits.

| | What it is | Who decides | Blocks |
| --- | --- | --- | --- |
| **Save-format sign-off** | A turn counter and held state are new persisted fields | **You** | Phase 1, and through it 2, 5, 6 |
| **Three tier prices** | §3a. Cost by supply means three numbers settle all 27 chassis and all 36 items | **You** | Phase 3 |
| **Campaign failure** | Losing an operation costs materiel (§12.7). Whether it can cost the *campaign* is the difference between tense and cruel | **You** | Phase 5b |
| **THE_BUNKER** | Hold conditions, how long, what exactly is lost | Design | Phase 5b |
| **CONNECTIONS** | Adjacency as geometry; the portal kit; 19 placements | Design + TERRAIN | **Phase 8 — every map** |
| **ARRIVAL** | The approach shot, what it shows, whether it carries the briefing | Design | Phase 5b |
| **DRONE_CLASSES** | Silhouettes and behaviour for both | Design + TERRAIN | Art, below |
| **FORCE_GENERATION** | The compose function; faction rosters | Design | Phase 4 |
| **ACT_FACTIONS** | Rosters and resistance curves for Home Command and Argus | Design | Phase 7 |
| **The opening unlock tier** | What the first two or three operations can afford | Design | Phase 0 |
| **Heat and tap tuning** | Rates, thresholds, pool sizes, channel durations | Design, then play | Phase 5b |

**CONNECTIONS is the one to start today.** It is the only outstanding concept
that all nineteen maps need rather than one system, and TERRAIN cannot draw a
map without knowing what a connection is.

### 13.2 ART, FX AND SFX

The core already carries a `Motes` particle system, so a good deal of the
capture feedback is a recolour rather than a new asset.

**Models**

| | For | Notes |
| --- | --- | --- |
| **Heavy-lift drone** | Squad in and out; building the stop | Outdoors only. Never a target — it is the shot, not the fight |
| **Tap drone** | Docking on a core and holding it | **Must fit indoors.** Interiors are a content gap already (§11) |
| **Bunker / portal kit** | All 19 maps | Two states: sealed blast door, open lit platform |
| **The stop** | What lifters build on a taken bunker | Green and brass; the railhead has the vocabulary |
| **Home Command installations** | Act 2's six maps | Depot, marshalling yard, fab works, relay station |
| **Launch sites** | Act 3's four | Pads, gantries, the ground that protects them. The mast in `block_railhead.gd` is the vocabulary |
| **Ten new maps** | §9 | Two defence-shaped, one interior, one small, one night |

**FX**

| | Where |
| --- | --- |
| Core state motes — amber out / stalled / green inward | Every core, every state |
| Light climbing the shaft, base to head | OVERRIDE beat |
| Panels rotating to face the player | CONTACT beat |
| Light stuttering and falling back | Contested |
| **The beacon** — a vertical line visible across the map | On COMMIT |
| Tap dock, and tap under fire: sparks, canted attitude | Every held core |
| The stop being built | Stand-down, once per site |
| Aerial arrival | Every assault |

**SFX** — currently there is none of this at all

| | Where |
| --- | --- |
| Handshake tone, two notes | CONTACT |
| Rising third, stepping as the light climbs | OVERRIDE |
| A mechanical thunk | COMMIT |
| Flare, then approach audio growing | Tap inbound |
| A latch, then the core hums | Dock |
| An audible fault | Contested |
| The hum going sour | Tap damaged |
| **Engines further off than anything you can see; comms chatter rising** | Heat building — this is the main read |
| Arrival | Air and rail, two different beds |

### 13.3 GAMEPLAY

**In-mission**

1. Capture as reversible **state**; a core can be held by either side.
2. The tap: spawn, dock, hit points, death reverting the core to **its**
   **authored owner** — see B.4, where the earlier NEUTRAL rule was overruled.
3. One tap per core; a second refused while the first lives.
4. Beats inside the channel, with a signal per beat for art to hang off.
5. `channel_duration` per core size — 3.0 on all three today.
6. Heat accumulator: cores plus incursion.
7. A target chooser — reinforcements **ADVANCE on the player**.
8. A finite reinforcement pool per site, which heat spends.
9. Spawn-at-edge for forces that were not authored into the map.
10. The failstate: materiel lost, operation failed, turn consumed.
11. Arrival modes — air for an assault, rail for a defence.
12. Entry and exit resolved from campaign state, not fixed nodes.
13. Per-core yield, so partial holdings pay partially.
14. Heat inverted on a defence: theirs, on a schedule.

**Campaign**

15. Turn counter, held state, and the migration for both.
16. Per-turn income; compute on capture.
17. Unlock ledger on allocation keys.
18. Force generation — `compose(budget, roster, posture, site)`.
19. Defend mission variants.
20. Turn loop: board actions, enemy cadence, auto-resolve.
21. Frontier rule driven off `OpsTable.ADJACENCY`.
22. Exposure, act thresholds, two new faction behaviours.

**UI**

23. The fab-car catalogue, four line states.
24. The board: per-core holdings, real income, act state.
25. Briefings split — authored place, generated opposition.
26. A coarse heat read: *quiet · building · committed · spent*.
27. A capture toast, in the shape the order toasts already use.

### 13.4 Existing things whose MEANING changes

Cheaper than new code and more dangerous, because nothing looks broken.

| | Was | Becomes |
| --- | --- | --- |
| `reward_resources` | The payout | The per-turn divisor's input |
| `compute_reward` | The payout | Replaced by flat on-capture |
| `mission.unlocks` | How you got kit | Retired |
| `state.unlocked` | A flat array | Allocation keys |
| `LevelExit` | An extraction pad | The stand-down at a held bunker |
| `completed_missions` | Progress | Superseded by held state |
| Briefings | Place *and* opposition | Place only |
| `channel_duration` | A uniform 3.0 | Per core size |

---

## 14. WHAT LIVES OUTSIDE THIS DOCUMENT

Everything this plan needs is in here, including the appendices below. The
only briefs kept separate are records of things already built, or other
lanes' standing work:

| | |
| --- | --- |
| `OPERATIONS_TABLE.md` | The board — built and working |
| `OPS_TABLE_FURNITURE.md` | The table it stands on — built |
| `OPS_TABLE_LEVER.md` | The departure lever — built; housing outstanding |
| `DEPARTURE_RIDE.md` | Riding the train out — built |
| `NEW_FRAMES.md` | Ten frames the unlock tree needs priced |
| `MULTI_CLASS_NAV.md` | Navigation classes, which force generation will lean on |
| `SITE_CONVERSION.md` | **Written 2026-10-13.** The other eight maps, measured: cores, bunker, entries and garrison posts for each |
| `ONE_PIN_PER_SITE.md` | The board draws one marker per MISSION; it should draw one per PLACE |
| `SIM_ARENA_MODE.md` | The sim as a mode: training, the Lab front end, and where the tutorial sits |

## 15. What I would still want decided

- **Whether the player can lose.** Act 3 as described can take sites faster
  than you can retake them. If there is no losing state, Argus needs a
  ceiling; if there is one, it has to be visible several moves out.

**Stage 0's three are worked in §16 and need one yes each:**

- **§16.1 — ANSWERED 2026-10-12: wipe and restart.** No migration, and
  `SAVE_VERSION` stays at 1. Only available while one person is playing.

- **§16.2 — is price a function of supply, with unlock at 2× buy?** The rule
  is the question; the three integers are a balance pass behind one table.
  Separately: **Diver's supply is a slip and should be 1.**
- **§16.3 — a connection is an authored edge marker naming its neighbour.**
  Nothing to build for six of nine maps. Polaris, the Causeway and Georgetown
  carry no anchor tags at all and need a tagging pass before they can be on a
  board.

Settled since the first draft: a turn is a mission (§5), the enemy moves every
2–3 turns (§5), garrisons are free with the ground and only the frontier can
be attacked (§6), and the Sim Arenas are a practice track rather than
territory — they are not on the adjacency graph.

---

## 16. STAGE 0 — THE THREE DECISIONS, WORKED

Written 2026-10-12. Each one needs a yes, and the yes is the only thing
missing. Where a number is a balance call it is marked as one and put somewhere
a single edit changes it.

### 16.1 SAVE FORMAT — ANSWERED: wipe and restart. No migration.

**Decided 2026-10-12** — *"i can wipe and restart saves it's no problem."*

So there is nothing to write. `SAVE_VERSION` **stays at 1**, `migrate()` stays
the passthrough it is, and the backfill below is not needed.

That is the cheapest possible answer and it is only available while one person
is playing. **It stops being available the moment anybody else is**, so if this
build ever goes further than this machine, the next schema change pays the
migration this one skipped.

**What still has to be true**, wipe or no wipe: `from_dict` reads every field
through `data.get(key, default)` and `migrate()` only warns about a save from a
future build —

```gdscript
# Every field read above already has a default, so a save written before a field
# existed loads cleanly. This is here for the changes defaults can't cover.
static func migrate(data: Dictionary) -> Dictionary:
```

— which is why new fields need no version bump to LOAD. §8 was asking about a
problem the serialiser had already solved; the only live question was what an
old save's ownership should be, and wiping removes the question.

**The two new fields, which are still the design:**

```gdscript
"turn": turn,
"sites": sites,   # site id -> { "owner": int, "since_turn": int }
```

**A dictionary keyed by site, not a set of held ids.** A set answers "mine or
not"; §3 needs four answers — yours, Home Command's, the Swarm's, nobody's.
And `since_turn` is what §5's farming hole needs in order to close, so it costs
nothing to put it in now and a migration to add it later.

### 16.2 TIER PRICES — the rule is the decision; the numbers are a dial

§3a asked for the supply table to be checked before it was applied. It has
been, against all 27 chassis on disk:

| Supply | Count | Purchasable | Matches §3a |
| --- | --- | --- | --- |
| 0 | 3 | 0 | Nest · Watcher · **Diver** |
| 1 | 10 | 6 | yes |
| 2 | 9 | 6 | yes |
| 3 | 5 | 4 | yes |

**The Diver slip is real.** It is the only supply-0 chassis with a cost — 60 —
and the only one of the three that is not a structure. Nest and Watcher are
correctly 0/0 and not purchasable; Diver is `supply = 0, cost = 60,
purchasable = false`. Under a supply-driven rule a supply-0 frame is free,
which is wrong for a thing clearly meant to be a unit. **Diver should be
supply 1.** One edit, and it is not a balance call — it is a typo with a price
attached.

Seventeen of the 27 are not purchasable at all: they are the enemy-only frames,
all at `cost = 0`. **The pricing rule only ever applies to the 16 that are
purchasable**, which is worth knowing before anyone worries about repricing 27
things.

**The rule, which is what needs the yes:**

> **Price is a function of supply. Every chassis of the same supply costs the
> same. Unlocking a line costs twice buying one. Equipment is banded the same
> way.**

**The numbers are placeholders and live in one place.** §3a's 100 / 260 / 520
is super-linear on purpose — supply measures *room* and cost measures
*capability*, so a Bulwark taking three riflemen's space should cost more than
three riflemen, or big frames become strictly efficient and the roster
collapses onto them. That reasoning is the decision. The three integers are a
balance pass, and the human is the only one who can run it, so they belong
behind a table rather than in 16 resource files:

```gdscript
# Campaign/pricing.gd — the whole balance surface, three lines of it.
const CHASSIS_BUY := {1: 100, 2: 260, 3: 520}
const ITEM_BUY    := {1: 40, 2: 110, 3: 240}
const UNLOCK_MULTIPLIER := 2
```

**Equipment banding, proposed.** 36 items currently run 0–260 with no
structure. §3a describes the bands by role, so they are assigned by role and
not by current price — the two disagree substantially, which is the point:

| Band | Buy | Items |
| --- | --- | --- |
| **I** | 40 | frag · smoke · emp · scanner · repair kit · repair tool · cluster mine · heavy mine · pistol |
| **II** | 110 | carbine · shotgun · ancient rifle · marksman rifle · light cannon · armour plating · utility harness · overclock servos · hardened uplink · nanite reboot · repair lance · cyclic feed · sensor relay · drone pack · hatchling charge · shield projector |
| **III** | 240 | autocannon · cluster launcher · heavy MG · ancient MG · squad automatic · mortar · rocket pods · grenade launcher · recoilless · Mark One · hatchling launcher |

Worth seeing before agreeing: the Ancient Pistol goes 10 → 40 and the Mark One
goes 130 → 240. The pistol becoming four times its price is the rule working —
a tier has a floor — but if a 10-resource throwaway is load-bearing somewhere,
that is a reason to keep a fourth band, not a reason to abandon the rule.

**Where this gets implemented is Stage 3, not now.** The rule is what Stage 0
owes; `pricing.gd` and the ~10 call sites that read `ChassisDefinition.cost`
belong with the catalogue and the fab car.

### 16.3 WHAT A CONNECTION IS — the maps already answered it

This was the expensive one to sit on, because §12.6 made it the starting gun
for ten new maps. With map production descoped, the question changes shape
entirely: **a connection has to be something the nine existing maps can carry
without being redrawn.** They can. They already do.

> **A CONNECTION IS AN AUTHORED EDGE MARKER, PROMOTED TO A BOARD EDGE BY
> NAMING THE NEIGHBOUR IT LEADS TO.**

Three parts, and only the middle one is new:

1. **On the map: a named marker that already exists.** Every shipped map
   anchors its enemy force on tagged points, and the convention for an
   approach is already in the tags — `_in`, `_in_*`, `exit`, `jumpoff`,
   `trailhead`. These are the passes the briefings describe.
2. **On the board: a declared edge.** One field naming the neighbour a marker
   leads to. **Declared, not derived from `map_position` distance** —
   adjacency is a design statement about the rail network, and a proximity
   rule would silently rewire the board every time a pin moved.
3. **A state, and one thing you do at it.** Yours or theirs; open or shut. You
   enter through one you hold, and you take the site by holding its
   connections.

**Degree is counted, not assigned** — which means the board's shape is already
sitting in the map files:

| Map file | Operation | Edge markers already authored | Degree |
| --- | --- | --- | --- |
| **pittsburgh** | Three Rivers | `in_east` `in_mon` `in_ne` `in_nw` `in_shore` `in_south` `exit` | **6** |
| **valley_basin** | Valley Basin | `exit_pass` `exit_n` `exit_s` `north` `south` | **5** |
| **coastal-road** | Coast Road | `east_in` `north_in` | **2** |
| **salient** | Over The Top | `jumpoff` `railhead` | **2** |
| **hillfort** | Hillfort | `trailhead` | **1** — its briefing says *"One way on"* |
| **heliostat** | Qamareen | `plant` `tower` | 2, neither of them an edge |
| **polaris** | Polaris | **no anchor tags at all** | **0** |
| **causeway** | The Causeway | **no anchor tags at all** | **0** |
| **georgetown** | Lockside | **no anchor tags at all** | **0** |

**The map file and the operation are not called the same thing**, which is
worth stating once because it is a trap: Three Rivers is `pittsburgh`, Lockside
is `georgetown`, Qamareen is `heliostat`. Nothing goes looking for
`three_rivers_level.tscn` and finds it.

Two things fall out of that table, and both matter more than the definition
did.

**§12.6 UNDERSTATED its own example.** It says *"Three Rivers has four"*
entrances and that this is why the graph makes it the hardest thing on the
board to hold. It has **six**, and it is the highest-degree map in the game —
so the claim holds and the number should be corrected rather than the example
replaced.

**CORRECTED 2026-10-13 — this was wrong.** Polaris, the Causeway and
Georgetown carry **46, 81 and 61 anchor tags** respectively: they are among the
most heavily tagged maps in the project. The claim came from grepping
`tag = &"..."` in the level file, and tags on PREFAB INSTANCES live in the
prefab, not the level — so the grep could not see them.
`tools/probe_map_geography.gd` instantiates each map and walks the live tree,
which is the only way to ask this question. What those three actually lack is
ENTRY-NAMED tags; the ground is fully marked up. See
`docs/briefs/SITE_CONVERSION.md`.


**What this leaves TERRAIN.** Not authoring connections: *dressing* ones that
exist. A tunnel mouth or a rail cut built where `obj_pitt_in_nw` already
stands, whenever there is time for it. The gameplay lane is no longer blocked
on art, which is the entire reason this decision was worth making cheaply.

# APPENDICES

The briefs this plan needs, kept here rather than scattered.

---

## APPENDIX A — PAID UNLOCKS — pay to open the catalogue, then pay to buy

Spend resources once to make a frame or a weapon *available*, then buy copies
of it at its normal price. Instead of an operation handing you kit for
finishing it.

Detail for Phase 3.

---

### A.1. The ledger already does this, and it needs no new save field

`Campaign/campaign_state.gd` opens with the contract:

> `earned` only ever goes up. Spending is NOT subtracted from it — allocations
> are stored separately and `available()` is derived:
> `available = earned - sum(allocations)`
> Allocations are keyed by an **arbitrary string** so the same ledger serves
> squad kit, player upgrades and unit purchases without three parallel
> systems.

So an unlock is one line:

```gdscript
state.allocate("unlock:cluster_launcher", 500)
```

and "is it unlocked?" is `allocations.has("unlock:cluster_launcher")`.

That is the whole mechanism. No new persisted field, no second balance to
drift, no migration for the *cost* side, and changing a price in a patch
recomputes correctly on every existing save — which is exactly the property
the ledger was built for.

**It also deletes `state.unlocked`.** The flat array of granted ids becomes
redundant: the allocation key set IS the unlock set.

### A.2. THE INTERESTING CONSEQUENCE: an unlock is capital, not spending

Allocations are money **tied up**, not money gone. Buy a rifle and its cost
sits in the ledger; sell the rifle and the entry is deleted and you have the
money back. That is why refunds are trivially correct here.

An unlock has nothing to sell. So its allocation never comes back, and
`available()` is permanently lower by that amount.

That is not a side effect to engineer around. It is the best thing about this
design:

**Every blueprint you own is a robot you cannot field.**

The game already teaches this shape. Compute is `earned - held`, and squad
slots and software **hold** compute rather than spending it, so your standing
force is capped by what you have tied up. Unlocks behaving the same way with
resources is consistent, not novel.

If it turns out too harsh, the alternative is a true burn — reduce `earned`,
the way `requisition_compute()` already does for compute. The cost of that is
breaking "earned only ever goes up", and that invariant is the reason the
ledger cannot desync. **Start with the allocation.**

### A.3. What it looks like in play

**In the fabrication car, not in a menu.** `railhead_car_fab` already exists
and currently only parks big frames on its mounts. The fiction does the rest:
nothing is sold to the player, because nobody knows the player exists. What
you are buying is not a weapon, it is **a production line** — you are diverting
Home Command's materiel to stand up a line for something nobody ordered.

So "unlock" means *the fab car can make this now*, which is a thing a car full
of machine tools can plausibly say, and "buy" stays what it already is.

A line in the catalogue reads one of four ways:

| State | What it says |
| --- | --- |
| Locked, affordable | `CLUSTER LAUNCHER — OPEN LINE: 500` |
| Locked, cannot afford | `CLUSTER LAUNCHER — OPEN LINE: 500 (short 180)` |
| Locked, prerequisite missing | `MARK TWO — NEEDS MARK ONE` |
| Open | `CLUSTER LAUNCHER — 240` |

### A.4. Pricing: derive it, do not author sixty-three numbers

There are 36 items and 27 chassis. Authoring an unlock price for each is
sixty-three balance decisions and sixty-three chances to forget one.

**Unlock = 2× the unit price, rounded to 25, overridable per entry.** One
exported `unlock_cost: int = -1` meaning "derive". Real numbers from the
catalogue as it stands:

| Entry | Buy | Opens the line for |
| --- | --- | --- |
| Ancient Pistol | 10 | 25 |
| Mark One | 130 | 275 |
| Cluster Launcher | 240 | 500 |
| Walker | 320 | 650 |
| Bulwark | 380 | 775 |

The ratio is doing real work. At 2× you commit about two copies' worth before
you own one, so an unlock pays for itself across a squad and never for a
one-off — which is the correct incentive, because this is a *standing army*
game. And it self-scales: a pistol costs 25 to open, which is to say a pistol
is not gated, which is right. You do not research a pistol.

### A.5. Marks and chains

"Mark One" is already a real item at 130, so the tiering the name implies is
where the pacing should live: `unlock_requires: Array[StringName]` on the
entry, naming other unlocks.

**The tree is the pacing, not the missions.** That is the actual change of
model here — progress is gated by what you have built toward rather than
where you have been. It also means the catalogue does not open as a wall of
sixty-three entries: you see the frontier, not the whole thing.

### A.6. What this replaces, and what it must not touch

**Replaces:** `mission.unlocks` and `state.unlocked`. Operations stop handing
out kit.

**`required_rank` is deleted** — see Phase 3, task 7. **Leave alone:**

- **`in_shop = false`** means cut from the game — the shotgun, the pistol. The
  code already warns this must not be folded into the unlock path, and it is
  right.
- **`debug.unlock_all_gear`** keeps working; it short-circuits the gate.

### A.7. The save change, which needs signing off

`state.unlocked` goes away and the allocation keys take over. Existing saves
have ids in that array which players have already earned, and they must not be
charged for them retroactively.

**Migration: on load, convert each `unlocked` id into a ZERO-COST allocation**
(`unlock:<id>` → 0). They keep everything, `available()` is unchanged, and the
"is it open" check has one code path rather than two forever.
`SAVE_VERSION` exists to switch on, and `_grant_owed_unlocks()` is already the
place that reconciles this on load.

This is the one part of the proposal that touches save shape, so it is the one
part that needs a yes before anything is written.

### A.8. Blocked on a balance call

**Eleven of the twenty-seven chassis are priced at 0** — Bastion,
Broodcarrier, Heavy Rifleman, Lobber Rover, Marksman, Mortar Track, Nest,
Rifle Trooper, See-Engine, Shotgun Trooper, Watcher.

A system that derives the unlock price from the unit price gives all eleven a
free line. They need real numbers first, and that is a feel judgement, not
something to infer from their stats.

### A.9. The honest risk

A pure price gate has **no discovery**. Mission unlocks are a bad reward but a
good surprise — something you did not know existed turns up. Paying for a
thing you were already looking at in a list never surprises anyone.

The prerequisite tree recovers some of that, because what is two tiers down is
not visible yet. It does not recover all of it. If the game wants the moment
where something unexpected appears, that has to come from somewhere else —
the likeliest candidate being the operations board, where taking a site could
reveal entries rather than grant them.

Which is also how this coexists with territory rather than competing with it:
**ground produces the income, and the income opens the lines.** The two
systems are not alternatives; one is the tap and the other is what you do with
the water.

---

## APPENDIX B — CAPTURE AND TAPS — making the core loop feel like an order

How a compute core changes hands, and how to stop it feeling like holding a
key down. Detail for §12.2–12.3.

---

### B.1. The problem, stated honestly

**Capture does not feel as good as giving an order, and it should feel
better** — it is the thing the whole campaign is about.

Compare what happens when you order a team to advance: you aim, you press,
a toast says `ARMOR : ADVANCE`, a marker lands in the world, four robots turn
and move, and somebody says something. It is instant, legible, audible, and
you watch the consequence happen.

Now compare capture: a bar fills.

The input is not the problem. **The absence of consequence is.**

### B.2. What already exists

`Env/world_objects/compute_core_point.tscn` — a `CapturePoint` node made of a
`Core`, a `Terminal` and a `Motes` particle system, scripted
`interact_objective.gd` with `channel_duration 3.0`, `channel_range 4.5`,
`channel_resume_grace`, and signals for `channel_started`, `channel_progress`
and `channel_interrupted`.

Three sizes: **1.88 m / 3.38 m / 5.19 m** footprint, **4.19 m / 6.97 m /
12.38 m** tall.

That last figure is the one being wasted. **A large core is a twelve-metre
structure** and it currently reacts to being taken by filling a bar on the
HUD.

### B.3. The sequence, with beats

A uniform progress bar has no beats, so nothing can land. Break the channel
into three, each with its own sound and its own thing happening on the core:

| Beat | ~ | The core does | You hear |
| --- | --- | --- | --- |
| **1 · CONTACT** | 0–1.5 s | Motes stall and hang. Panels along the shaft rotate to face you | A handshake tone, two notes |
| **2 · OVERRIDE** | 1.5–4 s | Light climbs the shaft from the base, amber bleeding to neutral white | A rising third, stepping as it climbs |
| **3 · COMMIT** | 4–5 s | Light reaches the head. Motes reverse and fall *inward* | A thunk. Mechanical, final |

Then the payoff, which is not part of the channel at all:

| **TAP INBOUND** | after | The core fires a beacon — a vertical line visible across the map | A flare, then approach audio growing |
| --- | --- | --- | --- |
| **DOCK** | +10–15 s | The tap drone settles onto the head. Motes turn Home green and flow | A latch, and the core starts humming |

**The core is yours at DOCK, not at COMMIT.** The gap is where the mission
lives.

### B.4. The rules that make it work

- **You run the channel.** Not a squadmate. The core loop cannot depend on AI
  pathing to a terminal, and a capture that fails because a robot caught a
  doorway is a failure the player can neither see nor fix.
- **They do not channel. They shoot the anchor off.** No AI capture behaviour
  is needed anywhere, which is the single biggest reason this design is
  buildable — but the anchor must be an `AI`-derived body, not a StaticBody3D,
  or nothing will ever target it. See §12.3.
- **The flight is never contestable.** A tap shot down 500 m away, by
  something you cannot see and could not reach, is a loss you had no play
  against. The drone arrives. What you defend is what lands.
- **One tap per core, unlimited overall.** You cannot stack them. A dead tap
  is replaced by walking back and working the terminal again — paid in
  exposure and time, not in an inventory count.
- **A destroyed tap hands the core BACK TO ITS OWNER.** Decided 2026-10-12,
  overruling an earlier NEUTRAL rule: a site you have not taken is theirs, and
  a third state that appears for a few seconds after one specific failure is a
  rule to teach the player for no gain. Shooting the anchor off undoes the
  capture — that is the whole sentence.

### B.5. Contest, and reading it at a glance

A hostile inside `channel_range` contests: progress stalls, then bleeds.
`channel_resume_grace` already covers stepping out and back.

**The feedback has to be on the core, not the HUD**, because the whole mission
is a question of which cores you still hold and that has to be answerable by
looking across a map:

| State | The core reads |
| --- | --- |
| Theirs | Amber motes drifting outward, slow |
| Being worked | Light climbing the shaft |
| **Contested** | Light stutters and drops back down the shaft. Audible fault |
| Neutral | Dark. No motes. The one state that is *quiet* |
| Yours | Green, falling inward, with a tap on the head |

A tap under fire should be obvious from distance too — sparks, a canted
attitude, the hum going sour.

### B.6. What a large core should cost

`channel_duration` is 3.0 on all three sizes today. Scale it, so the twelve
metre structure is not taken in the same time as the four metre one:

| | Channel | Why |
| --- | --- | --- |
| Small | 4 s | A thing you can grab in a lull |
| Medium | 6 s | Needs the area held |
| Large | 10 s | Needs the area held and somebody watching the approach |

### B.7. What does not exist

- Capture as reversible **state** rather than completion.
- The tap: object, dock, hit points, death reverting the core.
- The one-per-core rule.
- Beats inside the channel, and anything at all happening on the core mesh.
- The beacon, and a tap visible inbound across a map.
- Any capture audio.
- Per-size `channel_duration`.

### B.8. Open

- **Does the player's own death drop the channel or the core?** Dropping the
  channel is obvious. Whether a landed tap survives you being destroyed is a
  feel call.
- **Can a tap be repaired?** The repair tool exists and is built into the
  frame. Letting it mend a damaged tap would give the tool a second job and
  make holding a core an active thing rather than a waiting one.
- **Is there a limit per map rather than per core?** Unlimited is the ruling.
  Worth revisiting only if captures start feeling disposable.

---

## APPENDIX C — HEAT — the in-mission commander

What decides that more enemies arrive, where they go, and when it stops.
Detail for §12.4.

---

### C.1. Two problems, one system

**The enemy cannot react.** Reinforcements today are authored triggers —
`wake_after_kills`, `reinforcement_tag`, an objective firing a wave. Good for
set-pieces, blind to everything else. Nothing on the map knows you are winning.

**And range beats everything.** Nothing stops a player standing at 300 m with
mortars, dismantling a site a body at a time, for as long as they like. The
counter cannot be a rule that bans it. It has to be that **staying still gets
you found.**

### C.2. Heat rises from two things

> **heat rate = (enemy-held cores × their size) + incursion**

**Cores.** Every core still theirs emits. A large core emits more than a small
one. This is the main term, and it means the rate is **something the player
controls** — clearing cores is how you turn the pressure down. The win
condition in §12.7 is causal because of this: take the bunker with three cores
still theirs and you hold a doorway against everything three cores can
produce.

**Incursion.** A slower term that rises with time on the map and does not fall.
This is the one that answers the mortar: patience is allowed, but it is not
free, and it cannot be made free by standing far away.

### C.3. Heat buys squads, and the squads come to YOU

Heat accumulates and is spent at thresholds. A cheap threshold buys a pair; an
expensive one buys something with a chassis.

**Spawned reinforcements ADVANCE on the player**, not on a post. That is the
whole anti-cheese and it needs no special case: if you are at 300 m with a
mortar, what heat buys walks to 300 m and finds you. The counter to standing
off is that standing still is where they are going.

Once engaged they behave normally. `EnemySquadSpec.Posture` already has
**ADVANCE** (*"push to post_tag"*) and **GARRISON** (*"dig in at post_tag"*),
so the behaviour exists — what is missing is something choosing the target
instead of an author choosing it.

**Authored waves stay.** Coast Road's bombers for the bridge are good because
somebody wrote them. Heat is the ambient pressure *between* set-pieces, not a
replacement for them.

### C.4. IT SPENDS FROM A FINITE GARRISON

The most important rule here, because without it heat is a timer that
eventually kills everyone.

Each site has a **reinforcement pool** — part of the same budget force
generation already computes from site value, holder economy and act
(`CAMPAIGN_REWORK.md` §10). Heat is the **rate** at which that pool is
committed. It is not a tap that runs forever.

Which produces the right three outcomes without any of them being special
cased:

| Play | What happens |
| --- | --- |
| Fast and aggressive | Cores fall early, the rate stays low, most of the pool is never spent |
| Slow and careful | The rate climbs, you meet more of the pool, but it does empty |
| Standing off at range | The rate climbs *and* what it buys comes to find you |

**A site can be ground down.** That keeps patience viable and stops heat being
a stealth timer, which is the failure mode this would otherwise have.

### C.5. The player has to be able to feel it building

A pressure system the player cannot read is just unfair difficulty.

- **Audio first.** Engines further off than anything you can see. Comms
  chatter picking up. It should be possible to say "something is coming"
  without looking at anything.
- **A HUD read, but a coarse one.** Not a number. Three or four states —
  *quiet · building · committed · spent* — and the last one matters most,
  because knowing their reserve is gone is what tells you the site is yours.
- **Diegetically it is the cores.** They are what is calling. A site with
  every core still amber should look and sound like a place that is calling
  for help.

### C.6. Defence missions invert it

On a defence you hold the cores, so by §2 the rate would be near zero, which is
wrong — they are the ones attacking.

**On a defence, heat is theirs and runs on a schedule**: the attack is already
committed and arrives in waves from the connection they hold. The player's job
is to last, and what rises with time is *their* spend, not yours.

Same system, source swapped. Worth building that way from the start rather
than discovering it later.

### C.7. This is a LATER PHASE

Capture, taps and the bunker come first. Heat without reversible capture has
nothing to push against, and the incursion term is pointless until there is a
reason to linger.

**Phase 5b builds the core-driven term. The incursion term and the finite pool
can follow**, and should, once there is something to tune them against.

### C.8. What does not exist

- Any accumulator at all. Nothing on a map tracks pressure.
- A target chooser. Every ADVANCE today names its post in authored data.
- A reinforcement pool, or any notion of a site's reserve being spent.
- Spawn-at-edge for reinforcements that were not authored into the map.
- The audio and HUD reads above.

### C.9. Open

- **Does heat persist across visits?** Taking three cores, withdrawing — no,
  there is no withdrawal. But a site you lost and are retaking: does its pool
  come back? Probably over several turns, which makes "hit it again now"
  meaningfully different from "come back later".
- **What exactly does incursion measure?** Time on the map is simplest. Kills,
  or distance pushed, or cores taken, are all more interesting and all more
  gameable.
- **Should heat be visible as a number to a player who wants it?** The coarse
  read is right for feel; an exact one may be right for mastery.
