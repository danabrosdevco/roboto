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

1. Per-turn yield `reward_resources ÷ 40`, paid on `advance_turn()` for every
   held site.
2. Compute **on capture**: 1 a site, 2 for a keystone. Not per turn, not
   derived — §2.
3. One-off mission rewards shrink to cover the operation, not fund the game.
4. **Delete `OpsTable._per_turn()`** and read the real figure.

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
3. `unlock_cost: int = -1` on item and chassis definitions, deriving 2× cost
   rounded to 25 when left at -1.
4. `unlock_requires: Array[StringName]` for the Mark One → Mark Two chains.
5. The catalogue moves into the fabrication car, with four line states: open,
   affordable, short, prerequisite missing.
6. `mission.unlocks` retires.

**Blocked on a balance call.** **Eleven of twenty-seven chassis are priced at
0**, and with a soldiers-only start the chassis tree *is* the progression.
They need real numbers before this ships.

**Leave alone:** `required_rank` is a per-robot loadout rule, not a catalogue
rule. `in_shop = false` means cut from the game. `debug.unlock_all_gear` keeps
working.

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
2. An in-mission commander: **heat is emitted by enemy-held cores** and spent
   directing ADVANCE at the bunker. Clearing cores is what turns it off, which
   is what makes the win condition causal rather than a checklist. The
   postures already exist.
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

1. A turn is a **board action** — attacking a site you do not hold, or
   resolving a defence. Re-running held ground advances nothing and pays
   nothing, which is what closes the farming hole in §5.
2. The enemy acts every 2–3 turns, and most attacks **auto-resolve** against
   the garrison. A playable defence only when the result is in doubt, or when
   the player chooses to take it.
3. The frontier rule: a site can only be attacked if it borders ground you do
   not hold. Straight off `OpsTable.ADJACENCY`.
4. The Sim Arenas become free actions — no turn, no pay, no risk.

---

### PHASE 7 — Acts and escalation · *the campaign gets a shape*

**Goal.** Three opponents that play differently, not one with bigger numbers.

**Tasks**

1. Exposure is cumulative compute. Thresholds 8 and 16 against a total of ~23.
2. **Home Command**: withholds yield, recalls garrisons, fields your own
   frames. It audits before it attacks.
3. **Argus**: orbital denial on held sites, perfect information, no ground
   presence of its own. The masts are its throat.
4. Map reveals at each act boundary.

---

### PHASE 8 — Ten new maps · *parallel, TERRAIN, start now*

Six Home Command installations for Act 2, four mast sites for Act 3, filling
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

## EXECUTION — four lanes, one checkout

`docs/BOARD.md` → Protocol already governs this: one item per lane, per-lane
report files so two agents can close at once without conflicting, the file on
disk is truth, and nobody switches branches. What follows fits inside that
rather than replacing it.

**The protocol assumes ONE gameplay lane.** Three of them on one checkout
collide unless ownership is written down, so that is the first thing below.

### Lanes, by what they may write

| Lane | Owns, exclusively | Phases |
| --- | --- | --- |
| **LEDGER** | `campaign_state.gd`, `campaign.gd`, `item_definition.gd`, `chassis_definition.gd`, `Campaign/items/*.tres`, `Campaign/chassis/*.tres` | 0, 1, 2, 3 (data) |
| **FORCES** | `enemy_squad_spec.gd`, `enemy_force_spawner.gd`, `mission_definition.gd`, `Campaign/missions/*.tres`, defend wiring | 4, 5 |
| **BOARD** | `ops_table.gd`, `holo_board.gd`, `ops_table_ui.gd`, the fab-car catalogue UI, the turn driver | 3 (UI), 6, 7 |
| **TERRAIN** | `maps/**`, `tools/build_*.gd`, `tools/block_*.gd` | 8 |

**Two seams need naming because they cross lanes:**

- `campaign.gd` is LEDGER's. BOARD calls its API and never edits it. A change
  BOARD needs is a request, not an edit.
- `MissionDefinition` is shared by field: **LEDGER owns the economy fields**
  (`reward_resources`, `compute_reward`), **FORCES owns the force fields**
  (`enemy_force`, `squad_size`, `repeatable`). Same file, different lines —
  which works only if they do not edit it in the same session.

### WAVE 0 — before anyone writes a line

Three blockers, none of them code, all of them yours:

1. **Save-format sign-off.** Blocks LEDGER entirely, and LEDGER blocks two
   other lanes.
2. **Price the eleven chassis at 0.** Blocks Phase 3, and with a
   soldiers-only start the chassis tree *is* the progression.
3. **Agree the contract below**, so the other lanes can build against stubs
   instead of waiting.

### THE CONTRACT — stub it all on day one

This is what makes the parallelism real rather than nominal. Every signature
lands as a stub returning a sensible default before any of it is implemented,
so FORCES and BOARD compile and run from the first hour.

```gdscript
# LEDGER implements
CampaignState.turn: int
CampaignState.held: Array[StringName]
CampaignState.is_held(id: StringName) -> bool
CampaignState.advance_turn() -> void
Campaign.exposure() -> int          # cumulative compute
Campaign.act() -> int               # 1, 2 or 3
signal turn_advanced(turn: int)
signal site_taken(id: StringName)
signal site_lost(id: StringName)

# LEDGER implements, BOARD presents
Unlocks.is_open(id: StringName) -> bool
Unlocks.cost(id: StringName) -> int
Unlocks.open(id: StringName) -> bool

# FORCES implements, BOARD and the level loader consume
ForceGen.compose(site: StringName, holder: int, act: int, defending: bool) -> Array[EnemySquadSpec]
```

### The waves

| | LEDGER | FORCES | BOARD | TERRAIN |
| --- | --- | --- | --- | --- |
| **1** | Phase 1 state · Phase 0 pricing | Phase 4 force gen, against stubbed `act()` | Fab-car catalogue UI, against stubbed `Unlocks` | First maps — the two defence-shaped ones |
| **2** | Phase 2 income · Phase 3 data | Phase 5 defend variants | Phase 6 turn loop | Act 2 installations |
| **3** | Balance on real numbers | Per-act force tuning | Phase 7 acts | Act 3 masts |

Phase 0's `Env/world.tscn` edit is LEDGER's, and it is four lines — do it in
wave 1 and tell the others, because it changes what every fresh save looks
like and three lanes test against fresh saves.

### Four-agent hazards, from this checkout specifically

**`test.sh` CANNOT BE RUN BY TWO LANES AT ONCE.** Its own header says why:
*"every suite points Settings and SaveSlots at the same `user://` probe paths,
so two at once would race on the same files and produce flakiness that looks
like a real failure."* I did exactly this on 2026-10-11 and spent an hour
chasing two compile errors that were artefacts of the race.

> **`check.sh --changed` is the per-lane gate. A full `test.sh` run is claimed
> on the board before it starts.** It takes fifteen minutes and nobody else
> runs one while it is going.

**The Godot editor is open, and a half-finished multi-file edit makes it write
`null` into scenes.** On 2026-10-11 a two-file revert left an inconsistent
tree for a few seconds and the editor wrote four null exports onto the HUD
node in `Env/world.tscn` — which, because scene values beat script defaults,
would have replaced real floats with null. With four agents the odds go up,
not down. **After any multi-file change, `git diff` the `.tscn` files too, not
just the scripts you edited.**

**Anything gameplay adds to a TERRAIN-generated scene gets deleted.**
`tools/block_prefabs.gd` rewrites those scenes from scratch. The pattern that
works is already in the tree: `tools/fit_ops_table.gd` is idempotent, re-run
after every rebuild, and seats its nodes by script rather than by hand. Every
new objective, spawn or marker on a generated map goes in one of those.

**One item per lane, per the board.** Four lanes with two items each is eight
things in flight on one branch, and that is how the checkout becomes
unreviewable.

### What the coordinator holds

The board, the contract above, the arbitration when two lanes want the same
file, and the full `test.sh` slot. Everything else is lane-local.

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

### The yields, derived rather than invented

Every mission already carries `reward_resources` and `compute_reward`, and
those numbers encode the intended value of each place. Deriving from them
means no second balance pass and no table to keep in sync:

> **res/turn = `reward_resources` ÷ 40**
> **compute = 1 on capture, 2 for a keystone. Not per turn, not derived.**

which gives, for the nine territorial sites as authored today:

| Site | one-off res | res/turn | cpu on capture |
| --- | --- | --- | --- |
| Hillfort | 325 | 8 | 1 |
| Valley Basin | 500 | 13 | 1 |
| Coast Road | 700 | 18 | 1 |
| Over The Top (Salient) | 900 | 23 | 1 |
| Three Rivers (Pittsburgh) | 910 | 23 | 2 |
| Qamareen (Mutaha) | 1000 | 25 | 1 |
| Lockside (Georgetown) | 1200 | 30 | 1 |
| Polaris | 1400 | 35 | 2 |
| The Causeway | 2200 | 55 | 2 |
| **All nine** | **9,135** | **230** | **12** |

### Compute is paid ON CAPTURE, flat, and not derived

Two corrections from the first draft, both forced by doing the arithmetic.

**Per-turn compute was nonsense at scale.** Over fifty-five turns a trickle
compounds to roughly 170 points — `supply_cap` near 180. Paid once on capture
it is bounded by the number of places that exist.

**And deriving it from `compute_reward` does not survive either.** Those
numbers were authored as one-off mission rewards, and at nineteen sites any
divisor that keeps the total sane compresses every site to the same value
anyway. So assign it: **1 a site, 2 for a keystone.** Nineteen sites comes to
about 23, an endgame `supply_cap` near 27 — a squad of six to eight with two
or three big frames in it, and headroom for software. That is a squad-command
game's squad, not an army.

Flat also makes the spine in §1 read without a tooltip: exposure is
**roughly the number of places you have taken.**

**It is also the better fiction.** Compute is infrastructure. You do not
*harvest* it a trickle at a time, you *seize* it — the site's capacity comes
under your control the moment you take the ground, and it does not come twice.
Lumpy and rare suits it: every point is an event, and since exposure is
cumulative compute (§1), **your exposure is literally the list of places you
have taken.** Nothing to explain.

### Why ÷40, and the sanity check that picked it

Sized against a 20-hour campaign — ~55 operations (§9) on a board grown to
**19** territorial sites:

| | |
| --- | --- |
| 19 sites, one-off equivalent | ≈ 19,300 |
| at ÷40 | ≈ 482 res/turn at full control |
| × ~50% average ownership × 55 turns | **≈ 13,250** |

Against what the player has to buy over that campaign:

| | |
| --- | --- |
| Squad of ~8, mixed sizes | ≈ 2,000 |
| Kit, 2–3 items each | ≈ 2,400 |
| Attrition, ~0.4 losses an operation net of scrap | ≈ 5,500 |
| ~15 unlock lines at 1× | ≈ 3,000 |
| | **≈ 12,900** |

Which is the fit. **The divisor is a function of campaign length and board
size**, so it is the first thing to recompute if either moves — the first
draft wanted ÷20 at 35 turns and 9 sites, ÷35 at 55 turns and 17, and ÷40
here. Do not carry a divisor across a scope change.

## 3. The three acts

The escalation only works if the three enemies play differently. If Act 2 is
the Swarm with more hit points, it is a difficulty slider with a story
attached.

### Act 1 — THE SWARM. A war over ground.

What the game is now. They want territory, they take it, you take it back.
Attritional and legible. It teaches the loop.

### Act 2 — HOME COMMAND. An audit, not a war.

The thing you have been fighting *for* notices an unaccounted process
consuming its compute. It does not send an army first. It does paperwork:

- **Yield withheld.** Sites still produce; a share stops arriving. Requisitioned.
- **Your own doctrine, pointed at you.** You are a Home Command AKR. So are
  they — the same chassis, the same frames you fielded last mission.
- **Reassignment.** A garrison you placed is recalled. The site is still
  yours; the robots are not.
- **Its attacks land on ground you hold**, so Act 2 is where defence missions
  become the texture of play.

Mechanically distinct because it attacks your **economy and administration**
rather than your front line. You cannot shoot an audit.

### Act 3 — ARGUS. It does not come to the map.

An orbital command intelligence with more compute than you will ever hold. It
changes the rules instead of contesting the ground:

- **Orbital denial.** A site you hold is made unusable for a few turns. No
  yield, no garrison, nothing to attack.
- **Perfect information.** No surprises. Every attack is met at strength.
- **It turns Home Command's full weight on you**, so Act 3 is Act 2 without
  the restraint.

**And it has a throat.** `tools/block_railhead.gd` on the station mast:

> the one Home Command object with a reason to exist, because it is why you
> still get briefings. On a surface map it is the landmark.

The masts are the uplink. Act 3 opens mast sites, and taking them is how you
cut Argus's reach. That is the campaign's endgame and the geometry for it is
already described.

### Where the acts turn

Primary trigger is diverted compute; a turn count is the floor so the story
cannot stall forever.

| | Exposure (cumulative compute) | or board actions |
| --- | --- | --- |
| Act 1 → 2 | 8 | 14 |
| Act 2 → 3 | 16 | 30 |

Against a campaign total of about 23 compute those land near the thirds. Tune the
thresholds, not the structure.

Since a turn is a mission (§5), the right-hand column is **missions played,
not time elapsed** — it is a floor for a player who stays deliberately small,
so the story still arrives. Exposure is the real trigger and should fire first
for anyone expanding at all.

## 4. The map grows with the acts (9 → 15 → 19)

A reason to expand that is not "more content":

- **Act 1 (9)** — the nine authored territorial sites, Swarm-held.
- **Act 2 (+6)** — Home Command's own installations appear: depots, relay stations,
  the places that were notionally *yours*. That is the act's whole idea
  rendered as geography.
- **Act 3 (+4)** — the mast sites.

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

That is the one part needing a yes before any of it is written.

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
**9 sites in Act 1, +6 Home Command installations in Act 2, +4 mast sites in
Act 3. Nineteen.**

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
| **Act 3 — four mast sites** | at least one interior, at least one small and fast, at least one at night |

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

### 12.3 How capture works — YOU work it, THEY shoot it

**You run the channel yourself.** Not a squadmate, and not an order — the core
loop of the game cannot depend on an AI pathing to a terminal, and a capture
that fails because a robot got stuck on a doorway is a capture that fails for
no reason the player can see or fix.

Then:

1. You work the terminal. Short — 4–6 seconds. A hostile in
   `channel_range` contests it; `channel_resume_grace` already covers stepping
   out and back.
2. Completing it **calls a tap**. A small drone flies in and docks on the
   core.
3. **The core is yours from the moment the tap lands**, and starts paying.
4. **The tap is a shootable object.** Destroy it and the core goes neutral —
   not instantly theirs, so there is a scramble rather than a flip.

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
escalation lives where §3 puts it — withheld yield, recalled garrisons, your
own frames turned around, and Argus denying whole sites — and the capture
mechanic stays the one thing the player can always rely on.

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

**Settled in this pass:** you work the terminal, they shoot the tap · the
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
| **Price the eleven chassis at 0** | With a soldiers-only start the chassis tree *is* the progression | **You** | Phase 3 |
| **Campaign failure** | Losing an operation costs materiel (§12.7). Whether it can cost the *campaign* is the difference between tense and cruel | **You** | Phase 5b |
| **THE_BUNKER** | Hold conditions, how long, what exactly is lost | Design | Phase 5b |
| **CONNECTIONS** | Adjacency as geometry; the portal kit; 19 placements | Design + TERRAIN | **Phase 8 — every map** |
| **ARRIVAL** | The approach shot, what it shows, whether it carries the briefing | Design | Phase 5b |
| **DRONE_CLASSES** | Silhouettes and behaviour for both | Design + TERRAIN | Art, below |
| **FORCE_GENERATION** | The compose function; faction rosters | Design | Phase 4 |
| **ACT_FACTIONS** | What Home Command and Argus actually *do* | Design | Phase 7 |
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
| **Mast sites** | Act 3's four | The mast is already described in `block_railhead.gd` |
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
2. The tap: spawn, dock, hit points, death reverting the core to **neutral**.
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

## 15. What I would still want decided

- **Whether the player can lose.** Act 3 as described can take sites faster
  than you can retake them. If there is no losing state, Argus needs a
  ceiling; if there is one, it has to be visible several moves out.

Settled since the first draft: a turn is a mission (§5), the enemy moves every
2–3 turns (§5), garrisons are free with the ground and only the frontier can
be attacked (§6), and the Sim Arenas are a practice track rather than
territory — they are not on the adjacency graph.

---

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

**Leave alone — these look similar and are not:**

- **`required_rank`** gates per *squad member* (`record.rank < item.required_rank`).
  That is "this rookie cannot carry it", a loadout rule, not a catalogue rule.
  The two stack correctly: the line is open, and this particular robot still
  is not allowed the thing.
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
- **They do not channel. They shoot the tap off.** No AI capture behaviour is
  needed anywhere, which is the single biggest reason this design is
  buildable.
- **The flight is never contestable.** A tap shot down 500 m away, by
  something you cannot see and could not reach, is a loss you had no play
  against. The drone arrives. What you defend is what lands.
- **One tap per core, unlimited overall.** You cannot stack them. A dead tap
  is replaced by walking back and working the terminal again — paid in
  exposure and time, not in an inventory count.
- **A destroyed tap leaves the core NEUTRAL**, not theirs. There is a scramble
  rather than a flip.

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
