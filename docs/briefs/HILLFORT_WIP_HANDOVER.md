# HANDOVER — hillfort_wip, the map, for GAMEPLAY

Written 2026-10-15 by TERRAIN. Owner of what follows: **GAMEPLAY**.
Status: **geometry and markers done and committed. No mission exists yet.**

This is the alternative first mission. It is the same idea as Hillfort at a
quarter of the size, built because the shipped one measured 0.43 km² with two
capture points — 217,440 m² per objective, 3.5x sparser than the next worst map
in the project. The fort was never the problem; the 700 m of road to it was.

Nothing here touches a shipped hillfort file. New files only:

| | |
|---|---|
| `maps/hillfort_wip_level.tscn` | spawn, muster, nav, objectives, captures, cover |
| `maps/hillfort_wip_art.tscn` | terrain + geometry |
| `maps/terrain_data/hillfort_wip_level_terrain.res` | the bake |
| `Env/terrain/sketches/hillfort_wip.png` | the painted source |
| `tools/probe_build_hillfort_wip.gd` | the generator |
| `tools/probe_shots_hillfort_wip.gd` | 31 shots, filtered, 1.50 m eye |

---

## 1. The shape of it

**384 × 384 m**, 0.147 km² — 2.8× Valley Basin, a third of today's Hillfort.
Boundary walls 4 m in, so the playable rectangle is 376 × 376. The rectangle is
**centred at z = +64, not at the origin** — see the approach note below.

The ground is **one broad dome and nothing else**: a cone centred on the fort at
`(0, −66)`, flat on top, falling away at no more than 12° anywhere. It is a
glacis you can walk on from any direction. **Nothing gates by being steep** —
what decides where you go is **walls**, which are things somebody built.

Relief: spawn at y 0, the plateau at y 34. The relay dish on top of that is
62 m tall, which is what makes the fort visible from the trailhead — and it
still is from the new spawn, 302 m out.

Squad spawns at `(0, 1.15, 236)` facing −Z, up the map, on a trailhead pad at
`(0, 236)`. Eight muster stands beside it.

### The approach was lengthened on 2026-10-17 — read this before you re-measure

The map was **384 × 256** and the player met the Pillars garrison **64 m** off
the spawn, about 14 seconds in. The human asked for 20–30 s more before first
contact. The squad moves at 4.5 m/s, so that is 90–135 m — and terrain rounds Z
up to whole 64-cell chunks, 128 m at this 2 m cell, so **there was exactly one
size that satisfied the request.**

**All 128 m of it went south.** The rectangle is centred on the Terrain node, so
growing it alone would have put 64 m of dead ground behind the fort and bought
only half the walk. Instead the Terrain node sits at z = +64 and its five stamp
groups sit at −64, which cancels: **every stamp kept the world coordinate it
already had.** Nothing in the tables below moved except the Trailhead.

Measured after the rebake, bulwark (the widest frame): **191 m to Pillars**, up
from 64 — **28 s at squad pace, 21 s sprinting.** Reach PASS on bulwark, rover
and walker; 96.9–98.1% of the map reachable from the spawn.

**One consequence is GAMEPLAY's to resolve.** `obj_hfw_south_meadow` at
`(−90, 116)` used to be 4 m *behind* the spawn. It is now **155 m in front of
it**, so the squad posted there becomes first contact at roughly 34 s and eats
most of the quiet approach this change was made for. The human chose to leave
the marker where it is and flag it rather than have TERRAIN move it. Re-tag that
squad, or move it, or keep it deliberately as the opening ambush — but it is no
longer doing what it was doing.

### Three lanes

Two wall lines run north–south at **x = ±66**, from the fort's own south-west
and south-east corners down to z = 104. They stop 20 m short of the south edge,
which is the design: **you choose your lane at the trailhead, and once you are
in it, crossing means walking all the way back.**

| lane | length | character | captures |
|---|---|---|---|
| **CENTRE** | 108 m | short and exposed. Straight up a 132 m glacis, under the wall the whole way. | **1** |
| **WEST** | 281 m | long and covered. Screened for all of it, four berms, exposed only on the last 30 m. | **2** |
| **EAST** | — | **blocked.** A cross-wall runs the full 120 m width at z = 40 with one gatehouse in it. The lane does not open until that structure is taken. | **2** |

2 / 1 / 2 and one in the fort, rather than the obvious two per lane. **The count
is part of the difference between the lanes** — the fast way pays for its speed
in what it does not pick up.

---

## 2. The tag table — this is the contract

Missions reference these **by tag, never by node path**. Every one of them is
already in the level scene and framable (`probe_shots_hillfort_wip.gd`).

### Capture points — wired, 6 of them

| node | id | reward | at | lane |
|---|---|---|---|---|
| `CisternCore` | `hfw_cistern` | 20 | −113, 14, 70 | west |
| `ShoulderCore` | `hfw_shoulder` | 25 | −123, 23, −20 | west |
| `PillarsCore` | `hfw_pillars` | 25 | 17, 23, 50 | centre |
| `GatehouseCore` | `hfw_gatehouse` | 25 | 127, 22, 20 | east, **opens the lane** |
| `TerraceCore` | `hfw_terrace` | 25 | 157, 24, −30 | east |
| `RelayCore` | `hfw_relay` | **40** | −10, 34, −26 | the fort. `compute_core_point_large`. |

**The rewards are placeholders.** 20/25/25/25/25/40 is a shape, not a balance
pass. They are yours.

### District anchors — `SquadObjectivePoint`, no logic

| tag | place | x, z |
|---|---|---|
| `obj_hfw_trailhead` | Trailhead | 0, 236 |
| `obj_hfw_pillars` | The Pillars | −17, 50 |
| `obj_hfw_centre_apron` | The South Gate | 0, 4 |
| `obj_hfw_cistern` | The Cistern | −147, 70 |
| `obj_hfw_shoulder` | The Shoulder | −157, −20 |
| `obj_hfw_west_apron` | The West Gate | −92, −54 |
| `obj_hfw_gatehouse` | The Gatehouse | 93, 20 |
| `obj_hfw_terrace` | The Terrace | 123, −30 |
| `obj_hfw_east_apron` | The East Gate | 92, −54 |
| `obj_hfw_yard` | The Yard | 0, −100 |
| `obj_hfw_dish` | The Relay Dish | −52, −60 |
| `obj_hfw_hall` | The Data Hall | 20, −96 |
| `obj_hfw_postern` | The Postern | −24, −108 |
| `obj_hfw_bunker` | The Way Down | 6, −99 |
| `obj_hfw_west_flank` | West Flank | −150, −92 |
| `obj_hfw_east_flank` | East Flank | 152, −96 |
| `obj_hfw_south_meadow` | South Meadow | −90, 116 |

Patrol routes already exist under `HFW_Yard` (6 points) and `HFW_Pillars` (4).

### The bunker

`SiteSlice` raises the entrance kit at the marker; **the level does not instance
it**, because instancing it here as well would build it twice. The values:

```
bunker_marker = &"HFW_Bunker"
bunker_mount  = &"cliff"
bunker_offset = Vector3.ZERO
```

`cliff` rather than `open` is a fit as well as a judgement: `open` is 33.8 m
deep with its sunken court and the yard between the dish's north face and the
curtain is 30.6. `cliff` is 18.3 and leaves 12 m spare, and its revetted
headwall is what a tunnel mouth driven into the back of a rampart looks like.
`wall` needs a ceiling and there is none.

`LevelExit` is at `(6, 34, −103)` — 4 m inside the mouth. §12.7 replaces the
extraction pad with the doors, so the exit is where the doors are.

---

## 3. What is NOT done, and is yours

1. **The mission `.tres`.** None exists.
   `Campaign/missions/mission_polaris_1_siege.tres` is the model for shape.
2. **The location `.tres`** and its `connects_to` / ladder registration.
   `Campaign/locations/loc_hillfort.tres` is the model; this is a different
   location, not a replacement for that one.
3. **Enemy force.** Nothing is placed. Every `EnemySquadSpec` here wants a
   `post_tag` / `spawn_tag` off the table above. The lane design assumes the
   east lane's garrison sits behind the cross-wall and the gatehouse is what
   releases them.
4. **Capture rewards.** See above — placeholders.
5. **`always_active` on anything that walks more than 75 m.** This map has legs
   of 281 m. `always_active` does *not* exempt a spec from culling; an ADVANCE
   beyond 75 m froze on ten specs across five missions before that was found.

---

## 4. One open design question — the bunker's facing

**I have not changed this and it is a gameplay call.**

The bunker is at `(6, 34, −99)` and its doors face **+Z**, which here is south,
down the yard. §12.8 is *"you come up out of the ground and turn round to hold
the ground in front of them."* The intent was right. The problem is that the
58 m relay dish's pedestal is **17 m in front of those doors**, so the shot a
squad actually gets on arrival is the back of the dish filling the frame.
**There is no sightline from the doorway to the gate it is meant to hold** — to
see anything, a squad walks 21 m west or 10 m east around the dish first.

See `hfw_obj_7b_bunker_arrival.png`. Three options, one table row either way:

- **Leave it.** Surfacing under the dish is a strong image and the yard is still
  defensible once you are round it.
- **Turn it 90°.** Keeps the exact position the clearance was measured at, and
  the doors look down 50 m of open yard. Cheapest, and my preference.
- **Move it** to the east or west strip. More work, loses the measured
  clearance.

---

## 5. Rebuilding and proving it

The generator **refuses to overwrite an existing file** without `--force`,
because the file on disk is the source once a human has opened it.

```bash
PROFILE=1 godot --headless --path . --script res://tools/probe_build_hillfort_wip.gd
```

writes nothing and prints the radial profile, every leg's grade, the near lip
from every station, the cut or fill under every bench, and the installation
measured piece against piece. Use it before baking.

**`--force` throws away the baked cover points exactly as it throws away the
navmesh.** The order is build, then terrain, then navmesh, then cover.

```bash
RENDER_OUT=<dir> godot --path . --audio-driver Dummy --script res://tools/probe_shots_hillfort_wip.gd
```

31 shots, 1152×648, through the game's own signal filter at the real 1.50 m
eye. **Not headless** — the filter is a shader that reads the screen, and with
no screen there is nothing to read, so a headless run comes back flat and looks
like proof.

Both `check.sh --changed` and `tools/gate_terrain.sh` pass on it today.

---

# ANSWERED BY GAMEPLAY, 2026-10-15

Everything in §3 is done. The site is registered, playable, and measured.

| | |
|---|---|
| `Campaign/missions/mission_hfw_1_fort.tres` | the attack |
| `Campaign/missions/mission_hfw_2_defend.tres` | the defence |
| `Campaign/locations/loc_hillfort_wip.tres` | **Hillfort Redoubt**, `hillfort_wip` |
| `Env/world_objects/hillfort_wip_slice.gd` | six cores, the bunker, the operation |
| `tools/test_hillfort_wip.gd` | the contract above, asserted |
| `tools/shot_bunker_arrival.gd` | what a squad sees coming up out of the ground |

## §4 — THE BUNKER'S FACING. Left as authored, which is your option 1

**Not the option you recommended, and the reason is a photograph.**

`tools/shot_bunker_arrival.gd` stands the camera in the mouth at the real
1.50 m eye and looks out along the doors, with the leaves driven open through
the slice's own `_on_doors` rather than posed. All four quarters:

| yaw | what is in front of the doors | reach |
|---|---|---|
| **0 — as you built it** | dish pedestal to the RIGHT of frame, yard opening out to the left, curtain and gate structures in view | **clear 60 m** |
| 90 — recommended | square into the Data Hall, 14 m east | blocked 20.8 m |
| 180 | the rampart the tunnel is driven through | blocked 12.0 m |
| 270 | open, but a featureless apron facing away from the fort | clear 60 m |

**The dish does not fill the frame.** With the doors open it stands beside the
opening, not across it — a strong image AND a sightline, which is the pair
§12.8 is asking for. Turning it 90° would have bought a wall.

If `hfw_obj_7b_bunker_arrival.png` shows otherwise, it was probably shot with
the leaves shut or from further back inside the tunnel; the first cut of this
tool did exactly that and photographed the inside of a closed door.

`SiteSlice` gained a `bunker_yaw` export to measure this with. It defaults to 0
and changes nothing on the nine existing sites. **Keep it** — it is how the
next one of these gets settled by looking instead of arguing.

## §3.5 — the patrol routes were markers only

The handover says routes exist under `HFW_Yard` (6) and `HFW_Pillars` (4). The
**markers** exist; nothing wrapped them. There was no `PatrolPath` anywhere in
the level and no node in the `patrol_paths` group, so a `route_tag` would have
resolved to nothing and the squad would have warned "found no anchor" once, at
runtime, and then stood still.

Two `PatrolPath` instances added over the markers you placed, nothing moved:
`patrol_hfw_yard` and `patrol_hfw_pillars`.

## The difficulty is Hillfort's, to the unit

The only reason to build an alternative is to compare it, which fails if the
two cost different amounts. Measured with `tools/measure_resistance.gd`:

| | bodies | reserve | ON MAP | TOTAL |
|---|---|---|---|---|
| `hillfort_1_relay` | 50 | 31 | **48** | **79** |
| `hfw_1_fort` | 48 | 31 | **48** | **79** |
| `hillfort_2_defend` | 14 | 0 | 14 | 14 |
| `hfw_2_defend` | 14 | 0 | **14** | **14** |

(50 against 48 bodies is Hillfort's two supply-0 watchers.)

**Same vocabulary, too** — rifleman, shotgunner, chaser, hopper, and nothing
else. No marksman: a long covered lane wants one badly, and that is precisely
why it does not get one in the first mission the player ever plays. No watcher
either; that is Hillfort's own gimmick and borrowing it would muddy the
comparison. The Gatehouse is hard by COUNT, not by chassis tier.

### The reserves wake on captures, not on a kill count

`Campaign._on_objective_changed` passes the completed objective's id straight
to `wake()`, so **`reinforcement_tag` IS an objective id**. That makes each
wave a counter-attack on the thing you just took, and it delivers §1's "the
gatehouse is what releases them" exactly rather than approximately:

| wave | wakes on | spawns at | pushes to |
|---|---|---|---|
| MEADOW 6 | `hfw_pillars` | south meadow | the Pillars |
| WESTRUN 7 | `hfw_shoulder` | west flank | the Shoulder |
| EASTRUN 7 | **`hfw_gatehouse`** | east flank | the Terrace |
| POSTERN 11 | `hfw_relay` | the postern | the Yard |

A first cut had these as kill-triggered ADVANCE specs, which put all 79 on the
map at once — 65% harder than Hillfort while claiming to match it.
`measure_resistance.gd` caught it.

## The captures are OPTIONAL

All six carry `optional = true`. An attack is won at the BUNKER
(`SiteOperation._on_bunker_changed` is the only thing that starts a stand-down)
and the 2/1/2 lane split means a centre run picks up one of five outer cores.
Compulsory captures would make the fast lane unfinishable, which is the
opposite of the design.

`LevelExit` gained `requires_objectives_complete = true` so the way out does
not open early; `Campaign.open_way_out()` clears it when the operation is won.

## Capture rewards, which were yours to set

They are a bonus paid at extraction ON TOP of the mission reward
(`ObjectiveTracker.earned_objective_rewards`), so the whole take had to move
together. Hillfort pays 325 + one 40 core = **365 max**.

| | was | now | why |
|---|---|---|---|
| mission flat | 325 | **225** | value moved into the choice |
| `hfw_pillars` | 25 | **45** | centre's only core — it has to be worth the exposure |
| `hfw_cistern` | 20 | **30** | |
| `hfw_shoulder` | 25 | **30** | west pays 60 for 281 m of walking |
| `hfw_gatehouse` | 25 | **40** | you fight for it and it opens a lane |
| `hfw_terrace` | 25 | **30** | east pays 70, the most, behind the lock |
| `hfw_relay` | 40 | **55** | the large core, on everyone's route |

What that pays out:

| run | take |
|---|---|
| straight to the bunker, nothing taken | 225 |
| centre (Pillars + Relay) | 325 |
| west (Cistern + Shoulder + Relay) | 340 |
| east (Gatehouse + Terrace + Relay) | 350 |
| everything | 455 |
| *Hillfort, for comparison* | *365* |

A single-lane run pays a little under Hillfort; a full sweep about a quarter
over. The spread BETWEEN lanes is only 25, deliberately — the lane should be a
tactical choice, not an economic one. The real price of the fast lane is
arriving at the fort with the east garrison untouched.

## Where it sits on the board

`requires = [arena_3_firing_line]`, the same gate as Hillfort, and
`connects_to = [valley_basin]` with the reciprocal added to
`loc_valley_basin.tres`. **Both are first sites and the campaign now forks.**
That is the only arrangement that lets the two be played against each other,
which is the point of building it. It does not touch any shipped Hillfort file.

Board tables keyed by mission id, per ONE_PIN_PER_SITE: `LAYOUT` at
`(0, -95)` — directly above Hillfort, so it reads as a fork rather than a
second rank — `ICONS` RELAY, `HEIGHTS` 62.0.

## Proved by

- `tools/test_hillfort_wip.gd` — every spec resolves to a real anchor, every
  reserve waits on a live objective, every core's tier matches its prefab, the
  connects_to is reciprocal both ways, supply equals Hillfort's, and the fast
  lane pays least.
- `tools/spawn_geometry_audit.gd` — **79 bodies, 0 badly placed** on the
  attack; 14, 0 on the defence. Nothing buried, enclosed, floorless or
  standing on an objective.
- `tools/probe_nav_vs_art.gd` — no walkable navmesh inside any slice-built
  solid. **No rebake needed.**
- `tools/measure_resistance.gd` — the table above.

## Not done, and flagged rather than guessed

**Nothing has played it.** Every number here is measured and no number here is
felt. The lane split is 108 m against 281 m, a 2.6x difference in walking time
that no probe can judge — if the west lane is boring rather than tense, that is
a pacing problem and the fix is content on it, not a reward.

Files touched outside GAMEPLAY's lane, listed because the board says to say so:
`maps/hillfort_wip_level.tscn` (slice node, patrol routes, exit gate, optional
flags, rewards), `Env/world_objects/site_slice.gd` (`bunker_yaw`, additive),
`Env/world_objects/hillfort_wip_slice.gd` (new), `Env/world.tscn` (shared —
two missions registered), `Env/world_objects/ops_table.gd` (three board rows).

---

# SWAPPED IN, 2026-10-15 (later)

**It is Hillfort now.** `hillfort_1_relay` is out of the campaign and
`hfw_1_fort` is the opening site. Asked for directly; the fork that the section
above describes lasted about an hour.

## Nothing was deleted

`mission_hillfort_1_relay.tres`, `mission_hillfort_2_defend.tres`,
`loc_hillfort.tres` and `maps/hillfort_level.tscn` are **all still on disk and
all still load**. They are simply not registered: out of `Env/world.tscn`, out
of `location_catalogue.tres`, off the board tables. Swapping back is
re-adding four references, which is why it was done this way round — authored
content does not get deleted without being asked.

## What moved

| file | change |
|---|---|
| `Env/world.tscn` | the two hillfort missions unregistered |
| `Campaign/location_catalogue.tres` | `loc_hillfort` out; nine locations again |
| `Campaign/locations/loc_valley_basin.tres` | edge repointed to `hillfort_wip`; degree back to 5 |
| `Campaign/missions/mission_basin_1_anchor.tres` | `requires` → `hfw_1_fort` |
| `Env/world_objects/ops_table.gd` | `hfw_1_fort` takes Hillfort's `(0, 0)`; the old rows removed |
| `Campaign/callsigns.gd` | `hillfort_wip` → `SITE_HILLFORT` |

**The `requires` repoint was the load-bearing one.** `available_missions()`
gates on `completed_missions.has(req)`, so a mission that is not in
`Campaign.missions` can never be completed — leaving Valley Basin requiring
`hillfort_1_relay` would have locked the entire campaign after the tutorial,
silently, with the board simply never offering a second site.

## Display names

The location and both missions now read **Hillfort** and **Hillfort — Hold**,
because it is the hillfort. The internal ids stay `hillfort_wip`, `hfw_1_fort`
and `hfw_2_defend` — renaming those would touch the save format, the board
tables, the callsign pool and nine suites to buy nothing a player can see.

## The economy did not move

`loc_hillfort` and `loc_hillfort_wip` both pay 8 resources and 1 compute, so
the board totals are unchanged: still 230 resources/turn and 12 compute across
nine places, which is what `tools/test_campaign_spine.gd` asserts §2 requires.

## A regression this introduced, and then fixed

Adding `loc_hillfort_wip` as a TENTH location broke three checks in
`test_campaign_spine.gd` — "the nine places that exist" read 10, the income
totals read 238/13, and Valley Basin's degree read 6. That was live for the
length of one report, which did not mention it because the suite was not run.

The swap removes the tenth location and restores all three. The lesson is in
the lane report: **a new Location is a change to the board's arithmetic**, and
`test_campaign_spine.gd` is the thing that knows it.

## Suites repointed

`&"hillfort_1_relay"` → `&"hfw_1_fort"` and the site id `&"hillfort"` →
`&"hillfort_wip"` in: `test_campaign_spine`, `test_opening`, `test_enemy_turn`,
`test_turn_loop`, `test_callsigns`, `test_ops_board`, `test_ledger`,
`test_vehicle`, `probe_ops_colour`, `shot_ui`, `make_board_campaign`.

`test_hillfort_wip.gd` still loads `mission_hillfort_1_relay.tres` **off disk
by path** to compare supply, deliberately — the retired mission is the
difficulty benchmark and that check should keep working for as long as the file
exists.

## Saves

A `campaign.json` written before the swap holds `hillfort` as a site id and
`hillfort_1_relay` in `completed_missions`. The site id resolves to nothing in
the catalogue, so it pays nothing and cannot be raided; the completed mission
is inert. **An existing run will not crash, but it will have a hole in it** —
start a fresh campaign to play the swapped board.
