# Roboto — gameplan to shipping demo

Written 2026-09-17, rewritten the same night. Everything below is grounded in
the repo as it stands — where I say something is missing or inert, I checked.

---

## 0. The thesis

**Roboto does not need new systems. It needs the systems it already has to be
switched on.**

Five substantial mechanics are built — some completely, some nearly — and are
invisible in the running game. Not half-designed, not stubbed: written,
integrated, and then never turned on. The demo's entire dramatic arc already
exists in this repo as dormant parts.

| System | Built | Why it's invisible |
|---|---|---|
| **Veterancy** | ~95% | `add_xp()` exists and **nothing ever calls it**. Rank is permanently 0, so every `required_rank` gate on every item and chassis is permanently shut. |
| **Item unlocks** | ~90% | `unlocks` is authored on two missions and written to `state.unlocked` on completion. `unlocked` is **never read** — only saved. The shop shows everything from minute one. |
| **Enemy variety** | 100% built, 0% used | Five working enemy scenes. **All six campaign missions use only `soldier_shotgun`.** |
| **Reinforcement director** | ~80% | `Posture.RESERVE` is implemented in `enemy_force_spawner.gd:127`. **Every mission leaves `reinforcement_tag` empty**, and nothing triggers a wake. |
| **Possession** | ~70% | `possession.gd` is a complete, carefully-written controller. It is **not instantiated in any scene**, and `Soldier.drive()` — the one method it calls — doesn't exist. |

And one thing that is genuinely absent rather than dormant:

| **Recruitment** | 0% | `add_soldier()` is called from exactly one place: `_seed_new_campaign()`. The squad can only shrink. But `ChassisDefinition` already carries every field recruitment needs. |

My first pass at this document treated the project as "working game with gaps"
and produced a triage list: fix the lies, add the missing button, teach the
controls. That plan gets you to *not broken*. It does not advance anything,
because it ignores that **the interesting half of this game is already written
and switched off.**

---

## 1. What this costs you right now

The deepest experiential problem with the current build is not any single
missing feature. It's that **nothing changes across six missions.**

Same map. Same single enemy type. Same shop inventory. Same four soldiers at
rank 0 forever. Same three garrisons. No escalation, no growth, no unlock, no
loss you can recover from.

A new player's mission 5 is indistinguishable from their mission 1. That is the
ceiling on the demo, and every one of the five dormant systems above exists
specifically to break it.

---

## 2. Two deadlines

**Friday with your brothers is not the shipping demo.** It's the best
instrument you have: four people touching this cold, once, before expectations
set. Ship what exists, watch silently, explain nothing. Every explanation you
give in the room is a feature the demo needs and doesn't have.

**Shipping demo** is the real target: a 25–35 minute slice a stranger can finish
alone, that shows the pillar, and that *ends on purpose*.

Five questions to answer while watching on Friday:

1. How long before they open the squad manager unprompted? (Never → tutorial
   priority confirmed.)
2. Do they ever issue a squad order?
3. What do they do when the terminal cycles the mission name?
4. Do they notice a squadmate taking damage?
5. Where do they look when they don't know what to do?

---

## 3. The demo as a dramatic arc

This is the part my first pass didn't do. A demo needs shape, not just working
systems. Here is a five-mission arc built **almost entirely from parts that
already exist**, with what each mission teaches and what switches on.

### M1 — Valley Recon *(exists)*
3 shotgun soldiers, one garrison, extract.
**Teaches:** move, shoot, command, extract.
**New:** XP is awarded on return. At least one soldier reaches Regular and the
payout card says so. *The squad is now a thing that grows.*
**Shop:** small — 4 items. Legible because it's small.

### M2 — Valley Probe *(exists, re-forced)*
Adds a second garrison and **chasers** (`enemy_chaser.tscn` — melee rush).
**Teaches:** you cannot solo a rush. Use the squad or lose someone.
**New:** completing it unlocks the **DMR**. The shop visibly grows. *Progression
becomes legible.*

### M3 — Valley Push *(exists, re-forced)*
**Reinforcement director on.** Taking the first garrison wakes a RESERVE squad
that moves on your position.
**Teaches:** escalation responds to *what you do*, not a timer. This is the
first mission where you can realistically lose a soldier —
**so recruitment has to exist by here.**

### M4 — Valley Assault *(exists, re-forced)*
Mixed force: shotgun soldiers, chasers, **nest-chasers**.
**New:** unlocks **optics**, which is `required_rank = 1` — so it is only fittable
on a soldier who has *survived and ranked up*. Veterancy, unlocks and gear
converge in one moment.

### M5 — Valley Siege *(exists, re-forced)*
All three garrisons, **boss_guardian**, reinforcements armed.
**Teaches:** everything at once. This is the ending beat.
**Possession** is the signature move that makes it winnable in style.

**Every mission in that arc already exists.** M2–M5 need their `enemy_force`
arrays re-authored with different chassis and a `reinforcement_tag` — data, not
code. The arc is made of `.tres` edits plus five switch-ons.

---

## 4. Possession is the demo's signature moment

I under-weighted this badly the first time.

Your premise is: *you are a rogue agentic drone commanding robots.* Possession —
leaving your own chassis parked and vulnerable, taking direct control of a
squadmate, being ejected when that body dies — is the mechanical expression of
that premise. It is the one thing a player will describe to someone else
afterwards.

And it is written. `possession.gd` documents four edge cases it solves:
AI culling against the player's position, the squad fighting you for control of
the body you're driving, dying while possessing, and your own body dying while
you're away. That is not a sketch. That is someone who thought it through.

More telling: **the seams were deliberately carved into the other systems.**
`Player.get_focus_position()` exists with the comment *"Kept as a seam even
though it now just returns the body position."* `Squad.get_orderable_members()`
exists as an indirection over `get_living_members()` for no current reason.
Both are exactly the hooks possession needs.

What's missing is `Soldier.drive()` and the wiring. Honestly: a solid day, not
an afternoon — the controller is written but untested against a Soldier that
can't yet be driven. **It is still the highest experience-per-hour item in this
document**, and it should be in the demo.

---

## 5. What a first-time player needs, in order

From §3 of the audit: the combat loop and campaign loop both work. Every failure
is **discovery**, not capability. Four places where a working system goes
unfound:

1. **Base has no orientation.** They spawn, four robots stand around, nothing
   says what this place is.
2. **The terminal cycles.** Pressing it changes the mission name, which reads as
   a bug. Fix: make the prompt say `CYCLE OPERATION`.
3. **The squad manager is invisible.** Your best screen, behind an untaught key.
4. **Squad command is untaught.** Most first-timers will play a solo FPS with
   friendly bots and never see the game.

**#4 is fatal and has a cheap fix that isn't a tutorial:** wire `ORDER_ACK`
barks. A squad that *audibly answers* when commanded teaches that commanding
works, without a line of UI text. You have 105 robot voice clips and they are
currently bound to a single trigger — `apply_damage`. Your robots only speak
when shot.

That is the best value-per-hour in the project and it doubles as onboarding.

---

## 6. Asset reality

**Audio — 166 files, unevenly spent.** 105 droid voices (one trigger), 9 AR15,
9 ricochet, 8 squad-manager UI, 6 pistol, 3 melee, 3 scanner, **2 shotgun**,
**0 music**. No music directory exists anywhere.

**Art.** Weapons have real models. Environment has five Kenney kits plus
TrenchBroom brushwork. The CRT filter is genuinely distinctive and *done*.
**Characters are two CSG capsules.** No model for friend or foe — which is why
you can't tell Bravo-1 from Bravo-4, or a squadmate from a hostile, except by
HUD colour.

The capsules cut both ways: **new chassis are nearly free.** A frame is a
capsule at a different scale and tint plus a stats `.tres`. Three visually
distinct chassis this week, no commissioned art, and it solves squad legibility
at the same time.

---

## 7. The plan

### Phase 0 — Friday (hours)
Ship as-is. Verify the crash fix with one full mission to extraction. Watch,
don't explain, answer the five questions. **Start nothing.**

### Phase 1 — switch on what's built (the big win)
In dependency order. Each is small; together they are the entire arc in §3.

1. **Kill credit + XP award** → veterancy comes alive → rank gates open.
2. **Enforce unlocks** → shop grows across the campaign.
3. **Re-author M2–M5 enemy forces** → escalation, variety. Pure `.tres` work.
4. **Reinforcement trigger** → escalation responds to the player.
5. **Barks** → the squad becomes alive and teaches itself.

### Phase 2 — the one genuinely missing system
6. **Recruitment + 3 chassis tiers.** Must land before M3 is winnable-with-loss.
   Solves squad legibility as a side effect.
7. **Fail state.** Small, and a correctness fix — death currently never calls
   `Campaign.extract()`, so squad losses may not persist at all.

### Phase 3 — the signature
8. **Possession.** Finish `Soldier.drive()`, instantiate, teach it in M3.

### Phase 4 — product polish
9. Music (2 tracks). 10. Consolidate the two catalogues. 11. DMR/carbine made
real. 12. Scanner viewmodel. 13. Second map — the most expensive item here and
the one that raises the ceiling most, if there's time.

---

## 8. Implementation, first pass

### 8.1 Kill credit and XP *(switch-on)*

`apply_damage(damage, source)` already carries attribution; `die()` discards it.

```gdscript
# enemy.gd
var _last_attacker: Node = null          # set in apply_damage
```

In `destroy()`, credit the killer. Then `SquadSpawner.write_back()` at
extraction is the natural place to move XP from the live node onto the record —
it already walks every body to read survivors back.

Award shape: XP per kill, plus a survival bonus for finishing a mission alive.
Surviving should matter more than killing, or you teach the wrong behaviour for
a game about keeping soldiers.

`SoldierRecord.add_xp()` already handles rank-up. Surface it: the payout card
built this week takes extra lines, so `BRAVO-2 → REGULAR` goes straight on it.

### 8.2 Enforce unlocks *(switch-on)*

`state.unlocked` is written and never read. One filter in the armoury rebuild:

```gdscript
if item.required_unlock != &"" and not state.unlocked.has(item.required_unlock):
    continue
```

`ItemDefinition` needs one new field (`required_unlock`), or reuse `id` and gate
anything named in a mission's `unlocks` that hasn't been earned. The second is
zero new fields and works with the two missions already authored.

Then show it: `NEW IN STORES: MARKSMAN RIFLE` on the payout card.

### 8.3 Re-author enemy forces *(pure data)*

`EnemySquadSpec` already has `chassis`, `count`, `posture`, `route_tag`,
`post_tag`, `spawn_tag`, `reinforcement_tag`, `always_active`, `faction`.
M2–M5 just need more specs pointing at `enemy_chaser.tscn`,
`enemy_nest-chaser.tscn` and `boss_guardian.tscn`.

Careful: those live in `Character/characters/appx/`, which despite the name is
**not** a scratch folder — four of them have FuncGodot FGD entity definitions.

### 8.4 Reinforcement trigger *(switch-on)*

The spawner handles `Posture.RESERVE`. What's missing is the wake call and a
trigger. `ObjectiveTracker.objective_changed` already fires on completion —
connect it to `EnemyForceSpawner.wake(tag)`. Escalation on player action, not a
clock, exactly as the briefing intends.

### 8.5 Barks *(switch-on)*

Add a category arg and a per-category cooldown:

```gdscript
enum Line { CONTACT, ORDER_ACK, KILL, RELOAD, DOWNED, HURT, SEARCH }
```

| Line | Hook that already exists |
|---|---|
| CONTACT | `trigger_combat()`, first acquisition only |
| ORDER_ACK | `order_move_to()` when `force == true` |
| KILL | `change_combat_target()` when the old target died |
| RELOAD | `_on_reload_started()` |
| DOWNED | `enter_downed()` |
| HURT | `apply_damage()` — where it is today |
| SEARCH | `_enter_search()` |

Sort 105 clips into seven arrays. Global ~1.5s cooldown plus a per-squad one so
a four-robot contact produces one call, not four.

### 8.6 Recruitment *(build)*

Three frames, all capsule variants:

| | `scout` | `soldier` *(exists)* | `heavy` |
|---|---|---|---|
| health | 40 | 60 | 100 |
| speed | 1.25 | 1.0 | 0.8 |
| sensor | 55 | 45 | 40 |
| equip / module slots | 1 / 2 | 2 / 2 | 2 / 1 |
| cost | 60 | 100 | 180 |
| `required_rank` | 0 | 0 | 1 |

Give `soldier` a real cost; at 0 it can't participate in an economy.

```gdscript
@export var max_squad_size: int = 6

func recruit(chassis: ChassisDefinition, display_name: String = "") -> SoldierRecord:
    if not can_recruit(chassis):
        return null
    var key := "unit:%s:%d" % [chassis.id, _next_purchase()]
    if not _allocate_quiet(key, chassis.cost):
        return null
    var record := SoldierRecord.new()
    record.id = mint_id()
    record.display_name = display_name if display_name != "" else _next_callsign()
    record.set_chassis(chassis, catalogue)
    record.recompute_stats(catalogue)
    roster.append(record)
    ledger_changed.emit()
    roster_changed.emit()
    return record
```

`roster.append`, not `add_soldier()` — the latter emits on its own, which is a
rebuild mid-mutation, the bug family that has bitten four times.

No refunds on disband; that's what makes the choice weigh something. Base only —
`if campaign.in_mission: return`. UI is a `RECRUIT` row at the bottom of the
roster column, reusing `_make_shop_button()`.

**Callsigns must not reuse a dead soldier's name.** Continue the series against
the ledger, not the live roster.

### 8.7 Fail state *(build, small)*

Today: `die()` → `_on_player_died` → `reset_level()`. No screen, no consequence,
and **`Campaign.extract()` is never called**, so a mission you die in may not
write squad state back at all.

Call `extract(false)` — the unsuccessful path already works, bonus objectives
still pay — show `MISSION FAILED` on the payout card, return to base rather than
restarting in place. Returning to base keeps the campaign loop turning and puts
repair in front of the player, which is a system you want seen.

### 8.8 Possession *(finish)*

Implement `Soldier.drive(intent)` — accept a movement/look intent and skip the
AI's own movement for that frame. Then make `get_orderable_members()` exclude
the possessed body and `get_focus_position()` return it. Both seams exist.

Teach it in M3, where the reinforcement wave makes a second pair of hands
genuinely useful.

---

## 9. Back pocket — the abstract engagement layer

Not for the demo. Captured now because it should shape decisions before the
maps get big, not after.

### What it is, and what it is not

**It is texture with consequences.** The pitch, in the player's words: the
difference between a corridor of rooms with enemies in them and a place where a
war is happening that you are one part of. You should be able to *hear and see*
that there are other firefights, and the outcome of those fights should change
your mission — do reinforcements arrive from the west, or did that flank
collapse and you are now being encircled instead of pushing?

**It is not an optimisation.** The cheapness is a side effect. If it were a perf
technique you would optimise for cost; because it is texture you optimise for
*legibility and stakes*, and those pull in a different direction — a distant
battle nobody can read the outcome of is wasted no matter how cheap it is.

The governing rule: **the elements of combat must happen — movement, shooting,
dying — but the specifics must not matter.** Nobody needs to know which robot
shot which. Somebody needs to know the west flank is losing.

### The shape

An **Engagement** is two forces contesting a place, with no bodies:

- a position and a sector tag
- participants as *strength numbers* per faction, not nodes
- a coarse resolution tick — seconds, not frames — that trades attrition
- an outcome that changes world state when one side breaks

Resolution should be deliberately crude. Strength, a posture modifier, a die
roll, drift. Anything more detailed is invisible by definition and only buys
simulation nobody can perceive.

### Making it legible — and the piece that already exists

This is the part that decides whether it works, and **the channel is already
built**. The comms log takes friendly radio traffic and prints it. A distant
engagement reporting into it costs nothing new:

```
DELTA-2  ›  CONTACT WEST, HEAVY
DELTA-2  ›  FALLING BACK
WEST FLANK LOST
```

That, plus distant gunfire through `StimulusManager` (which already models
sound events and which real AI already react to) and occasional tracer lines
drawn between two points with no raycast behind them, is most of the
presentation. The CRT filter helps — distance is already abstracted by the art.

A player who hears a firefight, reads it going badly, and then meets the
consequences has understood the whole system without a tutorial.

### How it changes the mission

**The reinforcement director built for the gunship waves is the seam.** It
already answers "something happened → wake a reserve". Today the trigger is an
objective id; an engagement outcome is the same shape:

- allies win the west → a friendly reserve deploys, or an enemy garrison thins
- enemies win the west → a reserve wakes *behind* the player — encirclement
  rather than advance

That is the whole point: the same mission plays differently depending on a
fight the player did not take part in. And it should be *possible to take part*
— being able to break off and go help the west flank is what separates this
from a cutscene playing on the horizon.

### The hard part: materialisation

Turning an abstract engagement into real robots when the player closes is where
this breaks if it is done carelessly.

- **Hysteresis, generously.** Materialise at one range, dematerialise at a
  noticeably longer one, or a player standing on the boundary thrashes the
  whole squad in and out of existence.
- **Carry the attrition across.** An engagement that has been losing for two
  minutes must materialise as a mauled squad in cover, not a fresh one at full
  strength — otherwise approaching a battle *resets* it and the player learns
  to ignore the radio.
- **Dematerialising is the harder direction.** Bodies have position, health,
  ammunition and grudges; a strength number does not. Collapsing them loses
  information, so the rule for what survives the collapse has to be decided
  once and written down.

### Pitfalls worth naming now

- **Wallpaper.** An engagement with no stake is noise. Every one should be able
  to change something the player cares about, or it should not exist.
- **It must not win or lose the mission on its own.** It changes the *shape* of
  the fight, never the result. A player who loses because of a battle they
  could not see or influence has been cheated.
- **Persistence is save state.** The moment outcomes carry between missions,
  engagements are campaign data and the save format grows.

---

## 10. Risks

- **One map is the ceiling.** Six missions on `valley_level` will feel
  repetitive by M3 even with full escalation. The arc in §3 buys you a lot, but
  a second map is what actually raises the ceiling.
- **I cannot playtest.** Feel, balance and pacing are yours. My tools close the
  correctness gap, not the design one.
- **The economy split is a trap right now.** Shards / neural bits / compute is
  the most interesting design work here and the least urgent; it changes the
  save format. Not before the demo ships.
- **Possession could eat a week** if `drive()` fights the movement state
  machine. Timebox it. If it slips, the arc still stands without it.
- **Two catalogues** remains a live footgun until consolidated.
