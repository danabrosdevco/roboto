# Brief — BACKLOT, a marketing asset generator

**Draft dispatch. The human sends this; MARKETING cannot.**

**For:** GAMEPLAY. `Managers/**` and `Character/**` are both yours, and this sits
on top of the Laboratory without changing it.

**Written** 2026-10-13, **revised** the same day after the human reframed it. It
supersedes `BRIEF_FIGHT_CAPTURE.md`, which asked only for fight recording and was
too small an idea. Every symbol named here was checked to exist.

---

## 1. What it is, in one line

**Marketing writes a shot spec. BACKLOT stages it, films it, and leaves the
frames in a folder.**

The point is to make the request side cheap. Marketing should be able to say
*"Walker firing at a Rover, three-quarter view"* or *"EMP goes off among three
soldiers, low angle"* and get it, without a conversation about camera
coordinates, without anyone playing, and repeatably — so the same shot can be
re-taken when the art changes.

---

## 2. The name, and why it is not the Laboratory

**Call it BACKLOT.** A backlot is where things are staged to be filmed. It is
industrial rather than glamorous, it is unambiguous about purpose, and
`grep -r backlot` over the repo returns nothing, so the name is free.

**It must not be a mode of the Laboratory, and the distinction is not
cosmetic:**

| | Laboratory | BACKLOT |
|---|---|---|
| Question it answers | *Which side wins, and by how much?* | *What does this look like?* |
| Output | `lab_report.md`, win rates, accuracy | PNG sequences, an event index |
| Wants | statistical validity, `repeats`, no interference | one good-looking take, staged, interfered with constantly |
| Success | the numbers are trustworthy | the picture is usable |

A marketing run forces outcomes, freezes units, parks cameras and stages things
that would never happen — **all of which would poison lab data if the two shared
a mode.** Keep them separate at the entry point, share everything underneath.

---

## 3. What it reuses — please do not rebuild any of this

Verified in source. The Laboratory is most of the way to being a camera rig
already:

| Already there | Where |
|---|---|
| Spawn a side from a roster, with faction, callsigns, weapon swaps | `lab.gd:244 _spawn_side()`, `_issued_weapon()` |
| Issue a side an order | `lab.gd:325 _order()` |
| Place two groups a set distance apart on an axis | `_starts()`, `_find_axis()` |
| **A camera framed side-on and above the line between the starts** | **`_frame_camera()` — keep this as the `side_on` preset** |
| **Robots stay awake regardless of camera distance** — `AWAKE_FOR = 1.0e6` | `lab.gd` consts. Exactly the bug a naive capture tool hits first |
| Spectator that cannot be killed | `_become_ghost()` |
| Stage the scene anywhere on the map | `plan.site`, `plan.site_heading` |
| CSG pre-baked so forty robots do not cost a 336 ms frame | `CsgBake.make()` |
| Arena | `proving_level` |

**`AIEquipment` is directly drivable** — `can_use(context)` and
`execute(context)` on `Character/characters/ai/equipment/ai_equipment.gd`. This
is the finding that makes equipment shots cheap rather than expensive: BACKLOT
can simply call `execute()` and film the result. Scenes present: `ai_grenade`,
`ai_grenade_projectile`, `ai_mortar_round`, `ai_repair_kit`, plus
`ai_smoke.gd`, `ai_mine.gd`, `ai_deploy.gd`. `item_emp.tres` exists.

---

## 4. The shot spec — the deliverable marketing actually wants

A resource (`BacklotShot`), authored as `.tres`, so marketing can write them and
hand them over. Roughly:

```
name            "walker_fires_at_rover_34"

# WHO
subject         ChassisDefinition        # the one the shot is about
subject_kit     [ItemDefinition]         # weapons, modules fitted
target          ChassisDefinition        # optional, the thing acted upon
extras          [ChassisDefinition]      # optional, dressing
faction_subject / faction_target

# WHERE
level           "res://maps/mutaha_wip_level.tscn"
site_tag        &"obj_mutaha_compute"    # a tagged point — see §5
site            Vector3                  # raw fallback when no tag fits
heading         float
separation      float                    # subject to target, metres

# HOW IT IS CAPTURED
capture         OBS | FRAMES             # see §6

# WHAT
action          Action                   # see §8
action_arg      StringName               # e.g. which equipment

# HOW IT IS SEEN
camera          CameraPreset             # see §7
cam_distance    float
cam_height      float
fov             float
frames          int                      # 1 = still; 90 = three seconds at 30fps

# OUTPUT
size            Vector2i = (1920, 1080)
hud             bool = false
```

**Everything except `name`, `subject` and `camera` should have a sane default.**
A spec that is three lines long must produce something usable, or marketing will
not write them.

---

## 5. Maps and sites — address a place by name, not by coordinate

**Marketing picks the map, and picks where on it.** `proving_level` is the right
default for tier 1–2 poses, but most of what makes this game look like itself is
the places: a dusk street in Mutaha reads as the game in a way an arena never
will.

**The addressing already exists and costs nothing to implement.** Every level is
dressed with `SquadObjectivePoint` instances in the **`squad_objective_points`**
group, each carrying a `tag` and a human-readable `objective_name`. Counted
across the live maps:

| Level | Tagged points |
|---|---|
| `mutaha_wip_level` | **49** |
| `valley_basin_level` | 19 |
| `pittsburgh_level` | 18 |
| `coastal-road_level` | 16 |
| `proving_level` | 1 |

**102 named locations**, already authored, with names like *Compute Hall*,
*Server Garden*, *Monolith Avenue*, *Listening Post*, *Island South Gate*,
*East Ford*.

**`lab.gd:144 _find_axis()` already resolves one** — it walks
`get_nodes_in_group("squad_objective_points")` and matches on `tag`. Generalise
that into "give me the position and facing of tag X" and the whole vocabulary is
available.

So a spec says `site_tag = &"obj_mutaha_compute"` and gets Compute Hall. Keep the
raw `site: Vector3` as a fallback for somewhere with no point on it, exactly as
`plan.site` already does.

**Why tags rather than coordinates:** a tag survives the map being rebuilt and a
coordinate does not. Mutaha is mid-rework and TERRAIN moves things; a spec
library written in `Vector3` would rot within a week. Tags also make specs
readable, which is the difference between marketing writing them and asking for
them.

**One thing to decide:** sites are authored for *gameplay*, so a tag marks an
objective rather than a good camera position. Offsetting from the tag — "ten
metres south of Compute Hall, facing it" — is probably the real need. Keeping
`heading` and a small offset in the spec should cover it.

---

## 6. OBS — the capture path for anything deterministic

**The human can let BACKLOT drive OBS, and that changes the output format.**
OBS 28+ ships **obs-websocket** (Tools → WebSocket Server Settings: enable it,
note the port, default 4455, and the password). Godot has `WebSocketPeer` built
in, so no addon is needed on our side. The v5 protocol does an identify/auth
handshake, then `StartRecord` / `StopRecord` — and `StopRecord` hands back the
output path, which is how a clip gets named for its shot. **Check the request
names against obs-websocket's own docs before building; the protocol is
versioned and this is recalled, not verified.**

### What it buys — and it is a lot

- **Encoded video instead of a pile of PNGs.** My three-move test wrote 270
  frames at **545 MB**. The same clips as MP4 are a few megabytes. At any volume
  the PNG path fills a disk.
- **Audio.** PNG sequences have none. OBS captures the game's output — the title
  drone, gunfire, rotor noise. **The trailer is wordless by design, so audio is
  doing all the work**, and this is the only route to it.
- **No encoder to maintain.** This is why the scope guard below changed: OBS *is*
  the encoder, so wanting video no longer means taking on ffmpeg.

### The trade-off, honestly

OBS captures **a window**, so the game window must be set to the output size, and
one window shows one camera. That is at odds with the `SubViewport` approach,
which can render several angles at once but is invisible to OBS.

**It resolves cleanly, because of what each tier is:**

| | Capture | Why |
|---|---|---|
| **Tiers 1–2** (poses, `FIRE_AT`, `USE_EQUIPMENT`, `REVIVE`) | **OBS** | Scripted and deterministic, so **re-running the same spec with a different camera gives the same action from another angle.** Multi-angle costs a re-run, not a take |
| **Tier 3 `ENGAGE`** | **Frame sequences** | The fight is emergent and will never repeat identically. Several `SubViewport`s recording one unrepeatable take is the only way |
| **Stills** | Either | Frames are simpler for a single image |

Hence `capture: OBS | FRAMES` in the spec, defaulting to OBS.

### Two things that will bite

- **Window size.** For OBS to get 1920×1080 the game window must *be* 1920×1080,
  and BACKLOT's camera must draw full-window. Setting the window and letting OBS
  take it is simpler than the SubViewport route — but only for the OBS path.
- **Fail loudly.** If OBS is not running, or the websocket is off, or auth fails,
  **the shot will run perfectly and record nothing.** Confirm recording actually
  started (`GetRecordStatus`) before the action fires, and abort with a message
  if it did not. Per CLAUDE.md: a function that silently does nothing is the most
  expensive kind of bug here.

---

## 7. Camera presets — the core abstraction

This is where most of the value is. Defined geometrically so they are
implementable rather than vibes:

| Preset | Geometry | What it is for |
|---|---|---|
| **`side_on`** | Perpendicular to the subject–target line, elevated, looking at the midpoint. **Already written** as `_frame_camera()` | Establishing. Two things in relation |
| **`three_quarter`** | 45° in plan from the subject's facing, ~25° elevation, framed on the subject | **The product shot.** Showing a frame off. The default for "here is the Walker" |
| **`over_shoulder`** | Behind and above the subject, offset laterally ~0.6 m, framing the target. The subject's hull holds a lower corner | Relationship and intent — the shot that says *this one is shooting at that one* |
| **`pov`** | At the subject's sensor height, looking where it looks | What a robot sees. Good for devlogs about sensors, signal, target acquisition |
| **`overhead`** | Directly above the midpoint, straight down, framed to contain everything named | Tactics legibility. **The flanking shot** — it is the only angle where "both its guns point the wrong way" is obvious |
| **`low_hero`** | At or just below capsule height, slightly looking up | **The one that makes them read as capsules.** The game's single most distinctive visual, and absent from every shot taken so far |
| **`orbit`** | Circles the subject at fixed radius and elevation over `frames` | A turntable. One spec gives every angle of a new frame |
| **`dolly`** | Interpolates between two positions with smoothstep easing | Movement. Already written in `tools/probe_shots_motion.gd` — lift it |

**Easing matters.** Linear camera motion reads as a machine; smoothstep reads as
a decision. One line, large difference.

---

## 8. Action vocabulary, tiered by what it costs you

**Build tier 1 and 2 and marketing gets most of what it needs.** Tiers are
ordered so you can stop anywhere and the tool is still useful.

### Tier 1 — state, set at spawn. Nearly free.

`STAND` · `FACE` (a direction or the target) · `AIM_AT` · `HOLD` (a given
weapon) · `DOWNED` (spawn already collapsed) · `HULL_AT` (n% damage) ·
`KIT_FITTED`

These are poses. They cover every still marketing needs for a store page, and
they are just values set before the first frame renders.

### Tier 2 — one call. Cheap, because the API already exists.

`FIRE_AT` · `USE_EQUIPMENT` (`AIEquipment.execute()`) · `REVIVE` ·
`MOVE_TO` · `ORDER` (reuse `_order()`)

**`USE_EQUIPMENT` is the one to be pleased about.** "EMP goes off", "smoke
lands", "mine detonates", "repair kit used" are all the same code path with a
different argument.

### Tier 3 — emergent. Let the fight happen and film it.

`ENGAGE` — the Laboratory's existing behaviour: both sides live, orders issued,
camera rolling. Needed for anything that must look unchoreographed, and the only
honest way to get a robot going down under real fire.

### Tier 4 — do not build yet

Multi-beat choreography, timed sequences, scripted camera cuts. Marketing is not
asking for it, it is where the complexity lives, and the editor does that job.

---

## 9. Worked examples — what marketing would actually send

These are real requests, written in the format, to check the design carries them:

```
name        walker_fires_at_rover_34
subject     chassis_walker          kit [item_autocannon]
target      chassis_rover           faction_target  enemy
separation  34
action      FIRE_AT
camera      three_quarter    cam_distance 12   cam_height 3.5   fov 50
frames      60
```
*The "frames are not tiers" shot. The Walker's bulk and the autocannon read at
three-quarter in a way they never do side-on.*

```
name        emp_among_soldiers
subject     chassis_soldier         extras [chassis_soldier, chassis_soldier]
action      USE_EQUIPMENT           action_arg  emp
camera      low_hero         cam_distance 6    cam_height 0.8
frames      90
```
*Signal as the second health bar — the mechanic nobody can currently see.*

```
name        mechanic_revive_ots
subject     chassis_mechanic
target      chassis_soldier         action_target_state DOWNED
action      REVIVE
camera      over_shoulder    cam_distance 3.5  cam_height 2.2   fov 55
frames      120
```
***The single most wanted asset in the project.*** The itch gallery GIF, the
trailer's climax, and the one thing nobody has been able to capture.

```
name        walker_flanked_overhead
subject     chassis_walker
target      chassis_rover           extras [chassis_rover]
action      ENGAGE
camera      overhead         cam_height 26
frames      150
```
*The counter-play shot. Only overhead makes the slow turret traverse legible.*

```
name        squad_advance_low
subject     chassis_soldier  extras [chassis_soldier, chassis_rover, chassis_spotter]
action      MOVE_TO
camera      low_hero         cam_distance 9    cam_height 1.1
frames      90
```
*Four frames, separated, at capsule height. The cover shot that three attempts
have now failed to get.*

---

## 10. The two pieces of plumbing that are not negotiable

### 8a. Render to a fixed-size `SubViewport`

**Not the window.** Every existing shot script calls `root.get_texture()`, which
returns the game window, which is why the entire screenshot library came back
**1152×648 — below Steam's 1920×1080 minimum** and unusable on a store page.

Worked example that produced verified 1920×1080 output:
`tools/probe_shots_motion.gd`.

Prefer a dedicated `Camera3D` inside that SubViewport over moving
`world.player` — it avoids the HUD entirely and allows several cameras at once.

### 8b. The event index

A plain log beside the frames, with **frame numbers as well as timestamps**, so
marketing can cut straight to the moment instead of scrubbing:

```
# events.txt — mechanic_revive_ots
  frame   t      event              who
    001   0.00   capture_start
    042   1.40   went_down          ALLY-3
    088   2.93   revived            ALLY-3      <-- the shot
    120   4.00   capture_end
```

`Enemy` already carries every signal this needs, all verified by line number:
`combat_triggered` (1346) · `went_down` (1245) · **`revived` (1246)** ·
`destroyed` (1250) · `ekilled(victim, by)` (1098) ·
`close_threat_engaged` (506).

For `ENGAGE` shots this is the difference between usable footage and a pile of
PNGs nobody opens.

---

## 11. Done when

- A `.tres` shot spec plus one command leaves, in a folder named for the shot,
  either **an MP4 from OBS** or **a numbered PNG sequence**, at **1920×1080 or
  better**, plus `events.txt`.
- **A spec naming `level` and `site_tag` stages on that map at that place.** The
  tag vocabulary in §5 resolves without marketing supplying coordinates.
- **OBS failures are loud.** With OBS closed or the websocket off, the run aborts
  with a message rather than completing and recording nothing.
- **`three_quarter`, `over_shoulder`, `low_hero` and `overhead` are implemented**
  — those four carry almost every asset marketing wants.
- Tier 1 and tier 2 actions work, including `USE_EQUIPMENT`.
- A clean pass has **no HUD in frame**.
- `mechanic_revive_ots` from §9 produces frames showing the revive, and a
  `revived` line in the index.
- `bash tools/check.sh --changed` prints `PASS`; `tools/test.sh` if you touch
  anything with an invariant.

---

## 12. Scope guard — please do not build these

- **No encoder of our own.** ~~PNG sequences only~~ — **revised: OBS does the
  encoding** (§6). The guard still holds in substance: do not take on ffmpeg or
  write an encoder. Either OBS records it or we write frames.
- **No editing or assembly.** The index solves finding; a human cuts.
- **No managing OBS's own settings.** Encoder, bitrate, frame rate and output
  folder are configured once in OBS by hand. BACKLOT starts and stops it and
  reads back the path. Nothing more.
- **No realtime performance work.** This runs offline with nobody waiting. Slow
  is fine; correct is not optional.
- **No camera UI or editor panel.** Specs are resources, authored as text.
- **No changes to Laboratory scoring, `lab_report.md`, or the analytics hooks.**
  Other people depend on them.
- **No tier 4.**

---

## 13. Open questions — marketing's answers, overrule freely

1. **30 fps.** It matches `probe_shots_motion.gd` so clips cut together.
2. **Output location:** anywhere outside the repo. `lab.gd` uses
   `user://lab/<date_time>/`; something parallel seems right.
3. **Should BACKLOT get its own arena**, dressed for photography — flat ground,
   controllable light, no scenery — rather than `proving_level`? Marketing
   suspects yes for tiers 1–2 and no for `ENGAGE`, but this is a TERRAIN
   question as much as yours. **Note this is now a smaller question than it was**:
   with `site_tag` addressing (§5), most shots will be staged on real maps
   anyway, and a photography arena is only for the clinical "here is the Walker"
   product shots.
6. **Does the OBS path need the game window to be borderless/undecorated** to
   get exactly 1920×1080 of game pixels? Marketing does not know and it is the
   sort of thing that costs an afternoon if found late.
7. **One OBS scene, or one per camera preset?** A scene per preset would let OBS
   hold its own framing, but marketing's assumption is that BACKLOT owns all
   framing and OBS is a dumb recorder. Simpler, and fewer things to keep in sync.
4. **Time of day.** Marketing wants it specifiable per shot, because the last
   screenshot set came back bright midday on a game about a dead planet. If
   that is expensive, say so and it becomes a level-authoring problem instead.
5. **Is the capture camera better fully independent of `world.player`**, rather
   than riding `_become_ghost()`? Marketing's instinct is independent; you know
   what that interacts with.

---

## 14. A warning about the last brief this lane sent

`docs/marketing/SHOT_BRIEF.md` was followed exactly and still produced unusable
images: resolution was never stated as non-negotiable, lighting was left as "as
authored" and came back as bright midday, and it never said the subject had to be
unoccluded or that the action had to be *happening*.

So, flatly, rather than left to inference: **1920×1080 minimum. No HUD on the
clean pass. The subject unoccluded and filling at least a third of frame width.
The action happening rather than about to.** If any of that is wrong or
expensive, say so — it should not be guessed at.
