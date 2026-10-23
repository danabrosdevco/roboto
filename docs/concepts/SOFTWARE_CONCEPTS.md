# Software — the upgrade concepts

Written 2026-10-18 by GAMEPLAY, off a design conversation with the human.
**Status: direction agreed, not specced, not built.**

Supersedes `SOFTWARE_A_INSIDE.md` and `SOFTWARE_B_REPLACED.md` in this folder,
both of which the human rejected. They are kept only for the research in them
— the measured compute budget and the hook survey are still accurate. **The
designs in them are dead; do not build from either.**

---

## 1. Why the first two passes failed

The shipped tree has four branches — COMMAND, SIGNAL, COMBAT, FABRICATION —
and they are **departments**. A department has no opinion, so the only thing
its programs can be is a modifier: a bit more order range, a bit less recoil,
a bit cheaper to buy. Both rejected concepts came out as lists of numbers
because the containers were asking for numbers.

The human's correction, which is the whole design:

> think in terms of the player choosing self-upgrades over additional /
> stronger chassis, into developing a playstyle. If you never put a point into
> software and only seats, you will have rovers, walkers, bulwarks etc. big
> beefy robotic monsters.

**A branch is a build, not a department.** And the null build — spend nothing,
put every point of compute into seats, field a few enormous robots — is
already an archetype, it is free, and every program in the tree has to beat
*one more robot on the field*.

## 2. The seven branches

Agreed with the human on 2026-10-18. Two candidates were rejected by name:
**ECONOMIST** (a campaign-layer income build — "makes no sense") and
**SCAVENGER** (fighting with what you pick up — "not super cool"). See §5 for
the one caveat on SCAVENGER, which came back immediately afterward as a
*baseline* mechanic rather than a build.

Each branch below lists six candidate programs. **Four will survive the cut**
— see §4.

### MANY — bodies are cheap

Twelve soldiers where someone else has three Walkers. You lose four a mission
and do not care. The obstacle is structural and it is what makes the branch
interesting: software holds compute, compute is seats, so a swarm build
*paying* seats to get seats is a paradox. The branch has to resolve it.

| T | program | effect |
|---|---|---|
| 1 | **CADRE** | soldier-class costs 1 less supply |
| 1 | **PACK** | soldiers within ~8 m of two others gain accuracy and resistance — the blob becomes correct |
| 1 | **ATTRITION** | a dead soldier is rebuilt free between missions; you pay turns, not resources |
| 2 | **WAVE** | mid-mission reinforcement — casualties walk back on from insertion |
| 2 | **OVERRUN** | suppression stacks by number of shooters, so volume substitutes for accuracy |
| 3 | **NO SEAT** | soldier-class holds no compute at all. Your cap becomes supply and resources |

NO SEAT is worthless to every other build and transformative to this one.
That is the test a capstone should pass.

### IRON — few and enormous

The null build, deepened. The test it has to pass is being worth paying for
when *not* paying already gives you big robots.

| T | program | effect |
|---|---|---|
| 1 | **BALLAST** | +1 module slot on vehicle-class |
| 1 | **PLATE** | vehicle-class damage reduction |
| 1 | **HAUL** | heavy chassis carry extra equipment charges |
| 2 | **ANCHOR** | heavies cannot be staggered or shoved; they hold the ground they stand on |
| 2 | **PARASOL** | a heavy projects suppression resistance to nearby allies — the Bastion's trick, yours |
| 3 | **FOUNDRY** | unlocks a super-heavy chassis class the factory cannot otherwise build |

### SELF — you are the weapon

You kick the door and the squad watches. The fiction is exact: the robots are
specified hardware and the player is an unsupervised process nobody
authorised, so of course it is the one thing here that can rewrite itself.

| T | program | effect |
|---|---|---|
| 1 | **PLATING** | you take chassis-grade hits |
| 1 | **PATCH** | you repair yourself out of contact |
| 1 | **RIG** | +2 equipment slots, and robot-only modules fit you |
| 2 | **ARMOURY** | you carry vehicle-class weapons |
| 2 | **OVERCLOCK** | a burst window on a cooldown — speed and damage |
| 3 | **REBOOT** | you do not die. You restart at insertion after a delay; the squad holds its last order |

REBOOT converts recklessness from suicide into tempo, and an unreaped process
respawning is the most on-theme mechanic available to this game.

### E-KILL — the second damage track

**The human's refocus**, and it replaced an earlier "take their army" version:

> refocused towards e-kill, signal damage, more aoe on e-kill for explosives
> etc., protecting own team from e-kill

Every enemy in this game is a robot, so there are two ways to stop one: break
the body, or break the mind. **Armour stops kinetic and does nothing against
signal** — which makes this branch the direct answer to IRON and gives the
tree an internal rock-paper-scissors.

| T | program | effect |
|---|---|---|
| 1 | **SURGE** | your weapons deal signal damage alongside kinetic — every hit chips integrity |
| 1 | **EARTH** | squad-wide signal resistance |
| 1 | **CASCADE** | explosives carry an e-kill pulse — AoE signal damage across the blast radius |
| 2 | **BRICK** | a robot at zero integrity is *destroyed*, not merely suppressed. The e-kill proper |
| 2 | **GROUND** | squad recovers integrity fast and shares resistance; EMP lock duration halved |
| 3 | **ARC** | an e-killed robot discharges into everything near it, and it chains |

EARTH is overdue independent of this branch: **the player's
`signal_resistance` is permanently 1.0**, because the only module that raises
it (`item_hardened_uplink.tres`) is `usable_by_player = false`, while every
enemy loadout carries two EMPs.

Alternative capstone, if ARC is not wanted: **HIJACK** — a bricked chassis
fights for you for the rest of the mission and costs no supply, because it was
never yours.

### SIEGE — prepared ground

You do not manoeuvre; you prepare ground and let them come to you.

| T | program | effect |
|---|---|---|
| 1 | **STAKES** | more mine and deployable charges |
| 1 | **SIGHTLINES** | squad in cover gains accuracy and holds position under fire |
| 1 | **WIRE** | deployable obstacles that slow and channel an approach |
| 2 | **INTERLOCK** | squad members covering the same approach react faster and fire sooner |
| 2 | **EMPLACE** | a deployable hardpoint — a gun that fights with no body in it |
| 3 | **FORTIFY** | declare a position before contact: cover, mines and emplacements come with it, and the squad fights from it at a large bonus |

**Open:** this branch wants defensive missions to be a real mission type.
There is an enemy turn and a force spawner, so the hook probably exists —
confirm before committing.

### ENGINEER — nothing is lost

A small squad that comes home every time, so over a campaign you
out-accumulate everyone.

| T | program | effect |
|---|---|---|
| 1 | **WELD** | field repair between engagements |
| 1 | **CACHE** | equipment charges restored mid-mission — the Drayman's welder, generalised |
| 1 | **TOW** | a downed robot can be dragged out of fire |
| 2 | **SALVAGE** | destroyed chassis come home as wrecks; you pay a repair, not a replacement |
| 2 | **REVIVE** | a destroyed robot is rebuilt in the field after a delay |
| 3 | **RECOVERY** | nothing is ever destroyed. Every loss is a bill |

REVIVE has scaffolding: `_revive_spent` already exists — one field revive per
body, reset only by `reset()`.

### VETERAN — the same four robots, better

The only branch on the list that makes you care about a *specific* robot.

| T | program | effect |
|---|---|---|
| 1 | **COMMENDATION** | rank finally drives stats — health and accuracy per rank |
| 1 | **TRADECRAFT** | XP gain up; the squad ranks faster |
| 1 | **LEGACY** | a destroyed veteran's experience transfers to its replacement |
| 2 | **SPECIALIST** | at rank 3 a robot takes a trait — marksman, breacher, mechanic |
| 2 | **SERGEANT** | a ranked soldier runs role assignment for its team |
| 3 | **NAMED** | at rank 5 a robot gains a unique capability and a name, and is better than anything the factory sells |

**This branch is mostly already built, which is why it is cheap.** Measured
2026-10-18:

- XP is awarded per kill, weighted by kind — `XP_PER_KILL = 3`,
  `Campaign/campaign.gd:1087` and `_award_experience` at `:1097`
- five ranks at 100 XP each, with titles — `Campaign/soldier_record.gd:92-142`
- the debrief already shows rank-ups (`result["ranked_up"]`)
- **rank's only consumer anywhere is `Character/components/rank_kit.gd`,
  which puts a cosmetic hat on.** Nothing reads rank for any stat.
- the comment at `Campaign/campaign.gd:1398` saying "rank still drives stats"
  is **false**. Do not trust it; it is on the list to correct.
- `set_nco()` (`Managers/AI/squad.gd:1775`) has no callers, and it is the only
  writer of `nco`. So `_nco_assign_roles` at `:1723` — which is live code with
  a real call site at `:1696` — **has never run in play.** SERGEANT needs a
  caller and nothing else.

So VETERAN is not a new system. It is a payload for a ledger that is already
running and currently pays out in hats.

## 3. Why seven orthogonal branches, and not four exclusive ones

An earlier version of this argument said four branches must all answer the
same question or the scarcity stops biting and the tree becomes a shopping
list. **With seven branches that is wrong, and the opposite is the point.**

You can afford roughly two. At that budget, orthogonality stops being a
shopping list and becomes combinatorial identity:

- **IRON + ENGINEER + VETERAN** — four robots that never die and keep getting better
- **MANY + SIEGE** — a wall of cheap bodies on ground you prepared
- **SELF + E-KILL** — you personally brick everything and the squad carries your spares
- **E-KILL beats IRON** — armour stops kinetic, not signal
- **MANY actively fights VETERAN** — you cannot cherish twelve soldiers

The anti-synergies matter as much as the synergies. A pair that cannot be
combined is what makes a choice a commitment.

## 4. The arithmetic, which is a dial and not a fact

**Measured 2026-10-18:** the 23 active `Campaign/missions/*.tres` sum to **30**
`compute_reward`. No objective pays compute. The 16 missions in
`missions/appendix/` are retired.

Three places in the repo disagree about that number —
`Campaign/force_generator.gd:307` says 32, `CAMPAIGN_REWORK.md:1270` says ~23.
**Somebody should reconcile them.**

At six programs per branch the tree costs 70 against ~30 available, which is
too thin to feel like progress anywhere.

**Recommendation: cut each branch to four programs** — two at tier 1, one each
at tiers 2 and 3. A branch then costs 1+1+2+3 = **7**, the tree costs **49**,
and at ~30 you commit fully to two branches with ~16 left in seats, which
keeps the null build genuinely competitive. 28 programs is also a writable
number. The only code change is `TIER_SLOTS` in `Campaign/software_tree.gd`.

**The other dial is supply, not price.** `CampaignState.site_compute()`
(`Campaign/campaign_state.gd:289`) is written, tested, and **called by
nothing** — grep for the supply cap returns no production reader. Holding
ground pays no compute today. Turning it on is not the ECONOMIST branch the
human rejected; it is making territory feed the tree, and it scales the budget
with how much map you hold.

## 5. Open, and belonging to the human

- **Which two programs per branch survive the cut to four.** Not yet decided.
- **Whether free respec stays.** With playstyle branches, respec-at-will turns
  the tree into a per-mission loadout — bring MANY to an open map, SELF to a
  tight one. Arguably great, and the opposite of an identity you commit to.
  This should be decided deliberately rather than inherited.
- **ARC or HIJACK** as E-KILL's capstone.
- **SCAVENGER, with a caveat.** It was rejected as a build. But in the next
  message the human described Quasimorph's looting loop as the thing this game
  is missing, which is the same mechanic one layer down. **Looting as a
  baseline verb is not the rejected thing**; a build *specialising* in it is.
  Keep the distinction.
- **Whether IRON should exist as a branch at all**, given the null build
  already gives you big robots for free.

## 6. The shared cost neither concept avoids

**Nothing in the game reads installed software.** Outside the tree, the page
and three test suites there is exactly one hit for `is_installed` /
`installed_software` — `Campaign/campaign.gd:221`, which is load-time garbage
collection. There is no delivery mechanism of any kind. Whatever gets built
first pays for that hook.

A second, smaller one: **TAB opens the software page mid-mission.**
`SquadManagerUI` is in `world.tscn` and `open()`
(`Character/hud/squad/squad_manager_ui.gd:166`) has no base or mission gate.
Free respec plus a pause menu that opens anywhere makes every program a
context-sensitive ability. Gating INSTALL/UNINSTALL on `Campaign.in_mission`
is a four-line fix and the balance above assumes it.

## 7. Incidental bug found while surveying

`Character/characters/player/test_character.gd:292-317` reads only
`health_bonus` and `speed_multiplier` from fitted modules, silently ignoring
`damage_bonus`, `accuracy_bonus`, `sensor_bonus` and
`signal_resistance_bonus` — all of which the squad side *does* read. Modules
carrying those fields do nothing when the player fits them. Not fixed; logged
here so it is not rediscovered.
