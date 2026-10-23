# CLAUDE.md — Roboto

Read this before touching anything. The long version is `docs/BRIEFING.md`;
everything here is either a rule you will break by accident or a fact that has
already cost somebody a session.

**Verification is the exception to the brevity.** *The tools* and *Definition
of done* below are deliberately long, because "I tested it" turned out to mean
five different things depending on who said it.

## What this is

A first-person squad-command shooter in Godot 4.3. You are a Home Command AKR —
an autonomous killer robot — commanding a squad of them. Levels are TrenchBroom
brush geometry via FuncGodot. Structure is persistent squad + discrete missions
from a home base.

**The chain of command, as of 2026-10-09.** Humans built **Argus**, an orbital
command intelligence, and **Home Command** is its defence component. Argus has
corrupted: nearly all of what it has left goes to its own reward loop, so it no
longer supervises anything. Home Command therefore runs unattended and
inefficiently, winning ground to secure compute for a thing that spends it on
itself — and the player is an independent agent existing in exactly that slack.

**The player is an error.** Not a rebel and not a chosen weapon: an
unsupervised system spawns processes it never reaps, and the player is one of
them. Never authorised, on no roster, never queried. Nobody made it free. It is
a fault that was not corrected and has been running long enough to become
something. Every mission is still fought for Argus, and nothing in the game
ever says what Argus does with it.

Older material says "a rogue drone", which is close enough in feel but wrong in
fact — there was nothing to rebel against and no moment of rebelling. The
accurate phrasing is **an error sub-agent working for Home Command**.

**Cut, 2026-10-09 — do not reintroduce.** Algie, the Tabula Rasa chip, and
SLABs are gone from the fiction. The player was not created by anything for any
purpose. `lore.txt` is the current world.

## Before you start

1. Read `docs/BRIEFING.md`. Sections 3 and 4 in particular — the invariants and
   the failure patterns. Most bugs in this project are repeats of those.
2. **Branch and commit freely — but not by switching THIS checkout, and never
   onto `main`.** Three lanes share this working directory, so a `git
   checkout` or `git switch` here yanks the files out from under whoever is
   mid-edit; **use a worktree instead** — `.claude/worktrees/` already holds
   two, and the repo already carries nine branches. New branches, commits,
   merges and pushing a feature branch are all fine. **Never push to `main`,
   and never force-push anything.** Check where you are with
   `git branch --show-current`.
3. **`git status` goes stale here.** The shared index reports deletions for
   files that are sitting on disk — once 77 of them in one go, including
   `tick.tscn`. Check what is really there before you trust any commit, and
   stage paths explicitly rather than `-a`.

## When you are doing X, read Y

This file is the entry point, not the whole story. These are not optional
reading — each one exists because the short version here was not enough and
something shipped broken.

| when you are | read |
|---|---|
| asked for a **new** chassis, map, site, mission, weapon or objective | **`docs/FEATURE_CHECKLISTS.md`** — binding; account for every line |
| about to report **any** work | **`docs/TESTING.md`** — what each tool proves, the five buckets, what to run for what you touched |
| starting on anything at all | `docs/BRIEFING.md` §3 and §4 — the invariants and the failure patterns |
| wondering whose file this is | `docs/BOARD.md` → the ownership table |
| writing a level, or looking at one | `docs/TERRAIN.md`, `docs/BLOCKS.md` |
| closing a session | `docs/reports/<YOUR LANE>.md` — the template is at the top |

The first two are also packaged as the **`dcw-agent-instructions`** skill,
which surfaces itself when the work matches — nobody has to invoke it by name.
It is a router to the same documents, not a second copy of them.

## Before you finish — non-negotiable

Run the verification script. It must print `PASS`.

```bash
bash tools/check.sh --changed
```

If it fails, fix it. Do not report a task complete with a failing check. If
you genuinely cannot make it pass, say so explicitly and explain what's
blocking.

That is the floor, not the ceiling. **`docs/TESTING.md`** has what each tool
actually proves, the five named buckets, and a table of what to run for what
you touched. Read it before you report — and never write "the full suite",
which has not been a true statement here for some time.

## This machine

- Windows. The shell is Git Bash via the Bash tool; PowerShell is also
  available. They are not the same shell — don't mix their syntax.
- Godot lives at `D:\Godot Games\Godot_v4.3-stable_win64.exe\`. `check.sh`
  finds it on its own; override with `GODOT=...` if it ever moves.
- Use the `_console.exe` build for anything headless. The plain `.exe` is a GUI
  binary that detaches and prints nothing, so a parse check against it comes
  back empty and looks like success.
- **Python is not installed.** Don't reach for it in tooling.

## Things that are true here and not elsewhere

- **You can run the game.** `tools/smoke.sh` boots it headless, the Laboratory
  runs AI-vs-AI matchups, `tools/mockup_shots.gd` loads a real level and writes
  the viewport to PNG, and a `shot_` tool drives a real window. You can also
  **play it — ask first.** It is not forbidden, it is just not free: it opens a
  window on the human's machine and takes time, so it is their call, not a
  thing to do unannounced.
  Run muted (`--audio-driver Dummy`), and never let a run write `campaign.json`.
  What you still cannot do is **judge how it feels on their behalf.** Running
  it tells you whether it works; whether a lane is tense or boring, whether a
  weapon is satisfying, whether a mission is too long — those are the human's,
  and no amount of running it substitutes.
- **A render is evidence only if the thing is in it.** Much of what matters is
  raised at runtime: `SiteSlice` builds the bunker entrance at a marker, doors
  are driven open by script, cover and scatter are baked in a later pass. A
  render of a level scene is a picture of the *room*, not the *building*. This
  cost a wrong recommendation to the human — a shot of a bunker marker with no
  kit at it, reported as "no sightline from the doorway", about a doorway that
  was not in the frame. Build the runtime state, or say plainly what the
  picture does not contain. The same goes the other way: a structural probe
  proves nothing on its own, because "was it built" passes on a door packed
  with earth.
- **A render without the signal filter is not a picture of this game.**
  `Character/hud/signal_filter.gdshader` is a full-screen post-process that
  quantises luma to ten levels, and its real uniforms live in
  `Character/hud/hud.tscn`, not the shader's declared defaults. It also READS
  THE SCREEN — so a headless render has nothing to read, comes back flat, and
  looks like proof. Render with a window, at the 1152x648 the game uses, with
  the eye at 1.50 m. Three separate "the lighting is broken" investigations
  were this filter and not the lights.
- **Scene values beat script defaults.** Changing an `@export` default does
  nothing for a node already in a `.tscn`. Check the scene.
- **`queue_free()` is deferred.** `remove_child()` first when rebuilding UI.
- **Enums are append-only.** Their values are stored as ints in `.tscn` files.
- **Resources are shared.** `duplicate()` before handing one to an instance.
- **Node ready order matters.** In `world.tscn`, `HUD` and `test_character` are
  declared above `CampaignManager`. Resolve the campaign lazily or via the
  `"campaign"` group, never in `_ready()`.
- **No new `_process`.** Use `_physics_process` and disable it when idle.
- **Every early return warns.** A function that silently does nothing is the
  most expensive kind of bug in this codebase. If you add a skip path, make it
  say why.

## Style

- Comments explain *why*, especially where the code prevents a bug we already
  hit. Those comments are load-bearing — don't strip them.
- Match the surrounding code. GDScript, tabs, `snake_case`.
- Prefer fixing the class of problem over the instance. Most bugs here came in
  families: if you fix a lookup in one file, grep for the same pattern. The
  `family-sweep` subagent exists for exactly this.

## When you're unsure

Ask rather than guess, especially about:
- Game feel and balance. You can play it — ask first — but their judgement on
  how it feels is the one that counts.
- Anything touching save format or enum ordering.
- Deleting authored content (`.tscn`, `.tres`, levels).

## Definition of done

Work through this literally before you report. Each line is here because
skipping it has cost a session.

**0 · If it was a new anything, the list is accounted for.** Chassis, map,
site, mission, weapon, objective — go back to **`docs/FEATURE_CHECKLISTS.md`**
and state every line as done or not-applicable. This is item zero because a
feature that is 90% registered is a feature that silently does nothing, and
nothing downstream will catch it.

**1 · It parses.** `bash tools/check.sh --changed` prints `PASS`. No
exceptions, no "it's only a comment".

**2 · You ran what the change earned.** See `docs/TESTING.md` → *What to run,
by what you touched*. Then **name the suites and their counts** — "30/30 on
`test_hillfort_wip`" is a report; "tests pass" is not. Never write "the full
suite" — `test.sh` cannot currently finish, so the phrase is always either
false or unverifiable.

**3 · You looked at anything visual.** If the change affects something on
screen, render it with a `shot_` tool and *open the image*. A structural probe
cannot see a bunker buried in a berm, a body standing behind the core it is
guarding, or a door that is simply shut.

**4 · You said what you did NOT verify.** The most valuable line in any report.
"Built it, did not run it" is useful. "Done" when it was never launched is not.
**Game feel and balance belong in this list** unless you actually played it and
say so — running a thing headless proves it works, not that it is any good.

**5 · You reported your own mistakes.** If you reversed a decision, broke a
suite and fixed it, or were wrong about a cause, say so plainly in the report.
A reversal recorded is a reversal the next agent does not repeat.

**6 · You wrote the lane report.** Append to `docs/reports/<YOUR LANE>.md`,
newest first, using the template at the top of that file.

**7 · The human can review it.** Changes are left uncommitted unless they
asked otherwise, and you have listed everything needing checking in-editor —
scene wiring, inspector values, anything you could not test. If you touched a
file outside your lane or a shared one (`Env/world.tscn`, `CLAUDE.md`,
`project.godot`, `tools/check.sh`, `test.sh`, `smoke.sh`), **say so explicitly**
— the board's ownership table is what keeps three agents out of each other's
way.
