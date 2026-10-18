# SOFTWARE A — twenty-four programs, inside the framework

Concept, written 2026-10-16 · **status: nothing selected, nothing built**

The companion is `SOFTWARE_B_REPLACED.md`, which throws the framework away. This
one keeps it: four branches, three tiers, twenty-four ids, compute held and
refunded exactly as `Campaign/software_tree.gd` already does it. Every program
below names the system it changes and the file and line it changes it at.

---

## 0. What is actually built today, measured

Worth stating plainly, because it decides how much of this is design and how
much is wiring.

| | |
|---|---|
| the tree | `Campaign/software_tree.gd`, 130 lines. Costs (`:35`), slots (`:37`), tier gating (`:101`), uninstall ordering (`:114`) — all real and all tested |
| the page | `Character/hud/squad/software_page.gd`, 166 lines. Branch rows, tier columns, card grid, detail panel, INSTALL/UNINSTALL |
| the ledger | `CampaignState.install_software` / `uninstall_software` / `release_unknown_software`, `Campaign/campaign_state.gd:1002-1041` |
| the words | `software_tree.gd:41` — `const WRITTEN := {}`. **Empty.** All 24 render as `UNWRITTEN` |
| the effects | **none.** Nothing anywhere reads an installed program |

That last line is the one that matters. I grepped `is_installed`,
`installed_software`, `software:` and `SoftwareTree` across the repo. Outside
the tree, the page and the tests there is exactly one hit:
`Campaign/campaign.gd:221`, `state.release_unknown_software(_SoftwareTree.ids())`
— load-time garbage collection, not a gameplay read.

**So there is no delivery mechanism, and every program below needs one.** That
is a shared cost, not a per-program cost; §6 says what it is.

### The budget, which the framework already decided

| | |
|---|---|
| one branch, filled | 3×1 + 2×2 + 1×3 = **10 compute** |
| all four branches | **40 compute** |
| what the campaign pays | **30** — summed from `compute_reward` across the 23 active `Campaign/missions/*.tres` (the 16 in `missions/appendix/` are retired; no objective pays compute — `Campaign/objective_tracker.gd:120-125` finds none set) |
| free seats | 4 (`campaign_state.gd:79`, `BASE_SEATS`) |
| a fifth robot | 1 (`campaign_state.gd:96`, `SUPPLY_COMPUTE_COST`) |

`Campaign/force_generator.gd:307` says "the campaign pays 32 compute in total"
and `docs/briefs/CAMPAIGN_REWORK.md:1270` says "about 23". The authored files say
30. Somebody should reconcile those three numbers; for this document I use the
measured 30.

**The tree cannot be filled, and that is correct.** A player who finishes the
campaign can run three branches and field four robots, or two branches and
field fourteen. Nothing here should try to soften that.

One more, which is not in the tree's comments and should be: **`site_compute()`
(`campaign_state.gd:289-297`) is called by nothing.** Holding ground pays
resources per turn but no compute today. If it is ever wired, the budget goes
from 30 to 43 and every judgement below shifts.

---

## 1. The three rules the framework hands you

**A tier-3 program costs a whole extra robot, plus change.** Three compute is
three seats. If a tier 3 reads as a percentage it is in the wrong tier. All four
tier 3s below are rule changes: a thing the game could not do before.

**Free respec means nothing can be a trap — and nothing can be an always-take.**
If one program in a branch is strictly correct the other two are decoration.
Each tier-1 trio below is built as a counter-pick set, not a ladder: SHIELDING
and SCAVENGE answer different halves of the same threat, BANDOLIER is worthless
unless you fit throwables, SALVAGE is worthless unless you field a Reclaimer.

**Ids are permanent.** `release_unknown_software` exists because a save holding
a vanished id has to get its compute back. Everything below keeps
`<branch>_<tier><a|b|c>` exactly.

### And one the framework did not decide, which bites

**Titles must be about twelve characters.** `software_page.gd:118-120` puts the
title in a label with `clip_text = true` inside an 86 px card (`:18`, `CARD`) at
font size 12 in DS-Digital. Every title below is one short word. This is cheap
to change — widen `CARD` — but it is currently true and a design that ignores it
ships clipped.

---

## 2. COMMAND — "how the squad takes orders"

Where it lands: `Campaign/squad_spawner.gd:144-158` (`_new_squad`, squad-level
exports) and `Managers/AI/squad.gd`.

| id | title | about (in voice) | effect |
|---|---|---|---|
| `command_1a` | **TETHER** | *They finish what they start.* | `follow_combat_leash` 12 → 18 and `defend_combat_leash` 9 → 14 (`squad.gd:160,161`), set on the squad at `squad_spawner.gd:144-158`. They pursue further before `_enforce_leash` (`squad.gd:653-690`) walks them back. |
| `command_1b` | **COLUMN** | *A line is a wide thing to take down a street.* | A second formation. `_slot_offset` (`squad.gd:1310-1334`) mirrors slots **across** the advance axis; COLUMN files them **along** it at the same `FORMATION_SPACING` of 2.6 (`:1271`). Chosen per team on the squad page. |
| `command_1c` | **RELAY** | *An order given once is given.* | `resync_seconds` 3.0 → 0.8 (`Character/components/squad_commander.gd:900`), and ADVANCE — not CONTACT — passes at CRITICAL by relaxing `_can_receive_orders` (`Character/characters/ai/enemy.gd:5045-5048`) for move orders only. |
| `command_2a` | **DOCTRINE** | *Tell them how to fight, once, instead of every time.* | A per-team stance: CAUTIOUS / NORMAL / AGGRESSIVE. Stance picks the leash pair above and switches `_basic_assign_roles` (`squad.gd:1709-1720`) from its half-SUPPRESSOR/half-ADVANCER split to all of one. `docs/BRIEFING.md:§6` lists this as "Designed, not built… what gives back the expressiveness lost when three verbs became two." |
| `command_2b` | **SERGEANT** | *Somebody down there has to be in charge.* | Appoints the highest-rank member as NCO at spawn. `Squad.set_nco()` (`squad.gd:1775`) **is called by nothing** — I grepped; the only readers are `bark_director.gd:274` and `debug_overlay.gd:198`, and `BRIEFING.md:§6` lists it as dead code. So `_nco_assign_roles` (`squad.gd:1723-1744`), the branch that produces an OVERWATCH and a FLANKER instead of the flat half/half, has never run in play. This turns it on. |
| `command_3a` | **BROADCAST** | *Four teams, one order.* | Adds an ALL entry to the team cycle. Today `_issue_order` always targets `get_selected_squad()` (`squad_commander.gd:426`) and G steps one team at a time (`:309`), deliberately (`:18-21`). With `MAX_TEAMS = 4` (`campaign_state.gd:140`), the real ceiling on how many robots you can use is how fast you can re-issue orders — not supply. This moves that ceiling. |

**Why SERGEANT is the best-value thing in the document.** It is two lines of
wiring that switch on a written, tested-shaped, never-executed branch. If
nothing else here gets built, build that.

**Why TETHER and DOCTRINE do not collide.** TETHER is one number in one
direction; DOCTRINE is the dial with three positions and a UI. A player running
DOCTRINE has no use for TETHER, which is the point — tier 2 should make a tier 1
redundant and cost two compute for the privilege.

**Dead exports, flagged.** `assault_combat_leash` (`squad.gd:164`) and
`follow_reissue_interval` (`squad.gd:99`) are both exported and both read by
nothing in the repo — I checked `.gd` and `.tscn`. No program above touches
them; one that did would be a no-op.

---

## 3. SIGNAL — "the link between you and them"

The branch has a spine, and it is an asymmetry nobody designed on purpose:

**The player's `signal_resistance` is permanently 1.0.** The only module in the
catalogue that raises it is `Campaign/items/item_hardened_uplink.tres:29`
(`signal_resistance_bonus = 1.0`), and line 17 of that file is
`usable_by_player = false` — "Robots only — you have no link to jam." Meanwhile
every enemy loadout carries two EMP grenades (`Campaign/enemy_loadouts.gd:55, 62,
71, 79`), an EMP does 1.15 integrity at the centre with a 3.5 s recovery lock
(`Character/weapon/emp/emp_blast.gd:30, 32`), and the player's ladder costs
movement speed all the way down (`test_character.gd:961-964`) and their squad at
the bottom.

So: the player has a jammable link and no answer. That is this branch.

| id | title | about | effect |
|---|---|---|---|
| `signal_1a` | **SHIELDING** | *Harder to reach.* | Player `signal_resistance` 1.0 → 1.6 (`Character/characters/ai/ai.gd:67`). It is a divisor on both incoming damage and lock duration (`ai.gd:165, 188`). Lands in `test_character.gd:_apply_module_stats` (`:292-317`), which today reads only `health_bonus` and `speed_multiplier` and ignores `signal_resistance_bonus` entirely. |
| `signal_1b` | **RECOVER** | *Back faster, not hit less.* | Player `signal_recovery_rate` 0.04 → 0.09/s (`ai.gd:66`). |
| `signal_1c` | **PERSIST** | *They remember what they saw.* | `contact_fresh_seconds` 3.0 → 6.0 for the player's faction only (`Managers/ai_manager.gd:201`). Three existing consequences: `SPOTTED_SPREAD` 0.82 holds twice as long (`enemy.gd:5286`, via `_contact_assisted()` `:5289-5295`), `w_fresh` target scoring (`ai_manager.gd:213`) weights longer, and allied contact marks last. The squad shoots 18% tighter by remembering. |
| `signal_2a` | **DEADHAND** | *Your blackout stops being theirs.* | `uplink_drag` 0.35 → 0 (`squad_commander.gd:962`). Today, while your link is cut, `_lean_on_squad()` (`:950-958`) actively drains **your own squad's** signal, floored at CRITICAL (`:955`). This stops the bleed being contagious. |
| `signal_2b` | **QUIET** | *An order is a flare. Stop lighting it.* | `tx_signal_cost` 0.06 → 0 (`squad_commander.gd:685`) and `tx_radius` 45 → 22 (`:679`). Every order currently costs you integrity and tells every hostile inside 45 m where you are standing when the wavefront arrives (`_front_reached`, `:807`). |
| `signal_3a` | **BLACKOUT** | *Take the link off them instead.* | A player-placed jammer field. |

**SHIELDING against RECOVER is the cleanest counter-pick in the tree, and the
numbers make it so.** Near-miss suppression is 3.0 per shot = 0.03 integrity
(`Character/weapon/ai_weapon.gd:33`) with **no lock**, so against rifle fire the
thing that matters is how fast you climb back — RECOVER. An EMP lands 1.15 and
locks recovery for 3.5 s, and a lock blocks the passive climb completely
(`ai.gd:205-208`), so against grenades recovery is irrelevant and only the
divisor helps — SHIELDING. Neither dominates. A player who keeps getting
grenaded and a player who keeps getting shot at want different programs.

**BLACKOUT, and why it is worth three compute.** `Env/world_objects/jammer_field.gd`
is written, complete and **instantiated by nothing** — the only reference outside
the script is `tools/shot_jammer.gd`. Radius 22, 0.30 integrity/s drain, re-locks
every tick, both sides equally (`:36, :43, :17-21`). Dragged below CRITICAL
(0.38, `ai.gd:44`) an enemy cannot receive squad orders (`enemy.gd:5045-5048`),
its detection radius drops to 20% (`:5064`), its vision tick returns early
(`:932-934`) and `_check_close_threat` returns false (`:3466`).

It is the only thing in the game that turns an enemy squad into five
individuals. It is worth three compute because that is a different fight, not a
better one — and because it hits you too, so it pairs with SHIELDING and makes
a five-compute commitment the tree otherwise never asks for. The file's own
header says the dead-zone/transmit interaction is "Not wired up yet; see
SquadCommander._transmit" (`jammer_field.gd:23-25`); that is part of the build.

---

## 4. COMBAT — "you, in the fight"

The player has no spread model at all. Accuracy is perfect per round; recoil is
camera motion only (`Character/weapon/hud_weapon_template.gd:221-237`); the only
dispersion is `pellet_spread_mrad` on multi-pellet guns (`:83`). There is no
crit, no headshot, no weakpoint, no damage multiplier table — grepped, zero
hits. There is no health regeneration, no revive, no overheal
(`test_character.gd:812-823` clamps). Incoming damage is scaled once, globally,
by `damage_taken_scale = 0.5` (`:81`).

This is a thin surface, and it decides the branch: COMBAT cannot be a stat
sheet, because there is no stat sheet. It has to be slots, ammunition,
handling, soak, and one rule.

| id | title | about | effect |
|---|---|---|---|
| `combat_1a` | **LOADOUT** | *One more thing on your belt.* | +1 equipment slot on `player_record` only. `equipment_capacity()` = frame slots + module bonuses (`Campaign/soldier_record.gd:316-331`); the Soldier frame gives 2 (`Campaign/chassis/chassis_soldier.tres:27`) and the loadout's positional row caps at 3 (`Character/equipment/equipment_loadout.gd:49`, `EQUIPMENT_KEYS`). So there is exactly one free key and this fills it. The ceiling already exists. |
| `combat_1b` | **BANDOLIER** | *More of it, if you carry any.* | Player reserve capacity ×1.5, applied where `AmmoPool.reset()` builds the table (`Character/equipment/ammo_pool.gd:38-50`, `_capacities[type] = stock.capacity * n`). Concretely: grenade / EMP / smoke 4 → 6, rocket 2 → 3 (`Character/equipment/ammo/*.tres`). Worthless if you fit no throwables — the thrown types are `requires_carrier = true`, so fit none, carry none (`equipment_loadout.gd:574-603`). |
| `combat_1c` | **STEADY** | *The gun comes back down on its own.* | `recoil_per_shot` ×0.7 on the player's guns (`hud_weapon_template.gd:49`). Honest limit: it does nothing for the shotgun, whose dispersion is `pellet_spread_mrad = 45.0` and not recoil. |
| `combat_2a` | **HARDEN** | *Stand in it a little longer.* | `damage_taken_scale` 0.5 → 0.35 (`test_character.gd:81`). The body stays 100 HP and soaks like 285 instead of 200. |
| `combat_2b` | **TRIAGE** | *The tool works on you too.* | Lets `PlayerRepairTool` target the player. Today the player cannot heal themselves by any route: no regen, no revive, and the tool heals others at `heal_per_second = 22` (`Character/equipment/player_repair_tool.gd:26`) out of a 100-point reservoir that recharges at 6/s after a 4 s delay (`:50, :51, :53`), including while stowed (`:211`). Holding still is already the cost — `move_penalty = 0.45` (`:58`). |
| `combat_3a` | **VECTOR** | *Moving, you are a bad shot to take.* | Enemies shooting **you** apply ×1.8 spread while you are moving, ×1.0 standing. |

**HARDEN against TRIAGE is a question about where your damage comes from.**
HARDEN is for the fight you are about to be in. TRIAGE is for the four fights
between resupplies — the player's hull is the only resource in the game that
does not come back for free (`loadout.refill()` restocks ammunition at base, on
deploy, at a resupply chute and on respawn: `test_character.gd:206, 218, 719,
851`), and nothing restores health short of base, a chute or someone else's
tool.

**VECTOR, and why it is a rule rather than a number.** `get_inaccurate_target`
(`enemy.gd:5244-5261`) takes a `Vector3` and never consults the target body.
Nothing in this codebase can make any specific thing harder to hit; there is no
`evasion`, `dodge` or `hit_chance` field anywhere. VECTOR adds the first one,
via `_aimed_body()` (`enemy.gd:5238-5242`) read inside
`get_aim_spread_multiplier()` (`:5266-5281`).

It earns three compute because it is self-cancelling in exactly the right
place: **giving an order is a stationary act.** You are holding the command ray
on a point (`squad_commander.gd:48`), and `tx_signal_cost` is charged for the
privilege. So the program is switched off at the precise moment you are being a
commander, and switched on when you are being a rifle. That is a tension, not a
buff, and it is the only tier 3 here that changes how the player moves.

**The cheapest hook in the codebase, noted in passing.**
`_apply_module_stats` (`test_character.gd:292-317`) reads `health_bonus` and
`speed_multiplier` and silently ignores `damage_bonus`, `accuracy_bonus`,
`sensor_bonus`, `signal_bonus` and `signal_resistance_bonus` — all of which the
squad side does read (`soldier_record.gd:253-258`, `squad_spawner.gd:355-360`).
Modules with those fields do nothing when the player fits them. That is a bug
independent of this document and probably worth its own ticket.

---

## 5. FABRICATION — "what the base can make"

The economy has **no multiplier of any kind** — not on buy price, unlock price,
sale value, repair cost, scrap value, income or mission reward. Every one is a
bare constant or a bare product (`Campaign/pricing.gd:149-174`,
`campaign_state.gd:531-535`). The only `*_multiplier` in the whole ledger is
`rebuild_cost_multiplier` (`campaign_state.gd:1107`). There is no crafting, no
production queue, no build time and no research time — grepped, zero gameplay
hits.

| id | title | about | effect |
|---|---|---|---|
| `fabrication_1a` | **FOUNDRY** | *It costs them less to make.* | Item and chassis purchase ×0.8. See the warning below about where this lands. |
| `fabrication_1b` | **BREAKER** | *A wreck is worth more in pieces.* | `scrap_divisor` 3 → 2 (`campaign_state.gd:1221`): a dead frame pays half instead of a third. Fitted kit already pays `sale_value` (`:1266`). |
| `fabrication_1c` | **SALVAGE** | *Grind it twice as fine.* | Reclaimer yield ×2. `Character/characters/ai/reclaimer.gd:502-514` grinds a wreck worth `e.bits` and pays through `Campaign.add_salvage()` (`campaign.gd:151-156`), which only counts during a mission. Worth nothing unless you field a Reclaimer — the most clearly conditional program in the tree. |
| `fabrication_2a` | **ARSENAL** | *Every robot carries one more.* | +1 to `equipment_capacity()` for the whole roster (`soldier_record.gd:316-331`). |
| `fabrication_2b` | **TITHE** | *The ground pays better.* | `income_per_turn()` ×1.5 (`campaign_state.gd:271-279`), paid in `advance_turn()` (`:325-329`), and a turn is an operation (`campaign.gd:1475`). Holding all nine authored sites pays 230/turn today; this makes it 345. |
| `fabrication_3a` | **CONSCRIPT** | *Bodies stop costing anything but room.* | Recruiting costs no resources — only supply. |

**FOUNDRY against TITHE is early against late, and that is deliberate.**
FOUNDRY is a flat 20% on everything you buy, which is worth most when you are
buying your first frames. TITHE scales with held ground and is worth nothing on
turn one and 115/turn at full board. Opposite curves, same tier, free respec
between them. That is the shape every tier should have.

**FOUNDRY's build warning, which is structural.** `Pricing.item_buy`,
`item_unlock`, `chassis_buy` and `chassis_unlock` (`pricing.gd:149, 157, 165,
173`) are all `static` with no `state` parameter. Threading campaign state
through them means touching every caller. **Do not.** Apply the discount at the
three places that actually spend: `CampaignState.buy_item` (`:1534`),
`buy_chassis` (`:1554`) and `recruit` (`:1051`). Three sites, no signature churn,
and the UI previews keep reading the undiscounted figure — which is its own
small bug to decide about.

**ARSENAL's wart, stated because it is the ugliest thing in this document.**
Uninstalling it *shrinks* every equipment row and pushes the displaced items
back to stores. That path is already written and already runs
(`fit_equipment_capacity`, `soldier_record.gd:336-343`, settled by
`_settle_equipment_slots`, `campaign_state.gd:1463-1465`), so free respec stays
correct — nothing is lost. But the player will toggle a program and watch kit
jump off eight robots into the armoury. Every other program in the tree is
invisible when you flip it. This one rearranges your squad.

**CONSCRIPT opens a resource loop unless it is built one specific way.**
`recruit()` allocates `Pricing.chassis_buy(chassis)` under `"unit:<id>"`
(`campaign_state.gd:1061`). If CONSCRIPT *skips* that allocation, then scrapping
the frame takes `_write_off`'s issued-stock branch — `earned += back`
(`:1291-1293`) — and mints a third of a frame's price out of nothing,
repeatably. `_kit_payout`'s comment already records that recruit-and-scrap was a
money loop once and that "the suite caught it five cycles up 30" (`:1245-1254`).

**The fix is to write a zero-cost allocation rather than skip it** —
`allocations["unit:<id>"] = 0`, exactly what `grant_unlock` does for an issued
line (`:432-439`). Then `_write_off` takes the allocation branch, finds 0 paid,
pays 0 back, and the loop never opens. Build it that way or do not build it.

**Why CONSCRIPT is worth three compute.** Not for the 50 resources a frame costs
(`pricing.gd:115`, `CHASSIS_BUY[1] = 1.0` × `BASE = 50`; every authored frame is
supply 1 — `chassis_definition.gd:25`). It is worth it because it changes what
the remaining compute is *for*: after CONSCRIPT, each further point of compute
buys a seat and the robot that sits in it, free. It makes the tree's own central
question — robot or program — resolve harder toward robots, which is a strange
and good thing for a program to do.

### What I rejected in this branch, and why

- **Cheaper ammunition.** `restock_roster()` is free on return to base
  (`campaign_state.gd:1176-1179`, called once from `campaign.gd:1616`) and
  `BRIEFING.md:§6` says charging for it "is the decision that makes ammunition a
  campaign resource." That decision is unmade. A discount on a price of zero is
  not a program.
- **Cheaper rebuilds** (`rebuild_cost_multiplier` 2.0 → 1.0,
  `campaign_state.gd:1107`). `allow_rebuild` defaults to **false** (`:1226`), so
  REBUILD is not offered at all today. The program would be inert on arrival.
- **An armoury capacity upgrade.** `Campaign/armoury.gd:19` is an unbounded
  dictionary and `add()` never checks a limit. There is no capacity to raise.
- **A production queue.** Nothing in the game is scheduled against `turn`
  except income. It would be the first system needing a per-turn tick for
  anything else, which is far too much weight for one card on a grid.

---

## 6. What this costs to build

**The shared piece, which every program needs.** One accessor on the tree —

```
static func running(state, id: StringName) -> bool
```

— and a resolve at each of four landing zones, using the group lookup this
codebase already uses nineteen times over
(`get_tree().get_first_node_in_group("campaign")`, e.g.
`Campaign/squad_spawner.gd:366`, `test_character.gd:193`):

| zone | file | what lands there |
|---|---|---|
| per-robot stats at spawn | `Campaign/squad_spawner.gd:288-360` (`_fit_loadout`) — where module bonuses already land | SIGNAL squad effects, ARSENAL |
| per-squad exports at spawn | `Campaign/squad_spawner.gd:144-158` (`_new_squad`) | TETHER, COLUMN, DOCTRINE, SERGEANT |
| the player | `test_character.gd:292-317` (`_apply_module_stats`) | SHIELDING, RECOVER, HARDEN, BANDOLIER, STEADY |
| campaign maths | `campaign_state.gd` / `pricing.gd` | FOUNDRY, BREAKER, TITHE, CONSCRIPT |

**A mission can run with no campaign at all** — the Laboratory and the sim
arenas do. Every read must default to "not running" when the group lookup comes
back null, and say so in a comment, because a silent zero here is exactly the
kind of early return `CLAUDE.md` warns about.

### Which programs are not grounded in existing code

Eight, in rough order of weight. Everything not listed moves a number that is
already read every frame.

| program | what it needs that does not exist |
|---|---|
| **DOCTRINE** | a per-squad stance field, a control on the squad page, and the role-split branch. The biggest build in the document. `BRIEFING.md:§6` already wants it |
| **BLACKOUT** | a placement verb (the Designator already commits ordnance at a point — `Character/equipment/player_designator.gd:450`), plus the jammer's transmit interaction, unwired by its own admission |
| **VECTOR** | a per-target evasion term. No `evasion`/`dodge`/`hit_chance` field exists anywhere; `get_inaccurate_target` never sees the target body |
| **COLUMN** | a second branch in `_slot_offset` (`squad.gd:1310`) and a per-team choice. ~15 lines, no new system |
| **BROADCAST** | an ALL entry in the team cycle and an order fan-out. `_issue_order` is single-target by design |
| **TRIAGE** | self-targeting in `PlayerRepairTool`. The reservoir, the channel, the interrupt and the move penalty all exist |
| **RELAY** | a move-orders-only exemption in `_can_receive_orders` (`enemy.gd:5045`) — a real behaviour change to the signal ladder, not a tuning value |
| **FOUNDRY** | the discount moved off `Pricing`'s static functions onto the three spend sites |

**Honourable mention: SERGEANT needs nothing.** The function, the role split and
the bark consumer are all written. It needs a caller.

---

## 7. The honest weakness

**You can respec in the middle of a firefight.**

`SquadManagerUI` lives in `Env/world.tscn`, binds to TAB
(`Character/hud/squad_manager_ui.gd:30`), and `open()` (`:166-181`) checks only
that a campaign exists. There is no base gate, no mission gate. It takes
`PauseHold` and stops the world.

So the sequence is: walk into an EMP, pause, uninstall TITHE, install SHIELDING,
unpause. Free respec at any time plus a pause menu that opens anywhere means
every program in this tree is really a context-sensitive ability with a
loading screen in front of it, and the "robot or program" question the tree is
built around is answered differently on every street corner.

The framework's own comment says the choice is "what you run right now"
(`software_tree.gd:11`). It did not mean right *now*.

Two fixes, and they are not equivalent:

- **Cheap:** disable INSTALL and UNINSTALL while `Campaign.in_mission`
  (set false at `campaign.gd:1580`, true at `begin_deploy`). Roughly four lines in
  `software_page.gd:143-165`. The page stays readable in the field, which is
  right — you should be able to see what you are running.
- **Honest:** let the *installs* stand and freeze the *effects* at deploy, the
  way `SoldierRecord`s are snapshotted. More work, and it preserves the fiction
  that your own code is not something you edit while being shot at.

Either way: **this document's whole balance assumes the cheap fix at minimum.**
Without it, tier 1 is strictly better than tier 3 for every player who is
willing to pause, because three one-compute programs swapped on demand beat one
three-compute program that has to be right in advance.

The second weakness is smaller and already stated: the tree costs 40 and the
campaign pays 30, so **six of these twenty-four will never be seen by most
players in one run.** That is a feature of the budget, not a flaw in the
programs — but it means the six tier-1s a player meets first carry more weight
than the four tier-3s, and the tier-3s are where all the interesting rules are.
If that bothers the human, the lever is `TIER_COST` (`software_tree.gd:35`), not
this list.
