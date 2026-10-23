# Shot brief — the five itch.io screenshots

Written 2026-10-01 by MARKETING. **Draft dispatch: the human sends this, not me.**

**For:** GAMEPLAY, or whoever can run the game and park a camera. TERRAIN could
take shots 1 and 4, which are landscape-led.

**Not for the 1 October recording.** Those clips are the human's own. This is the
separate set of stills an itch.io page needs, and nothing here is urgent before
the playtest build ships.

---

## What this is for, in one line

Five screenshots that make a stranger understand what the game is before they
read a word. They go on the itch page gallery and later on Steam, where five
gameplay screenshots is a hard minimum.

**One shot per level, deliberately.** Five shots from five places read as a big
game; five from one map read as a demo. Variety comes from the *places*, never
from the lighting — **pick one time of day and hold it across all five.**

---

## Before any of it: two things to settle

### 1. The capture tool

`tools/mockup_shots.gd` already does the hard part — loads a real level for its
lighting, stages subjects, parks a camera, writes the viewport to PNG, headless:

```bash
godot --audio-driver Dummy --path . --script res://tools/mockup_shots.gd -- <out dir>
```

It is hard-wired to the depot and to kit mock-ups (`LEVEL`, `STAGE`, `SOLDIER`
constants at the top). **Please generalise that rather than writing a second
tool** — most of the work is done and a second one will drift from the first.

What marketing needs it to take: level, camera position, camera target,
resolution, HUD on/off, and which squad to place. Five parameters and the
existing body.

**The HUD toggle matters more than it sounds.** A store page wants clean frames
and a devlog wants the green phosphor. Re-staging a shot to get both is what
makes capture expensive, and it is the difference between this being an
afternoon and a week.

If generalising it is not worth the time right now, taking these by hand in the
editor is fine. The shot list works either way.

### 2. Which Mutaha?

`mutaha_level` is in the live campaign; `mutaha_wip_level` is the rework and the
board says it gets promoted "when you say it is finished, not before". **Shoot
whichever is current when you take these** — the landmark names below are from
the WIP, and they should carry over. Worth confirming before you set up.

---

## The five shots

Landmark names below are real node names in each level, so you can select them in
the editor and put the camera from there.

### Shot 1 — the squad, in the open · `coastal-road_level`

> Camera at squad height, **8–12 m behind a squad of four**, looking along the
> road. Stage it between **`Coast_Hill`** and **`Coast_Bridge`** so the road runs
> away from camera and the bridge is in the far third. Four frames legible and
> **separated** — not clumped, not overlapping. Mixed frames if you can: two
> soldiers, a Rover, a Spotter at altitude.
>
> **No HUD**, plus a second pass **with HUD**.

**Why it is shot 1:** it is the cover image and the one that has to say "these are
capsules, and there are four of them" in a single glance. Open coastal ground
gives the cleanest separation of anything in the repo. Nothing else in the set
does this job.

### Shot 2 — an order being given · `mutaha_level` / `mutaha_wip_level`

> **First person, HUD on.** The order text legible in green phosphor, and the
> squad **visibly moving to it in the same frame** — mid-stride, not standing.
> Stage around **`Mutaha_CrossWest`** or **`Mutaha_CorePlaza`**, where the town
> geometry makes the movement read as a decision rather than a walk.
>
> If you can get **`Mutaha_Compute`** in shot, do — an objective marker that says
> COMPUTE over a dead town is the whole game in one frame.

**Why:** the only shot that shows commanding. If one image has to prove this is
not a normal shooter, it is this one.

### Shot 3 — the Mechanic standing a robot back up · `valley_basin_level`

> **Side-on, both robots in frame**, close enough that the welder reads clearly.
> HUD on. Open ground near **`Basin_Anchor`** or between **`Basin_GarrisonW`**
> and **`Basin_TrenchS`** — somewhere uncluttered, because the two figures *are*
> the composition.
>
> **Also grab 6–8 seconds of video of this**, same framing. It becomes the itch
> gallery GIF, which is the single biggest conversion lever on that platform.

**Why:** the most legible good thing in the build and the one mechanic nobody
else has. It is the shot that makes a stranger feel something about a capsule.

**Read the blocker note below before staging this one.**

### Shot 4 — flanking the Walker · `pittsburgh_level`

> Wide enough that **the Walker's turret facing and the flanking frame are both
> visible at once** — the entire point is that its guns are pointing the wrong
> way. Shoot across the bridges: **`Pitt_Bridgehead`**, **`HiveBridge`** or
> **`Pitt_Point`** at the confluence. Bridge geometry makes the flank read as
> geometry rather than as two robots standing near each other.

**Why:** the counter-play shot. It proves the frames are objects with weaknesses
rather than tiers of the same thing.

### Shot 5 — the squad manager · `depot_level`

> **Full-screen UI, no world behind it.** FACTORY or ARMORER tab, showing a
> **real roster with ranks on it** — not a fresh-start squad. Veterans and a
> Captain if you can get them, and a frame with kit actually fitted.
>
> Taken at the depot, near **`ChassisBays`** / **`DummyTerminal`**.

**Why:** the persistence shot. Tactics buyers look for this image specifically,
and its absence reads as "no meta layer". Recruitment is confirmed live, so the
FACTORY tab is legal to show.

---

## Technical spec

| | |
|---|---|
| Resolution | **2560×1440**, or 1920×1080 if that is a problem. Consistent across all five |
| Format | PNG, no compression artefacts, no scaling after the fact |
| HUD | Every shot in **two passes, HUD on and HUD off**, except shot 5 which is UI |
| Time of day | **One, held across all five.** As authored, unless one level looks obviously wrong |
| Naming | `01_coast_squad_hud.png`, `01_coast_squad_nohud.png`, and so on |
| Where | Anywhere outside the repo is fine; tell marketing the path |

**Do not** add overlays, text, borders, logos or colour grading. Steam rejects
screenshots with marketing text baked in, and the game's own look does not need
help.

---

## Do not shoot — these are not public

From `docs/marketing/CLAIMS.md`. Everything here is real and running, and none of
it is reachable by a player, which makes it the most dangerous thing to put in
front of someone:

- **Marksman weapon** and **Mortar** — both tagged DARK in GDD §4.
- **Quadcopter Bomber as an ally**, **Lobber Rover**, **Mortar Track** — exist,
  none purchasable. Board NEXT #4.
- **The Laboratory** — a test harness, not gameplay.
- **Possession** — not instantiated in any scene.
- Anything on `causeway_level` — the map exists, no mission does.

---

## Two blockers that would quietly ruin a shot

### The Mechanic's welder may be the wrong size — affects shot 3

The board's record blocker says the infantry `WeaponMount` baked a 0.25 scale and
**all the infantry mounts want the same new value** or the squad's guns and the
enemy's disagree. Current state on disk:

| Scene | `WeaponMount` scale |
|---|---|
| `soldier_chassis.tscn` | **0.4** |
| `mechanic_chassis.tscn` | **0.25** |

So the soldier mount has been bumped and the Mechanic's has not. **Shot 3 puts a
Mechanic and a downed soldier in the same frame**, which is exactly where a
mismatch shows.

It may be deliberate — the Mechanic's mount holds a welder, not a rifle, and a
welder is not a gun. **Please check it in-editor before staging shot 3.** If it
is a miss, it is a one-value fix; if it is intended, say so and marketing will
stop flagging it.

### The exe has the wrong icon — not a screenshot problem, but adjacent

`editor_settings-4.3.tres` has `export/windows/rcedit = ""`, so Godot cannot
rewrite the exe's resources. Every build carries the **Godot Engine icon** and
`Godot Engine` in its file properties. Full detail in
`docs/marketing/ITCH_SETUP.md` §11. Worth fixing before the build goes anywhere,
since it is the first thing a playtester sees.

---

## What marketing does with them

Shot 1 becomes the itch cover (recropped to **630×500** — it must read at
315×250, so expect to recompose rather than scale). Shot 3 becomes the gallery
GIF. All five go in the gallery, and later carry over to the Steam page, where
five gameplay screenshots is the minimum Valve accepts.

Copy to go around them is in `docs/marketing/PITCH.md`. Page structure is in
`docs/marketing/ITCH_SETUP.md` §7.

---

## Revision 2 — 2026-10-01, after seeing the first set

The first set came back in `D:\Godot Games\roboto_shots`. All five shots, both
HUD passes, correctly named — the brief was followed. **The brief was the
problem.** Below is what went wrong and what to change. Most of it is mine.

### The one objective failure: resolution

Every file is **1152×648**. The brief asked for 2560×1440 and that did not
happen, which suggests the capture is writing the window viewport rather than
rendering at a set size.

This is not a taste question. **Steam requires screenshots at 1920×1080 minimum**,
so as taken these cannot go on a Steam page at all, and they are soft on itch.

**Fix:** the capture needs to render to a fixed-size `SubViewport` rather than
grab the window. If that is hard, running the game windowed at 1920×1080 and
grabbing that is an acceptable fallback. **Nothing else in this list matters if
the resolution does not change.**

### What my brief failed to say

Four things I assumed and should have written down:

1. **Time of day.** I wrote "as authored", and what came back is bright midday
   with a clear blue sky. On a game whose whole register is a dead planet, a
   cheerful sky is the single most off-tone thing a screenshot can do.
   **Shoot dusk or overcast.** If the level is authored bright, say so and
   marketing will raise it as a lighting question rather than a shot one.
2. **The subject must be unoccluded and large.** In `01_coast_squad`, a wall
   fills the left 60% of frame and the squad is specks on the horizon. In
   `03_basin_mechanic`, the capsules are behind a parapet so only their domes
   show. **Rule: the subject occupies at least a third of the frame width, with
   nothing between it and the camera.**
3. **The action has to be happening.** `03` shows two robots standing. The shot
   is a Mechanic *mid-revive* — welder out, downed frame on the ground, contact
   between them. A still of the moment, not of the place where the moment
   occurs.
4. **The frames must read as capsules.** That is the game's one unmistakable
   visual and no shot in the set delivers it. Camera at or slightly below
   capsule height, clear sky or flat wall behind, nothing cutting them off.

### What is already good — use it

**The `environments/` set is far better than the gameplay set** and whoever shot
it understood the tone exactly. Dark, cold, empty, properly composed.

- **`mutaha_wip_14_quarter_street.png` is the best image in the project.**
  Gutted blocks, cobbled street, clock tower in the distance, dusk. **It is now
  the itch cover** (`docs/marketing/brand/itch_cover_630x500.png`).
- The other Mutaha, hillfort and salient frames are usable gallery filler.
- **`pittsburgh_03_the_whole_valley.png` is not usable** — it is a high-altitude
  top-down that reads as a map or a debug view, and the terrain's edge and the
  void beyond it are visible along the top.

**So the lighting and composition problems are solvable — the same person
already solved them once.** The environments set is what the gameplay set should
look like, with robots in it.

### Reshoot list — the five, with the corrections applied

Same five subjects and landmarks as above. Changed for the reshoot:

| | |
|---|---|
| Resolution | **1920×1080 minimum**, 2560×1440 preferred. Non-negotiable |
| Light | **Dusk or overcast.** Match `environments/mutaha_wip_14_quarter_street` |
| Subject size | **At least a third of frame width**, nothing occluding it |
| Camera height | At or just below capsule height, so they read as capsules |
| Action | Staged and mid-motion — the revive in contact, the squad walking, the Walker's turret visibly off-target |
| Still needed | **6–8 s of video** of the revive, same framing, for the gallery GIF |

If only one gets reshot, make it **shot 3, the Mechanic revive.** It is the
gallery GIF, it is the best clip in the game, and it is the one the current set
misses most completely.
