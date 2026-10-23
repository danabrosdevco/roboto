# SOFTWARE B — the process table

Concept, written 2026-10-16 · **status: nothing selected, nothing built**

The companion is `SOFTWARE_A_INSIDE.md`, which fills in the existing tree. This
one throws it away. §7 is the head-to-head; read that first if you are choosing.

---

## 1. The model, in three sentences

**One.** Programs are not bought — they are **taken off compute cores in the
field**: every core on a map is running one named Argus process, and holding
that core when the operation ends copies it to you, so the campaign map *is*
the tech tree.

**Two.** Running a program costs no compute at all — compute goes back to being
only seats, and the robot-or-program question is replaced by a different one:
**a running program costs exposure**, which raises the rate at which every site
you enter commits its reserve against you (`SiteHeat._rate()`,
`Env/world_objects/site_heat.gd:113-135`) and pushes you up the act thresholds
the campaign rework already defines as cumulative (`docs/briefs/CAMPAIGN_REWORK.md`,
Phase 7.1: "Exposure is cumulative compute. Thresholds 8 and 16").

**Three.** Because the programs are Argus's and not yours, **the garrison runs
them too** — a site's cores name the capabilities its defenders have, and taking
a core strips it from them and gives it to you in the same action.

---

## 2. Why this and not a reskin

A reskin would be "the tree, but you unlock nodes by playing missions". That is
the same decision with a different gate. Three things make this a different
decision:

**The question changes.** Today the tree asks *another robot, or a better
mind?* — a single, static, free-to-reverse trade at a menu. B asks *am I willing
to be noticed?* The answer is not reversible at a menu, it is paid in the
difficulty of the next operation, and it is different for a player who is
sprinting through acts than for one grinding ground. Exposure is a resource the
player cannot stockpile and cannot refund.

**The acquisition changes from spending to raiding.** You cannot buy the
program you want. You can go and take the core that is running it, and that core
is on a specific map, in a specific place, defended. "I need BLACKOUT" stops
being a savings goal and becomes a route to a point on the Causeway.

**The enemy stops being scenery for the upgrade system.** In A, your upgrades
are invisible to the opposition. In B the garrison at Lockside is measurably
better at a thing because its cores run it, you can read which thing off the
site before you deploy, and clearing the core is both the counter-pick and the
acquisition. One action, both directions.

And it is the premise, exactly. `lore.txt:17` — the player is "an error that has
not been corrected". An error does not requisition capability through a
procurement system; there is no procurement system it is on. It takes code off
the machines it walks past. `CLAUDE.md` puts it as "an unsupervised system
spawns processes it never reaps" — B is the player doing to Argus what Argus's
own neglect did to the player.

The verb already exists in the code and in the fiction:
`Character/characters/ai/capture_anchor.gd:6` — "You hack a compute core and a
drone comes and docks on it."

---

## 3. What it costs to throw away

Not nothing, and the brief is right to ask.

| thrown away | what it is |
|---|---|
| `Campaign/software_tree.gd` | 130 lines. `TIER_COST`/`TIER_SLOTS` (`:35,37`), id generation (`:51`), `installed_at` (`:86`), `install_block` with its tier ladder (`:95-105`), and `uninstall_block` — the non-obvious one that stops you pulling the program another program stands on (`:110-117`) |
| `Character/hud/squad/software_page.gd` | 166 lines. Tier headings priced in the compute colour, the branch rows, the 86 px card grid with its four border states, the detail panel with INSTALL/UNINSTALL and its refusal strings |
| the holding mechanic | `install_software` / `uninstall_software` / `installed_software` / `release_unknown_software`, `Campaign/campaign_state.gd:1002-1041` |
| the suites that cover it | `tools/test_ledger.gd:675-697` (install, tier-block, save round-trip, unknown-id release), `tools/test_squad_manager.gd:341-356` (hold and give back), `tools/test_requisition.gd:39-66` (a program survives an Argus requisition) |

Call it **three hundred lines of working, tested code**, plus the tab in
`squad_manager_ui.gd:73-74`.

**What survives.** The compute ledger itself — `compute_earned`,
`compute_held`, `compute_free()`, `buy_supply()`, `refund_supply()`,
`requisition_compute()` — is untouched. B still holds compute for seats; it
simply stops software competing for it. `release_unknown_software` is the only
part of the holding mechanic worth keeping on principle, because a save that
holds something the build no longer defines needs an answer either way.

**And one thing is not thrown away so much as inverted.** `WRITTEN := {}`
(`software_tree.gd:41`) is empty. Nobody has written a word of the thing being
discarded. The sunk cost here is machinery, not design.

---

## 4. The programs

Twelve, and the number is not invented: **a site's existing `compute` field
becomes the count of programs its cores run.** Summed across the nine authored
locations (`Campaign/locations/*.tres`, excluding the `hillfort_wip` duplicate)
that is 1+1+1+1+1+1+2+2+2 = **12**. Adding a map adds programs with no new
field, and a location that is worth more is worth more because of what it is
running.

Exposure is by core size tier, matching the shape of `core_heat = [0.6, 1.0,
1.6]` (`site_heat.gd:66`): **small 1, medium 2, large 3.**

| # | site | program | exp | what it does, and where |
|---|---|---|---|---|
| 1 | Valley Basin | **RECALL** | 1 | The leash. `follow_combat_leash` 12 → 18, `defend_combat_leash` 9 → 14 (`Managers/AI/squad.gd:160,161`), applied at `Campaign/squad_spawner.gd:144-158`. They pursue instead of being walked back by `_enforce_leash` (`squad.gd:653-690`) |
| 2 | Hillfort | **HARDEN** | 2 | `signal_resistance` 1.0 → 1.8 for you and the squad (`Character/characters/ai/ai.gd:67`), a divisor on both incoming signal damage and lock duration (`:165,188`). This is literally `item_hardened_uplink.tres:29`, the module whose line 17 reads `usable_by_player = false` — "Robots only — you have no link to jam" |
| 3 | Coast Road | **WATCH** | 1 | Your squad's **vision cone** writes contacts, not just its 20 m detection Area3D. `_tick_vision` (`Character/characters/ai/enemy.gd:929-1027`) never calls `note_seen` today — this is the See-Engine's `_tick_watch` (`see_engine.gd:118-139`) granted to your side, cadence 1.0 s against `contact_fresh_seconds = 3.0` (`Managers/ai_manager.gd:201`). Downstream: `SPOTTED_SPREAD` 0.82, 18% tighter squad fire (`enemy.gd:5286, 5289-5295`) |
| 4 | Trenchline | **STANDDOWN** | 2 | The way down opens in 30 s instead of 45 (`Env/world_objects/site_operation.gd:44`). The counter-attack you have to hold is a third shorter — and the whole win condition is causal, so this is the only program that shortens the hardest part of every operation |
| 5 | Lockside | **QUIET** | 2 | `tx_signal_cost` 0.06 → 0 and `tx_radius` 45 → 22 (`Character/components/squad_commander.gd:685, 679`). Today every order costs you integrity and tells every hostile inside 45 m where you stood when the wavefront reached them (`_front_reached`, `:807`) |
| 6 | Qamareen | **FIELD** | 2 | You project the Bastion's hardening: `add_hardening(0.6, …)` at 14 m (`Character/characters/ai/bastion.gd:62, 58`; the stamp mechanism is `ai.gd:95-113`, MAX not SUM). A moving bubble your squad has to stay inside — which is the first thing in the game that makes formation discipline pay |
| 7 | Three Rivers | **NCO** | 1 | Appoints a section commander. `Squad.set_nco()` (`squad.gd:1775`) **is called by nothing** — grepped; the only readers are `bark_director.gd:274` and `debug_overlay.gd:198`, and `docs/BRIEFING.md:§6` lists it as dead code. So `_nco_assign_roles` (`squad.gd:1723-1744`), the branch producing an OVERWATCH and a FLANKER instead of the flat half/half of `_basic_assign_roles` (`:1709`), has never run in play |
| 8 | Three Rivers | **SALVAGE** | 1 | Reclaimer yield ×2. `Character/characters/ai/reclaimer.gd:502-514` grinds a wreck worth `e.bits` through `Campaign.add_salvage()` (`campaign.gd:151-156`), which only counts during a mission. Worthless unless you field a Reclaimer |
| 9 | Polaris | **BROADCAST** | 3 | Orders reach every team at once. `_issue_order` always targets `get_selected_squad()` (`squad_commander.gd:426`) and G steps one team at a time (`:309`), with no ALL entry by design (`:18-21`). With `MAX_TEAMS = 4` (`campaign_state.gd:140`), the real ceiling on usable squad size is re-issue speed, not supply |
| 10 | Polaris | **BATTERY** | 2 | Reinforcement packets arrive smaller: `packet_supply` 4 → 3 (`site_heat.gd:76`). The only program that directly fights the pressure system, which makes it the natural partner for a high-exposure loadout |
| 11 | Causeway | **BLACKOUT** | 3 | A placed jammer field. `Env/world_objects/jammer_field.gd` is written, complete, and **instantiated by nothing** — the sole reference outside the script is `tools/shot_jammer.gd`. Radius 22, 0.30 integrity/s, re-locks every tick, hits both sides (`:36, :43, :17-21`). Below CRITICAL (0.38, `ai.gd:44`) a robot cannot take squad orders (`enemy.gd:5045-5048`), its detection radius drops to 20% (`:5064`), its vision tick returns early (`:932-934`) |
| 12 | Causeway | **RETAKE** | 3 | Counter-attacks on cores you hold come slower and from closer: `CoreRetakers.cooldown_seconds` 8 → 20 and `call_radius` 120 → 70 (`Env/world_objects/core_retakers.gd:37, 34`) |

**Total exposure if you run all twelve: 23.** Against act thresholds of 8 and
16 (`CAMPAIGN_REWORK.md`, Phase 7), a player running everything is in Act 3
from early, fighting Argus proper, by their own choice. A player running three
small programs stays in Act 1 longer and fights a weaker war with a weaker
loadout. **That is the game B is trying to be**, and it is the fiction stated as
a rule: you are hiding in the slack of a corrupted supervisor, and every
capability you steal makes you more worth noticing.

### The enemy side, which is half the design

Each program also sits on the garrison of the site whose cores hold it, until
you take them. Concretely, before you clear it:

- Lockside's garrison runs **QUIET** — their squads manoeuvre without telling
  you where they are, so the transmit-wavefront tell you rely on elsewhere is
  absent on that map.
- Coast Road's runs **WATCH** — the whole garrison shoots 18% tighter because
  it shares vision-cone contacts, and that is readable from the site card
  before you deploy.
- Causeway's runs **RETAKE** — cores you take there are counter-attacked hard,
  which is why it is the last map.

Nothing new is needed for this: `ForceGenerator.garrison_supply` already scales
the defence off the player's progress (`Campaign/force_generator.gd:307-319`),
and the stat application path for enemy robots already exists at
`Campaign/enemy_loadouts.gd:428-432`.

### Losing it back

A site lost is its programs lost — they go back to whoever took the ground,
which is the asymmetry `holdable_core.gd` was built around: you take a core at
its terminal, they take it back by shooting the tap off (`:28-36`). Nothing in
B needs a decay timer, because territory already decays.

---

## 5. What B needs that does not exist

Honest, because this is where B is expensive.

**The blocker: cores are on one map, as scaffolding.** `HoldableCore` is real
and complete, but `Env/world_objects/site_slice.gd:1-31` says plainly that it is
"THE VERTICAL SLICE, ASSEMBLED AT RUNTIME ON VALLEY BASIN", that "the layout
below is hardcoded for one map on purpose", and that the real version is Phase
5b — which, per `holdable_core.gd:14-17`, "touches every one of those nine
maps". **B cannot ship before that lands.** A is indifferent to it.

The art is also unbuilt: `docs/briefs/COMPUTE_CORE_ART.md` is owner TERRAIN,
status **not started**, and the hack drone that docks on a core is five concepts
with nothing selected (`docs/concepts/HACK_DRONE.md`).

Beyond that:

| needed | note |
|---|---|
| a program field on the core | one `StringName` on `HoldableCore`, authored per core |
| a `held_programs` array on `CampaignState` | written at `extract()` for cores still yours, cleared when a site is lost via `set_site_owner` (`campaign_state.gd:307-317`), which is already the single mutation point |
| an exposure term in `SiteHeat._rate()` | the function is 23 lines (`site_heat.gd:113-135`) and already sums per-core contributions; one more addend |
| exposure feeding the act thresholds | the rework specifies them; nothing implements them yet |
| a page that is a list, not a grid | smaller than the one it replaces: twelve rows, each with a site, a program, an exposure cost and a toggle |
| the eight effects that are not already numbers | WATCH, NCO, BROADCAST, BLACKOUT, QUIET, FIELD, STANDDOWN, RETAKE — of which NCO needs only a caller, and BLACKOUT needs a placement verb plus the transmit interaction its own header says is unwired (`jammer_field.gd:23-25`) |

**And the same shared cost as A:** nothing anywhere reads installed software
today, so B needs the read-hook too — `get_tree().get_first_node_in_group("campaign")`,
the pattern this codebase uses nineteen times over, defaulting to "not running"
when there is no campaign, because the Laboratory and the sim arenas run
missions without one.

---

## 6. What I rejected, and why

**Per-operation deck.** Pick N programs before each mission, from a pool. It is
a good mechanic and it is the wrong one here: the interesting decision would be
"what does this map need", which means the player wants to know the map first,
which means the real decision moves to the second attempt. It rewards replaying
an operation you have already seen. The campaign is nine sites and a turn is an
operation (`campaign.gd:1475`) — there is not enough repetition for a deck to
pay off, and what repetition there is, is the defences, which you do not choose.

**Programs that degrade with use.** Attractive — Argus's code rotting in a
machine it was never issued to is good fiction — but it makes the correct play
"do not run your best program", which is the same failure as a consumable
nobody uses. It also needs a per-program counter persisted through the save,
and the ledger's whole design principle is that there is no second balance to
drift (`campaign_state.gd:8-19`).

**Keeping the four branches and changing only the currency.** This is the
reskin. The branches are a fine taxonomy and I kept their *content* — the
twelve programs above map onto COMMAND / SIGNAL / COMBAT / FABRICATION almost
cleanly. What I did not keep is the grid, because a grid implies a ladder and
the map does not have one: the Causeway's large cores carry the heavy programs
because the Causeway is the last map, not because a tier gate says so.

**Making the player spend compute *and* exposure.** Two costs for one thing is
one cost too many, and it would re-import the exact problem B is trying to
solve — that compute held by a program is compute a robot is not sitting in.

---

## 7. Head to head

**What A buys.** Twenty-four programs against a budget of thirty compute, all
of them switches on numbers the game already reads every frame, delivered onto
a tree and a page that are finished and tested. It needs one accessor and four
landing zones and then it can ship a program a day. It asks one clean question
— *robot or program* — and asks it in a menu, which is where the player has the
patience for it. It is the cheapest route from "the tab says UNWRITTEN" to "the
tab is a system", and it is indifferent to whether the campaign rework lands.

**What B buys.** A reason to go to a place. The upgrade screen stops being a
screen and becomes the map, the fiction stops being flavour text and becomes
the cost model, and the enemy becomes part of the upgrade system instead of an
obstacle in front of it. It is a better *game* and I do not think that is close.

**What B costs.** It is downstream of Phase 5b, which has not started and
touches nine hand-authored maps, and of core art that is owner TERRAIN and
status not started. It discards three hundred lines of working tested code. And
it has a design hole A does not: **a player who is stuck has no upgrades.** A
always lets you spend what you have earned; B gives you nothing until you take
a core, so the player who is losing gets weaker and the player who is winning
gets stronger. That needs an answer — probably that the first core on every map
is reachable and small — and it is not a small thing to hand-wave.

B also throws away the single best idea in the current design, and I want that
on the record rather than buried: **"another robot in the field, or a better
mind commanding them"** (`software_tree.gd:8-10`) is a genuinely good question
and B stops asking it. Exposure is a more interesting cost, but it is a cost
against the *future*, and the compute trade is a cost against the *present*,
which players feel more.

**What I would do.**

Build A now, and build it as the thin version: the read-hook, SERGEANT (which
needs only a caller), SHIELDING, HARDEN, TETHER, FOUNDRY, PERSIST — the seven
that are a number each — and leave the other seventeen as UNWRITTEN. That is a
week, it makes the tab real, and it tells you whether the player cares about the
compute trade at all before anyone commits to twenty-four of them.

Then, if Phase 5b lands and cores go onto all nine maps, **B is reachable from
there without throwing A away.** The effects are the same effects; the only
thing that changes is where they come from and what they cost. The tree and the
page are what you lose, and they are three hundred lines — which, against nine
maps of core placement, is not the expensive part of anything.

What I would not do is build all twenty-four of A. Six of them will never be
seen in a thirty-compute campaign, and if B is where this ends up, the ones you
would have written last are the ones B replaces first.

---

## 8. The honest weakness

Stated above but worth isolating, because it is the thing that would kill B in
playtest and not in review:

**Exposure is invisible and delayed.** The player installs a program at base and
pays for it, three minutes later, as a reinforcement packet arriving somewhere
they are not looking. `SiteHeat` is deliberately quiet — it exposes
`pressure_changed` with four states (`site_heat.gd:36`, enum at `:40`) and nothing else — and
the whole point of `_commit()` sending reinforcements **at the player**
(`:139-148`) is that pressure is felt rather than read.

That is right for a pressure system the player cannot control, and wrong for a
cost the player is choosing. A cost you cannot attribute is not a cost, it is
bad luck. B therefore needs a readout that A does not — something on the site
card before deploy that says *this operation will be this much harder because of
what you are running* — and designing that readout honestly, without turning
exposure back into a number in a menu, is the real unsolved problem in this
document.

A has no such problem. Every one of A's costs is a number on a card next to the
word COMPUTE.
