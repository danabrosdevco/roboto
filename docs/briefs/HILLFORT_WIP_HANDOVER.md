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

**384 × 256 m**, 0.0983 km² — 1.85× Valley Basin, a quarter of today's
Hillfort. Boundary walls 4 m in, so the playable rectangle is 376 × 248.

The ground is **one broad dome and nothing else**: a cone centred on the fort at
`(0, −66)`, flat on top, falling away at no more than 12° anywhere. It is a
glacis you can walk on from any direction. **Nothing gates by being steep** —
what decides where you go is **walls**, which are things somebody built.

Relief: spawn at y 13, the plateau at y 34. The relay dish on top of that is
62 m tall, which is what makes the fort visible from the trailhead.

Squad spawns at `(0, 14.15, 112)` facing −Z, up the map. Muster at
`(−10, 13, 114)`, eight stands.

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
| `obj_hfw_trailhead` | Trailhead | 0, 112 |
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
