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

`ENV=proposal` (filmic tonemap, `background_energy_multiplier` 2.0 → 1.0,
sky ambient, plus the fog): near→far spread collapses from **4.1 steps to 1.1**.
Filmic compresses the highlights, and the highlights are where the entire far
field lives. See `env/salient_S3_no_mans_land_proposal.png` — the far ridges
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

### 2e. A converging ground line does not survive on shelled mud.

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

### P1 — THE TELEGRAPH LADDER. *Do this one first.*

Five lines of `props/prop_power_pole` running **along** the axis of advance, a
pole every 40 m, the lines 88 m apart across the frontage.

```gdscript
+ [["row", "props/prop_power_pole", -390.0, -184.0, 390.0, -184.0, 40.0],
   ["row", "props/prop_power_pole", -390.0,  -96.0, 390.0,  -96.0, 40.0],
   ["row", "props/prop_power_pole", -390.0,   -8.0, 390.0,   -8.0, 40.0],
   ["row", "props/prop_power_pole", -390.0,   80.0, 390.0,   80.0, 40.0],
   ["row", "props/prop_power_pole", -390.0,  168.0, 390.0,  168.0, 40.0]]
```

**Why this and not more landmarks.** Salient's existing dressing is twenty-odd
`row` entries and **every one of them runs at a constant x** — across the
frontage, perpendicular to the advance. That puts every copy of a repeated
object at *the same distance* from an attacker, so the repetition carries no
ranging information whatsoever. Turning the same trick through ninety degrees
turns it into a ruler. This is one inversion, not a new idea.

**Measured, not guessed.** `prop_power_pole` is **9.50 m** tall (`KIT=1`). At
648p / 70 degrees that is 124 px at 40 m, 50 px at 100 m, 25 px at 200 m,
12 px at 400 m — a clean halving ladder that stays resolvable past the far
objectives, and it subtends one degree at 544 m. It is a thin dark vertical
against a luma-0.83 sky, which is the exact signal the filter's edge pass is
built to draw.

**Shot:** `mockup/salient_S3_no_mans_land.png` against
`salient_S3_no_mans_land.png`. In the baseline the only two vertical objects in
the frame are a power pole at ~100 m and the clock tower at 420 m, and they are
the **same apparent size** — you cannot tell them apart. In the mock-up there
is a diminishing row and you can read the ground.

- **Count:** 105 poles, +8.2% on the map's 1285 pieces. Static meshes with a
  ~1 m footprint; run `tools/probe_level_baseline.gd` after and confirm it has
  not moved.
- **88 m spacing, not 90:** it keeps every line off the objective anchors'
  own z values (0, 10, 34, 70, −70, 95, −95, −142, −195) by at least 6 m.
- **Clashes:** poles will land in trench cuts and on the wire and berm rows at
  x = −152, −140, −126, 12, 26, 40, 44. The builder already counts and reports
  guard clashes at placement — check the count it prints. If dress rows are
  **not** guarded, nudge each line's z by up to ±6 m until
  `tools/probe_map_overlap.gd` and `tools/probe_level_faults.gd` come back
  clean. Do not leave an interpenetrating pole: there is no depth small enough.
- **Navmesh:** 105 new obstacles in open ground. Rebake and re-run the reach
  probe before calling it done — this is the map where a 6 cm change closed
  four bridges.

### P2 — TWO MID-GROUND MASSES PER APPROACH

```gdscript
+ [["at", "industrial/industrial_water_tower", -120.0,  86.0,   0.0],
   ["at", "industrial/industrial_water_tower",  150.0, -96.0,   0.0],
   ["at", "trench/op_tower_ruin",               -34.0, -88.0,   0.0],
   ["at", "trench/op_tower_ruin",               124.0,  70.0, 180.0]]
```

Measured heights: `industrial_water_tower` **27.00 m** (one degree at 1547 m),
`op_tower_ruin` **16.22 m** (929 m). Both are already in the map's kit; the
op tower is already used once, at the blown span.

These are the thing the eye locks onto, and they tell you *which sector* you
are looking at — the second missing cue, because the map is built from one
repeated module and nothing says which part of it is in front of you. The
positions put a 27 m mass at **99 m** from the jump-off and a second at
**158 m** from the front line, i.e. inside the dead band, flanking the axis
rather than blocking it.

**Shot:** `mockup/salient_S5_front_line_east.png`. The water tower on the left
and the tower ruin on the right frame the village between them, and the village
now reads as *behind* them instead of as part of the same strip.

Four pieces. This is the cheapest real improvement on the list.

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

**P1, the telegraph ladder.**

It is the only item on the list that supplies a *ruler* rather than a landmark,
and ranging is precisely what the human asked for ("how far things are from
me"). It is five lines in a table that already has twenty like them, using an
asset the map already ships, and it is the one change for which there is a
before-and-after photograph taken through the real filter. P2 is cheaper and I
would take it in the same commit, but four towers tell you *where* you are;
only the ladder tells you *how far*.

And do not touch the fog. It is not the problem, and three of the four things
you would naturally do to the environment measurably make it worse.

---

## 5. Reproducing any of this

```bash
G="/d/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe"
O="D:/Godot Games/roboto_shots/legibility"

TALL=1 "$G" --headless --path . --script res://tools/probe_legibility.gd
KIT=1  "$G" --headless --path . --script res://tools/probe_legibility.gd

RENDER_OUT="$O"          "$G" --audio-driver Dummy --path . --script res://tools/probe_legibility.gd
RENDER_OUT="$O/mockup" MOCKUP=poles ONLY=salient "$G" --audio-driver Dummy --path . --script res://tools/probe_legibility.gd
RENDER_OUT="$O/env"    ENV=fogonly  ONLY=S3      "$G" --audio-driver Dummy --path . --script res://tools/probe_legibility.gd
```

Not `--headless` for anything that renders: the dummy driver returns a blank
image, and a screen-reading shader with no screen reports a perfectly flat
picture of nothing, which looks like proof.
