# Pulling footage with AI — a one-day plan

Written 2026-10-13 by MARKETING, answering: how to use AI to get interesting
game footage, with a day and plenty of agent capacity to spend.

---

## The thing that changes the answer

**You already have ~107 hand-tuned camera positions.** `tools/probe_shots_*.gd`
holds them across eight levels — position, look-at and FOV for every one, each a
composition somebody already judged worth keeping:

| Script | Positions |
|---|---|
| `probe_shots_mutaha_wip.gd` | 37 |
| `probe_shots_hillfort.gd` | 22 |
| `probe_shots_proving.gd` | 12 |
| `probe_shots_pittsburgh.gd` | 10 |
| `probe_shots_salient.gd` | 10 |
| `probe_shots_block` / `bridge_proposal` / `alpine` | 16 |

**So the job is not "find interesting footage". It is "connect positions that are
already catalogued, and fix the one line that is throwing away the resolution."**
That is a much smaller job and it fits in a day.

---

## The three unlocks, cheapest first

### 1. One line — the resolution

Every existing shot script ends with:

```gdscript
root.get_texture().get_image().save_png(...)
```

`root` is the game **window**, so the output is whatever size the window
happened to be — which is why everything came back **1152×648**. That is below
Steam's 1920×1080 minimum and soft on itch.

Render into a `SubViewport` at an explicit size instead and it is fixed,
independent of the desktop, for every script. Done in
`tools/probe_shots_motion.gd` and it is four lines.

**Rerunning the existing scripts after that fix regenerates the entire still
library at proper resolution, for free.** That alone may be the single
highest-value hour of the day.

### 2. Camera moves — footage from positions you already have

A move between two catalogued positions, interpolated over 90 frames with
smoothstep easing, is three seconds of footage and costs one line of authoring.
`tools/probe_shots_motion.gd` does this and writes `0001.png, 0002.png …`
— **CapCut and DaVinci Resolve both import a PNG sequence directly**, so no
ffmpeg is needed (it is not on this machine anyway).

Three moves are authored already as a proof: a walk down the quarter's street,
a push onto the plaza, a descent onto the island tip. The street one is the shot
the wordless trailer opens on.

**Easing matters more than it sounds.** Linear camera motion reads as a machine;
smoothstep reads as a decision. One line, large difference.

### 3. Robots in frame — the actual gap

Every environment shot is empty. Marketing needs the squad in them, and this is
where the day's remaining hours should go. Two routes:

- **Spawn a squad at a known point** in the capture script and park the camera.
  Static, controllable, reliable.
- **Use the Laboratory.** `Managers/lab.gd` already runs headless AI-vs-AI squad
  fights. **GDD §8 calls it "the most under-used thing in the repo."** Park a
  camera in the arena, let a plan run, and you get real combat — robots
  advancing, engaging, going down — with nobody playing. That is the footage
  that is otherwise hardest to get, and the machinery exists.

The Laboratory route is the higher-value one and the one I would spend the
afternoon on.

---

## What AI is actually good for here, and what it is not

Worth being exact, because it decides how to spend the capacity.

**Genuinely useful:**

- **Writing and extending the capture tools.** Fast, and the existing scripts are
  a clear pattern to follow.
- **Authoring camera moves at volume.** I can read the catalogued positions and
  emit dozens of plausible moves across every level in minutes.
- **Visual triage.** *This is the distinctive one.* Render 200–400 candidate
  frames, tile them into contact sheets, and I review and shortlist them. A
  human doing that is a long, dull afternoon. This is the one job where a model
  that can see images beats you on throughput rather than just on patience.
- **Writing the VO script** for whatever survives triage.

**Not useful, and claiming otherwise would waste your day:**

- **I cannot watch video.** I judge frames, not motion. Whether a move *feels*
  right is yours.
- **I cannot tell whether a fight is exciting**, only whether a frame is
  well-composed.
- **I cannot edit, record, or play.** Anything requiring the game to be played
  well is yours.
- **Rendering is wall-clock, not capacity.** The machine is busy and the GPU is
  occupied; agent capacity does not make it faster.

---

## The day, with the waiting overlapped

The renders are the long pole, so start one and work on the next thing while it
runs. Never sit watching a render.

| | You | Me, in parallel |
|---|---|---|
| **Hour 0–1** | Apply the SubViewport fix to the existing shot scripts, kick off a full re-render of the still library at 1920×1080 | Author camera moves for the other seven levels from their catalogued positions |
| **Hour 1–3** | Renders running. Set up OBS and CapCut while you wait | Build the contact-sheet tool; triage the stills as they land |
| **Hour 3–5** | Render the camera moves | Shortlist the moves worth keeping; draft the Laboratory capture script |
| **Hour 5–7** | Run Laboratory fights with a parked camera — the combat footage | Review the fight frames; mark the seconds worth cutting to |
| **Hour 7–8** | Record VO over the best of it | Write the VO script, the itch devlog post and the Reddit post |

**If the day gets short, do hour 0–1 and nothing else.** A full still library at
proper resolution is worth more than a half-finished video pipeline, and it is
what the itch page and the Steam page both actually need.

---

## The triage loop, concretely

The part worth setting up properly, because it is reusable forever:

1. Capture writes to a flat directory, one PNG per candidate.
2. A small script tiles them 4×4 into labelled contact sheets.
3. I read the sheets and return a shortlist of cell names — fast, because a
   sheet carries sixteen candidates for the cost of looking at one image.
4. I then look at the shortlisted frames full size and rank them.
5. Output: a ranked list of shot names, which feeds straight back into the
   `SHOTS` array as the next render's input.

**This is a loop, not a one-off.** Each pass narrows: render wide, triage, render
the survivors with motion, triage again.

---

## What to shoot, if you want the list now

From `docs/marketing/SHOT_BRIEF.md`, with Revision 2's corrections applied —
dusk or overcast, subject unoccluded and at least a third of frame width, camera
at capsule height, action mid-motion:

1. **The Mechanic revive.** Still *and* 6–8 seconds of video. It is the itch
   gallery GIF, the hero shot, and there is nothing to cut one from today. **If
   one thing gets captured this day, make it this.**
2. A squad walking, unoccluded, four frames separated.
3. An order being given, HUD on, squad moving to it in frame.
4. A Walker being flanked, turret visibly pointing the wrong way.
5. Street-level moves through Mutaha at dusk — the tone shots, already proven by
   `environments/mutaha_wip_14_quarter_street.png`, which is the best image the
   project has and is now the itch cover.

---

## One caution

The capture scripts **open a window and use the GPU** — they are not headless,
because the dummy renderer returns blank images. The machine will be busy and
windows will appear. Worth knowing before you start a long render and then try
to do something else on the same box.
