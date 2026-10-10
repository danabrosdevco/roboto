# Salient — why you cannot read distance on it

> "it's hard to see at a distance what is coming up in the distance - like you
> see at the same time too much and too little. i'm not sure what the solve is
> there but generrally in other games i feel like i have a better sense of
> terrain / how far things are from me"

Investigated 2026-10-09. Everything below was measured with
`tools/probe_legibility.gd`, which casts a 128x72 grid of rays through a camera
at the game's own FOV and then reads the **same** grid of pixels back out of
the rendered frame, so luma and distance are sampled at the same places. Every
frame is shot through `Character/hud/signal_filter.gdshader` with the uniforms
read out of `Character/hud/hud.tscn`. A render without the filter is not a
picture of this game.

Shots are in `roboto_shots/legibility/` (baseline), `.../mockup` (the
proposal), `.../track` and `.../env` (the two things that do not work).

---

## 1. The finding, in one line

**Nothing on Salient stands up between 25 m and 200 m**, and on flat ground
with the eye at 1.65 m that is the only way a frame can carry any information
about range at all.

| view | 25-200 m, share of frame | **above-eye hits at 25-200 m** | near→far luma spread | sightline, median |
|---|---|---|---|---|
| salient S1 jump-off, east | 1.7% | **0.37%** | 4.3 steps | 524 m |
| salient S2 over the parapet | 8.7% | **0.04%** | 4.2 | 524 m |
| salient S3 no-man's-land | 8.6% | **0.13%** | 4.1 | 539 m |
| salient S4 the crater lip | 3.9% | **0.13%** | 4.0 | 574 m |
| salient S5 front line, east | 4.0% | **0.24%** | 4.6 | 468 m |
| salient S6 down the trench | 0.7% | **0.71%** | 5.0 | 368 m |
| salient S7 the long axis | 0.3% | **0.09%** | 4.2 | 4 m (blocked) |
| hillfort H1 the trailhead | 15.5% | **5.79%** | 1.0 | 751 m |
| georgetown G1 the towpath | 6.1% | **2.55%** | 1.8 | 72 m |
| georgetown G2 the stack | 8.5% | **4.32%** | 1.6 | 46 m |

Salient has **ten to fifty times less** standing at ranging distance than the
two maps in this project that read well. That is the whole complaint, as a
number.

### Why that column is the one that matters

Ground running away from a 1.65 m eye has a depression angle of
`atan(1.65 / d)`. At 25 m that is 3.78 degrees; at 200 m, 0.47; at 400 m, 0.24.
The game renders 70 degrees over 648 px, so:

- the entire **25 m → 200 m** range of ground occupies **31 pixels** of frame
  height — under 5% of it,
- the entire **200 m → 400 m** range occupies a further **2 pixels**.

So on flat ground, *every* distance from 25 m to the horizon arrives in the
same thin strip under the horizon line, at the same apparent size, in the same
luma step. Half the screen is the 25 m of mud at your feet (40-78% of the
frame, carrying no information at all) and everything you actually need to read
is in a band 31 px tall. **That is "too much and too little at the same time",
literally.** Look at `salient_S5_front_line_east.png`: the bottom 55% is a
carpet of identical trench modules, the top 40% is empty sky, and the support
line at 130 m, the gun line at 270 m, the village at 370 m and the valley wall
at 600 m are all inside one 60-pixel strip.

The only exception on the map is the valley walls themselves — they are the
10-18% of frame sitting in the 200-400 m band. They are above the eye, so they
*do* get screen area, but they run **parallel** to the advance on both flanks,
so they tell you nothing about how far forward anything is.

### The map's own inventory agrees

`TALL=1` over the three levels:

| | placed pieces | 8 m or taller |
|---|---|---|
| salient | 1285 | **5.7%** |
| hillfort | 98 | 15.3% |
| georgetown | 258 | 21.7% |

And every one of Salient's tall pieces is at the **east end** (x >= 395: the
village, the clock tower at 52 m, two water towers) or **off the map edge**
(x = -510). The 600 m of ground between the jump-off and the support line —
which is the whole game — has nothing in it over about 7 m, and those are
burnt tree snags at z = ±232, on the map's north and south borders.

---

## 2. Four things that do not work — measured, not guessed

The brief that commissioned this expected the answer to be about fog. It is
not, and three of the four obvious environment moves make the picture **worse**.

### 2a. More fog does nothing. The quantiser eats it.

`ENV=fogonly`, `fog_density` 0.0008 → 0.0022 (2.75x the haze, 38% veil at
200 m instead of 15%):

| band | authored | +175% fog |
|---|---|---|
| 0-25 m | 0.239 / step 2 | 0.257 / step 2 |
| 50-100 m | 0.364 / step 3 | 0.410 / step 4 |
| 400-800 m | 0.699 / step 6 | 0.712 / step 6 |
| **near→far spread** | **0.460 (4.1 steps)** | **0.455 (4.1 steps)** |

Nearly tripling the haze changed the near-to-far separation by **−0.005**, and
moved exactly one band across one of the ten luma steps. The shader's own
comments were right.

### 2b. Salient already has MORE atmospheric separation than the maps that read well.

Salient: **4.0 to 5.0** of the filter's ten luma steps between the near band
and the far one. Hillfort: **1.0**. Georgetown: **1.6-1.8**. Hillfort's hill is
within 0.03 luma of its own sky and reads perfectly, because it reads by
**silhouette** — the filter's edge pass puts a hard outline on any luma
discontinuity over 0.06, and that is the depth cue that actually survives in
this renderer. A haze gradient produces no discontinuity and therefore no edge.
A vertical object against the sky produces one every time.

### 2c. Filmic tonemapping destroys three of the four steps that exist.

`ENV=filmic` (filmic tonemap, `background_energy_multiplier` 2.0 → 1.0,
sky ambient, plus the fog): near→far spread collapses from **4.1 steps to 1.1**.
Filmic compresses the highlights, and the highlights are where the entire far
field lives. See `env/salient_S3_no_mans_land_filmic.png` — the far ridges
come out *paler than the near ground* and the frame is one flat wash. **Do not
copy Hillfort's and Georgetown's `tonemap_mode = 2` onto this map.**

### 2d. The height fog layer is dead, and waking it up makes things worse.

The brief's claim is correct: `fog_height = -40.0` sits 40 m below a surface
that runs from −2.5 to +42, so the layer contributes nothing. But `ENV=heightfog`
(layer moved to +4 m, density 0.05, nothing else touched) raises the **near**
field from 0.239 to 0.372 and leaves the far field untouched at 0.699 — spread
4.1 steps → **3.3**. Height fog applies most where *you* are, not where you are
looking. Leave `fog_height` where it is, or set `fog_height_density = 0.0` and
delete the dead knob.

### 2e. Spreading landmarks evenly is worse than clustering them near the player.

This one overturned the first draft of this document. `MOCKUP=marks` is four
pieces placed deliberately close to the cameras; `MOCKUP=lattice` is sixteen on
a 110 m stagger covering the whole contested ground. Mean "standing at range"
across the seven Salient views:

| | pieces | mean standing at 25-200 m |
|---|---|---|
| authored | — | 0.24% |
| `MOCKUP=poles` (63 poles) | 63 | 0.32% |
| `MOCKUP=lattice` (even grid) | 16 | 0.34% |
| **`MOCKUP=marks` (four, placed close)** | **4** | **0.44%** |

**Four well-placed pieces beat sixteen evenly-spread ones and sixty-three
poles.** Screen area at range is dominated by *proximity*, not by count: a 27 m
tower subtends 15 degrees at 100 m and 5 degrees at 300 m, so a landmark two
hundred metres off the line of advance is costing a piece and buying almost
nothing. The rule that falls out of this is in P1 below, and it is not the rule
I would have written before measuring.

### 2f. A converging ground line does not survive on shelled mud.

Georgetown's towpath reads largely on linear perspective: a hard-edged brick
path running to the vanishing point, warm against cool grey. Salient already
owns that asset — `ground/ground_track` is dressed into the map in four rows
along the advance axis, at x −520..−190 and x 210..500. **They stop exactly
where the player is looking**, so extending them across no-man's-land looked
like a free win. `MOCKUP=track` (307 pieces, three runs joining the two halves)
is **invisible**: see `track/salient_S3_no_mans_land.png` against the baseline.
A dirt track on dirt has no value contrast, and at eye height it is inside the
31-pixel strip anyway. Georgetown's towpath works because it is luma 0.4
against 0.2 with a coping edge on it, not because it is a line.

---

## 3. The proposal

Ranked by effect per unit of work. All of it goes in the `the_salient` entry in
`tools/mapdeck_data.gd`, in the existing `dress` list, in the existing
`["row", piece, x1, z1, x2, z2, spacing]` / `["at", piece, x, z, yaw]` forms.
Nothing here needs a new asset or a new generator feature.

### P1 — MID-GROUND MASSES, HUNG ON THE LINES OF ADVANCE. *Do this one first.*

**The rule, which is the part that matters:** every landmark goes **50 to
150 m off a line the squad actually walks** — the three crossing routes and the
objective anchors — and no two consecutive ones are the same piece. A landmark
200 m off the advance costs a piece and buys almost nothing (section 2e).
Do not lay them on an even grid. Hang them on the routes.

The routes are not typed anywhere and must not be: `build_salient.gd` already
writes `Trenchworks/Anchors` markers for every feature of all three crossings,
and `_landmarks()` already places the ditched tank and the op tower ruin off
`_marks["A.blown"]` precisely so they follow the road if it moves. New
landmarks go in the same function, off the same marks.

A starting set, measured and photographed:

```gdscript
+ [["at", "industrial/industrial_water_tower", -120.0,  86.0,   0.0],
   ["at", "industrial/industrial_water_tower",  150.0, -96.0,   0.0],
   ["at", "trench/op_tower_ruin",               -34.0, -88.0,   0.0],
   ["at", "trench/op_tower_ruin",               124.0,  70.0, 180.0]]
```

Measured heights (`KIT=1`): `industrial_water_tower` **27.00 m**, one degree at
1547 m; `op_tower_ruin` **16.22 m**, 929 m. Also available and already in the
kit: `feature_watchtower` 8.72 m, `fort_floodlight_mast` 9.91 m,
`estate_frame_shell` 22.9 m. All are built assets standing on flat ground, so
**playable ground must be flat** and **gate with walls, not cliffs** are both
satisfied — none of this is terrain.

These four pieces take the front-line view from **0.24% to 1.20%** standing at
range, a five-fold improvement for four pieces, and they are the strongest
effect per unit of work anything in this investigation produced.

**Shots:** `marks/salient_S5_front_line_east.png` — the water tower on the left
and the tower ruin on the right frame the village between them, and the village
now reads as *behind* them instead of as part of the same horizon strip.
`lattice/salient_S3_no_mans_land.png` shows the same thing from no-man's-land:
one big near mass with a clear silhouette and a smaller one behind it, which is
two planes where the baseline had one.

Expect to need **ten to fourteen** of them before the map matches Georgetown,
not four — four fixed one view and left six of the seven where they were. Add
them in pairs tied to route marks and re-shoot, rather than committing a grid.

- **Navmesh:** these are solid obstacles in open ground. Rebake and re-run the
  reach probe. This is the map where a 6 cm change closed four bridges.
- **Overlap:** `tools/probe_map_overlap.gd` and `tools/probe_level_faults.gd`
  must stay clean. A water tower dropped on a wire row interpenetrates, and
  there is no depth small enough to be safe.

### P2 — FINISH THE TELEGRAPH LADDER THAT IS ALREADY HALF BUILT

This map **already has the right idea in it.** Two rows of
`props/prop_power_pole` run the entire length of it, along the advance axis:

```gdscript
["row", "props/prop_power_pole", -520.0, 160.0, 500.0, 160.0, 46.0],
["row", "props/prop_power_pole", -520.0, -160.0, 500.0, -160.0, 52.0],
```

They are at z = ±160, which is **160 m off the axis everybody advances along**.
From the jump-off the nearest pole is 161 m away at 83 degrees off the look
direction — out at the rim of a 101-degree frame, where a receding line cannot
be read as a receding line. The asset, the idiom and the spacing are all here;
only the placement puts them where nobody is looking. Fill the 320 m gap:

```gdscript
+ [["row", "props/prop_power_pole", -400.0, -88.0, 400.0, -88.0, 40.0],
   ["row", "props/prop_power_pole", -400.0,  -8.0, 400.0,  -8.0, 40.0],
   ["row", "props/prop_power_pole", -400.0,  84.0, 400.0,  84.0, 40.0]]
```

**And re-space the two existing lines from 46 m and 52 m to 40 m.** A ruler
whose lines disagree about how long a step is is not a ruler. 40 m on all five.

`prop_power_pole` is **9.50 m**. At 648p / 70 degrees that is 124 px at 40 m,
50 px at 100 m, 25 px at 200 m, 12 px at 400 m — a clean halving ladder that
stays resolvable past the far objectives (one degree at 544 m), drawn as a thin
dark vertical against a luma-0.83 sky, which is exactly the discontinuity the
filter's edge pass exists to outline.

This is ranked **below** P1 because the measurement says so: 63 poles moved the
mean from 0.24% to 0.32%, where four towers moved it to 0.44%. But the metric
measures *area*, and a ruler works by count and spacing rather than by area, so
treat that ranking as "do both, towers first" and not as an argument against
the poles. The complaint has two halves — "what is coming up" and "how far
things are from me" — and the poles are the half that answers the second.

- **63 poles**, +4.9% on the map's 1285 pieces. Static meshes, ~1 m footprint;
  re-run `tools/probe_level_baseline.gd` and confirm frame cost has not moved.
- **z −88, −8, +84 rather than round numbers:** every objective anchor sits at
  z 0, 10, 34, ±70, ±95, −142 or −195, and this clears all of them by 8 m or
  more.
- **Clashes:** poles will land on the wire, berm and dragon-teeth rows at
  x = −152, −140, −126, 12, 26, 40, 44 and in the trench cuts. The builder
  prints a guard clash count at placement — read it. If dress rows turn out
  not to be guarded, nudge each line's z by up to ±6 m until the overlap and
  fault probes come back clean.

### P3 — MORE WATER IN NO-MAN'S-LAND

In the `paint` list, the three `"B"` ovals are flooded shell holes at world
(−112, −80), (−32, 64) and (24, −112). **The one at (−32, 64) is the single
most legible mid-range object on the whole map** and it is an accident: it is
the only reason S3's 50-100 m band (mean luma 0.364) is *brighter* than its
0-25 m band (0.239). Every other Salient view has the mid band darker than the
near one, which is backwards for atmospheric perspective and is why distance
reads as "closer and flatter" than it is.

Water is a flat specular plate: it takes the sky's luma (0.83) and sits it on
the ground at a known place, which is a hard edge, a high-contrast mark and a
landmark at once — and it survives a ten-step quantiser better than anything
else on the map does.

Add four more across the contested ground, keeping the existing 2 m depth so
they stay a reason to go round and not a swim:

```gdscript
["oval", 47, 38, 4, 3, "B"], ["oval", 56, 16, 3, 3, "B"],
["oval", 64, 46, 4, 3, "B"], ["oval", 71, 30, 3, 3, "B"],
```

(= world (−136, 48), (−64, −128), (0, 112), (56, −16).) Four entries in a list.
Check they do not land on a trench route or an objective anchor and re-run the
bake; `water_bank = 6.0` means each one eats a ~6 m skirt of walkable ground.

### P4 — HUE, THE CHANNEL THAT IS NOT BEING USED

Lower priority, larger job, noted so it is not forgotten. The filter quantises
chroma *separately* from luma, at 5 levels, at saturation 0.90 and
`palette_strength` 0.60 — hue survives the posterise far better than value
does. Salient spends none of it: `ground_tint (0.28, 0.255, 0.225)` at
`saturation 0.72` is one near-neutral brown over a kilometre of map.

Hillfort's trailhead reads partly because its foreground crates are saturated
orange and blue against a desaturated grey-green distance. Georgetown's towpath
reads because warm brick sits against cool grey stone. The equivalent here is
to warm the **friendly** works (revetment, duckboard, sandbag, the kit west of
x = −140) and cool the **enemy** side, so which half of the field you are
looking at is a hue and not a guess. That is a texture pass, not a dress line.

---

## 4. If only one change were allowed

**P1 — ten to fourteen tall built masses, hung 50 to 150 m off the lines of
advance.**

It is the largest measured effect per unit of work by a factor of about
fifteen: four pieces took one view from 0.24% to 1.20% standing at range, where
sixty-three poles moved the seven-view mean from 0.24% to 0.32%. It needs no
new asset, no generator change and no terrain work — the kit already holds a
27 m water tower and a 16 m tower ruin, and `build_salient.gd` already has the
function that hangs landmarks off route marks. And it is the only change that
puts *mass* into the 31-pixel strip where all of 25 m to the horizon is
currently drawn, which is the geometric cause of the whole complaint.

The honest caveat is that four is not enough — it fixed one view of seven. Add
them in pairs off route marks and re-shoot with
`MOCKUP=marks tools/probe_legibility.gd` until every forward view has two
masses in it.

And **do not touch the fog.** It is not the problem, Salient already has more
near-to-far value separation than either map that reads well, and three of the
four things you would naturally reach for in the environment resource
measurably make the picture worse.

---

## 5. Reproducing any of this

```bash
G="/d/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe"
O="D:/Godot Games/roboto_shots/legibility"

TALL=1 "$G" --headless --path . --script res://tools/probe_legibility.gd
KIT=1  "$G" --headless --path . --script res://tools/probe_legibility.gd

RENDER_OUT="$O"        "$G" --audio-driver Dummy --path . --script res://tools/probe_legibility.gd
RENDER_OUT="$O/marks"  MOCKUP=marks ONLY=salient "$G" --audio-driver Dummy --path . --script res://tools/probe_legibility.gd
RENDER_OUT="$O/env"    ENV=fogonly  ONLY=S3      "$G" --audio-driver Dummy --path . --script res://tools/probe_legibility.gd
```

`MOCKUP` takes `poles`, `marks`, `lattice`, `track` or `both`; `ENV` takes
`fogonly`, `heightfog` or `filmic` (all three rejected — see section 2). Everything either flag does is applied to
the loaded scene **in memory** and nothing is written back, so none of it can
collide with whoever is editing the level.

Not `--headless` for anything that renders: the dummy driver returns a blank
image, and a screen-reading shader with no screen reports a perfectly flat
picture of nothing, which looks like proof.
