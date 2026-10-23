# SITE CONVERSION — the other eight maps

**Written 2026-10-13, from measurements.** Valley Basin has been through the
whole rework and works. This is what the same treatment costs on every other
map, grounded in `tools/probe_map_geography.gd` rather than in what the tag
names sound like.

> **MEASURE FIRST. THIS IS WHY.** The basin's defence was authored by picking
> tags that read as defensive — `trench_n`, `trench_s`, `tower`. All three sit
> at the far WEST end, 250 m from where the attackers arrive, and the garrison
> spent the entire fight alone at the wrong end of the map. Every coordinate
> below came out of the probe.

---

## THE PATTERN, as Valley Basin now has it

| | |
| --- | --- |
| **Cores** | 3–5 capture points. Reversible, anchored, shootable. The site IS the cores |
| **A bunker** | one always-marked place. Holding it is how an attack ENDS |
| **Entries** | named edge markers. Degree = how many. They are the board's connections |
| **Garrison posts** | one per core, for the defence. Measured against the cores, not chosen by name |
| **A Location** | res/turn, compute, resistance measured from the authored force |
| **Two operations** | attack and defence, on one Location |

## WHAT EVERY MAP NEEDS, found by the survey

**1. EVERY MAP HAS AN `_extract` OBJECTIVE, AND §12.7 DELETES EXTRACTION.**
All nine: `hillfort_extract`, `coast_extract`, `sal_extract`, `pitt_extract`,
`pol_extract`, `cway_extract`, `gt_relay_*`'s sibling, and the basin's two.
Each is a free bunker site — it is already placed where the mission expects
the player to end up. **Convert, do not delete.**

**2. THE `_relay_` OBJECTIVES ARE THE CORES.** Every map names them the same
way and they are already spread across the ground. Nothing needs inventing on
seven of the nine.

**3. `_hive_` OBJECTIVES ARE NOT CORES.** They are eliminate objectives sitting
on nests. Leave them alone; they are the other half of a mission.

**4. THREE MAPS DO NOT LACK TAGS — they lack ENTRY-NAMED ones.** Polaris (46
tags), the Causeway (81) and Georgetown (61) are among the most heavily
tagged in the game. An earlier note in §16.3 said they had none; that was a
grep against the level file, and tags on prefab instances live in the prefab.
**Corrected.** What they need is a handful of existing edge tags NAMED as
connections, not a tagging pass from nothing.

---

## HILLFORT · the opener

576 × 755 m · 18 tags · **1 relay**

| | |
| --- | --- |
| Cores | `hillfort_relay` (-12, -262) — **only one** |
| Bunker | convert `hillfort_extract` (72, -292) |
| Entries | `obj_hillfort_trailhead` (0, 430) — **degree 1** |
| Garrison | `cistern` · `gate` · `terrace` · `yard`, all on the climb |

**ONE CORE AND ONE WAY IN.** Its own briefing says *"One way on"* and the
measurement agrees. That makes it the right opening site and a **bad defence** —
no flanks, nothing to cover, one approach.

> **Do not build a defence variant for Hillfort.** Give it the attack
> treatment and leave it off the raid list. A site with degree 1 behind your
> lines is interior and untouchable anyway, which is the frontier rule doing
> the right thing by accident.

**Needs:** two more cores invented if it is to feel like a site rather than a
single objective, or accept it as the tutorial-weight opener it already is.

---

## COAST ROAD · the corridor

700 × 220 m · 13 tags · **3 relays**

| | |
| --- | --- |
| Cores | `coast_relay_bridge` (-105) · `_craters` (-55) · `_town` (292) |
| Bunker | convert `coast_extract` (505, 20) — the east end |
| Entries | `east_in` (590, -50) · `north_in` (150, -150) · `obj_coast_bridge` (-110, -25) — **degree 3** |
| Garrison | `gate` · `hill` · `town_e` · `town_w` |

**A 700 m LINE.** The cores are strung along it, which is excellent for the
attack — its briefing's *"each relay you take calls something different"* is
already the heat model in prose — and mediocre for a defence, because two of
the three approaches are the same axis.

`north_in` is the saving grace: a genuine flank. A defence here should put the
weight through it rather than up the road.

---

## OVER THE TOP · the ladder

600 × 290 m · 12 tags · **4 relays in depth**

| | |
| --- | --- |
| Cores | `sal_first_line` (60) · `sal_support` (190) · `sal_guns` (330) · `sal_back` (420) |
| Bunker | convert `sal_extract` (455, 165) |
| Entries | `jumpoff` (-170, 0) W · `railhead` (350, -195) N · `village` (430, 95) E — **degree 3** |
| Garrison | `redoubt` · `sap_north` · `sap_south` · `crater` |

**THE BEST-SHAPED MAP IN THE GAME FOR THIS, and nobody designed it that way.**
Four cores at x = 60 / 190 / 330 / 420 is a literal depth ladder: the attack is
breaking four lines in sequence, and the defence is the same ladder backwards,
giving ground one line at a time.

**It is also the hardest site on the board** — 365 supply measured, against
the Causeway's 351 — and it pays 23 a turn. That mismatch is flagged in the
Stage 2 notes and should be settled before anyone plays it.

---

## THREE RIVERS · the showcase

1074 × 515 m · 18 tags · **5 relays** · the biggest map

| | |
| --- | --- |
| Cores | `pitt_relay_dam` (-298, -161) · `_shore` (-155, -45) · `_strip` (100, -85) · `_furnace` (395, 237) · `_port` (352, -265) |
| Bunker | convert `pitt_extract` (505, 20) |
| Entries | `in_east` · `in_nw` · `in_mon` · `in_ne` · `in_shore` · `in_south` — **degree 6, the highest** |
| Garrison | `island` · `bridge` · `coke` · `point` · `ohio` |

**THE DEFENCE MAP.** Six approaches converging on five cores spread over a
kilometre is exactly what §11 says a defence wants and says none of the nine
have. It has it.

> **Do this one second, after Valley Basin.** It is the only other map where a
> defence can be judged properly, and §12.6's claim that "Three Rivers has
> four" entrances undercounts it — it has six.

---

## POLARIS · the hold-out

569 × 576 m · 46 tags · **3 cores + 5 wave triggers**

| | |
| --- | --- |
| Cores | `pol_breach` (0, 56) · `pol_cinema` (-92, 92) · `pol_garage` (96, 86) |
| Bunker | convert `pol_extract` (-40, -42) |
| Entries | `big_box` (-313) W · `basin` (256) E · `school` (-318) N · `frontage` (258) S — **degree 4** |
| Garrison | `anchor_e` · `anchor_w` · `corral_e` · `bank` |

**THE ONE MAP ALREADY DRAWN AS A DEFENCE.** Its own briefing: *"Not an advance.
You go in, you start the drain, and then you hold."* The five `pol_wave_*`
objectives are a wave director that predates all of this and does by hand what
`SiteHeat` now does generically.

> **Read `pol_wave_*` before touching it.** There is an existing hold-out
> implementation here, and the right move may be to let SiteHeat replace it
> rather than run two directors on one map.

---

## THE CAUSEWAY · the long crossing

1235 × 290 m · 81 tags · **7 cores** · the longest map

| | |
| --- | --- |
| Cores | `relay_staging` (-350) · `_crossing` (12) · `_checkpoint` (352) · `_yard` (470) · `_basement` (513) · `_twelfth` (530, y 72) · `cway_uplink` (513, y 138) |
| Bunker | **`cway_bunker` already exists** (520, -148) — no conversion needed |
| Entries | `terrace` (-575) W · `sangar_east` (660) E — **degree 2** |
| Garrison | `bastion_ne/nw/se/sw` (441–619, ±89) — a built four-corner redoubt |

**SEVEN CORES, TWO WAYS IN, AND A BUNKER ALREADY BUILT.** The most
map-per-metre of anything in the project, and the four `bastion_*` tags are
already a garrison ring round the east end.

Note the Y values: `_twelfth` at 72 m and `cway_uplink` at 138 m are **up the
tower**. A vertical site. The beacon columns will need shortening here or they
will spear through the structure.

Degree 2 on a 1235 m corridor makes it a poor defence and a superb attack —
which matches §6's observation that the Causeway is a dead end behind Polaris,
and that taking Polaris first makes it untouchable forever.

---

## LOCKSIDE · the terraces

436 × 298 m · 61 tags · **5 relays**

| | |
| --- | --- |
| Cores | `gt_relay_park` (-34, 132) · `_stack` (86, 112) · `_lock` (48, -9) · `_street` (-40, -108) · `_mill` (-212, -6) |
| Bunker | convert its extract |
| Entries | `mill` (-212) W · `town_mill` (224) E · `back_lane` (-136) N · `esplanade` (162) S — **degree 4** |
| Garrison | `compound` · `cofferdam` · `canal_works` · `berm` |

**FIVE CORES ON FOUR BENCHES, FOUR WAYS IN.** The second-best defence shape
after Three Rivers, and the only one with real verticality in the playable
ground — its briefing's *"four flat benches, not a slope"* means a defender can
hold a terrace rather than a line.

---

## QAMAREEN · unresolved

`heliostat_level` reports **2 tags, 2 capture points, and an extent of
228 × 0 m** — a degenerate survey. Either the mission points at a different
level than the probe assumed, or the map is not finished.

> **Do not write a brief for this one until that is resolved.** It is the only
> map where the measurement did not produce something usable, and guessing is
> precisely what this document exists to stop.

---

## ORDER OF WORK

| | | why |
| --- | --- | --- |
| 1 | **Three Rivers** | degree 6, five cores. The only other map a defence can be judged on |
| 2 | **Over The Top** | the depth ladder is free design; settle its 365-supply / 23-a-turn mismatch while there |
| 3 | **Lockside** | degree 4, five cores, real verticality |
| 4 | **Polaris** | read `pol_wave_*` first; may be a replacement rather than an addition |
| 5 | **Coast Road** | attack-first. The defence leans entirely on `north_in` |
| 6 | **The Causeway** | attack-first. Seven cores is a lot of value; degree 2 makes the defence a corridor |
| 7 | **Hillfort** | attack only. Do not give it a defence |
| — | **Qamareen** | blocked on the survey |

**The shared work, worth doing once rather than eight times:** nine `_extract`
objectives become bunkers, nine Locations gain `defend_mission_id`, and
`BasinSlice` stops being basin-specific. It is already a generic assembler with
four hardcoded node names — lifting those into exports makes it `SiteSlice` and
the other eight become data rather than code.

---

# THE INTEGRATION PLAN

**Written 2026-10-13, after `SiteSlice` landed.** The eight maps are now a data
exercise, not eight copies of a four-hundred-line file. This is what each one
costs and the order to spend it in.

## WHAT A SITE COSTS, NOW THAT THE SLICE IS GENERIC

`Env/world_objects/site_slice.gd` does all of it — cores, the bunker, heat, the
commander, the garrison, the beacons, the win and the loss. A map supplies
**answers**, not behaviour. Valley Basin's are 60 lines and most of that is
comment:

```gdscript
extends "res://Env/world_objects/site_slice.gd"

func _init() -> void:
    cores_by_node = {"InteractObjective": 0, "AnchorObjective": 2}
    bunker_marker = &"Basin_ExitPass"
    entry_markers_named = [&"Basin_North", &"Basin_South"] as Array[StringName]
    resistance = 82
```

**Per map, in order:**

| | | cost |
| --- | --- | --- |
| 1 | A `*_slice.gd` subclass with the brief's table | ~30 lines of data |
| 2 | One node added to the level `.tscn` | 2 lines |
| 3 | A `Location` .tres: res/turn, compute, measured resistance, `connects_to` | 12 lines |
| 4 | The attack mission's `active_objectives` → the cores | 1 line |
| 5 | A defence mission .tres: attackers, `garrison_posts`, `defence = true` | ~90 lines, mostly the authored attack shape |
| 6 | `defend_mission_id` on the Location, and a board position | 2 lines |

**Only (1), (3) and (5) carry judgement.** The rest is mechanical.

## THE SHARED WORK, WORTH DOING ONCE

**1. NINE `_extract` OBJECTIVES BECOME BUNKERS.** §12.7 deletes extraction and
every map has one, already placed where the mission expects the player to end
up. Converting is `bunker_marker = &"<the extract's marker>"` per map, plus
dropping the id from `active_objectives`. Valley Basin is done; eight to go.

**2. EVERY ATTACK MISSION'S `active_objectives` IS STILL THE OLD CHECKLIST.**
The basin listed one core and an extract while the slice built four cores — the
HUD disagreed with the map. Every other map has the same mismatch waiting.

**3. RESISTANCE IS ALREADY MEASURED FOR ALL NINE.**
`tools/measure_resistance.gd` has the table; the Locations already carry it.
Nothing to do but keep it honest when forces change.

**4. `pol_wave_*` MUST BE READ BEFORE POLARIS IS TOUCHED.** There is a
hand-built wave director there doing what SiteHeat now does generically.
Two directors on one map is worse than either alone.

## ORDER, AND WHY

| | | |
| --- | --- | --- |
| **1** | **Three Rivers** | degree 6, five cores over a kilometre. The only other map a defence can be judged on. Do it next and play it |
| **2** | **Trenchline** | four cores at x = 60/190/330/420 is a free depth ladder. Settle its 365-supply / 23-a-turn mismatch while there |
| **3** | **Lockside** | degree 4, five cores, real verticality on four benches |
| **4** | **Polaris** | read `pol_wave_*` first. May be a replacement rather than an addition |
| **5** | **Coast Road** | attack-first; the defence leans entirely on `north_in` |
| **6** | **The Causeway** | attack-first. Seven cores, degree 2, and a bunker already built |
| **7** | **Hillfort** | attack ONLY. One core, one way in — do not give it a defence |
| — | **Qamareen** | blocked: the survey returned 2 tags and a 228 × 0 m extent |

## WHAT TO DO AFTER EACH ONE, NOT AT THE END

Valley Basin took six rounds of fixes, and **every one of them was found by
watching it rather than by a test** — the garrison 250 m from the fight, forty
attackers culled and idle, cores that could not be taken, anchors parked above
everyone's heads. The suites passed throughout.

> **After each map: run `tools/watch_defence.gd` against it and look.** It
> takes four minutes. The alternative is finding six of these at once on the
> eighth map with no idea which change caused what.

`watch_defence.gd` is currently hardcoded to the basin's defence; generalising
it to take a mission id is a ten-line change and should be the first thing done
in step 1.

## WHAT THIS DOES NOT COVER

- **Act 2 and Act 3 forces have still never run.** Everything behind them is
  built and tested, and `act` is faked at 1 until Phase 7. Converting eight
  maps does not change that, and Phase 7 is a smaller job than any single map
  on the list above.
- **One pin per MISSION, not per SITE.** A converted map draws two markers on
  one spot. Eight more conversions makes that eight more collisions, so the
  board's one-marker-per-site change should land before the bulk of this.

---

# WHAT VALLEY BASIN COST THAT THESE TABLES DO NOT YET SAY

The per-map tables above cover **placement** — cores, bunker, entries, garrison
posts. Six other things went wrong on the basin, and five of them are still
live traps for every map that follows. They are listed here because the tables
read as if placement were the whole job, and it is not.

## 1. WAKE-DELAYED ATTACKER WAVES NEED `always_active = true`

The basin's defence had two waves on `wake_after_seconds`. Both spawned far out,
were **culled before they ever walked**, and about forty robots stood at the
bunker doing nothing for the whole operation while the garrison died.

> Every spec with a `wake_after_*` trigger needs `always_active = true`. A
> squad ordered to ADVANCE across a kilometre is exactly the one distance
> culling throws away.

Three Rivers is a kilometre across. This will bite hardest there.

## 2. `defence_assault_seconds` HAS TO BE SET PER MAP

A defence ends when the attacker's pool is spent. `SiteHeat._rate()` normally
derives pressure from **hostile cores** — and on a defence the player holds all
of them, so that term is zero and the pool drains at the incursion trickle:
roughly an hour for a typical site.

The basin uses **240 s**. That number is the length of the fight, and a
kilometre-wide map where the attackers need ninety seconds just to arrive
cannot use the same one. **Set it from how long the walk-in takes, not by
copying the basin.**

## 3. DO NOT RE-SAVE AN AUTHORED LEVEL FROM AN INSTANTIATED COPY

Step 2 of the recipe says "add one node to the level `.tscn`". Doing that with
a fit script is how the basin was nearly destroyed: `PackedScene.pack()` on an
instantiated hand-authored level **bakes every prefab instance in** — 8,199
lines to 9,692, every `uid` dropped, every prefab link replaced by a copy of
its contents. It had to be restored from a backup.

> Add the node by hand, or by a text edit of the `.tscn`. Never by packing an
> instantiated scene. This applies to all eight.

## 4. ENTRY MARKERS MUST BE ON NAVIGABLE GROUND

The basin's runs logged `was 31.6 m off the navmesh` for bodies spawned at
entry markers. An entry that is not on the navmesh produces a squad that
either teleports or never moves, and the spawner's safeguards silently turn
themselves off when the nav map cannot answer.

> After choosing entries, deploy a force and read the log for "off the
> navmesh". `tools/probe_map_geography.gd` gives positions, not walkability —
> those are different questions.

## 5. BEACON HEIGHT IS PER MAP

`CoreSignal.BEACON_HEIGHT` is 34 m, chosen to clear Valley Basin's trench walls
and be visible from the pass. The Causeway's cores sit at **y 72 and y 138** up
a tower; Lockside is four stacked benches; Hillfort is a 130 m climb. A column
sized for a shallow bowl will spear through structures or vanish under them.

## 6. ALREADY HANDLED GENERICALLY — do not re-solve these

Worth knowing so nobody re-fixes them per map. All of these were basin bugs and
all now live in `site_slice.gd`, `site_operation.gd` or `holdable_core.gd`:

| | |
| --- | --- |
| Cores starting hostile on a defence | `is_defence` → `start_held()` |
| A defence with no win condition | pool spent + ground held |
| A defence failing on its first frame | `_armed`, set once you hold something |
| Anchors parked out of reach on the core's head | `_anchor_point()`, at the foot |
| The authored objective stealing the terminal back | the takeover watchdog |
| Resistance hardcoded per map | read from the Location |
| The garrison turning up in the order wheel | `Squad.autonomous` |

