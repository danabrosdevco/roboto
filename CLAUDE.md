# CLAUDE.md — Roboto

Read this before touching anything. It is short on purpose; the long version is
`docs/BRIEFING.md`.

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
2. Do not create or switch branches. Three lanes share one checkout and one
   branch, and another agent is usually mid-edit — see `docs/BOARD.md` →
   Protocol. Check where you are with `git branch --show-current`.

## Before you finish — non-negotiable

Run the verification script. It must print `PASS`.

```bash
bash tools/check.sh --changed
```

If it fails, fix it. Do not report a task complete with a failing check. If you
genuinely cannot make it pass, say so explicitly and explain what's blocking.

`bash tools/check.sh` with no argument checks the whole project — 309 scripts
and 638 scenes and resources, so it is slow. Use it when you have touched
something shared.

Two more, both of which catch what a parse check cannot:

```bash
bash tools/test.sh
bash tools/smoke.sh
```

`test.sh` runs the headless logic suites in `tools/test_*.gd` — run it after
touching the ledger, the armoury or anything with an invariant. `smoke.sh`
boots the game headless and fails on runtime errors; run it after touching
anything that loads at startup.

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

- **You can run the game, but you cannot play it.** `tools/smoke.sh` boots it
  headless, the Laboratory runs AI-vs-AI matchups, and `tools/mockup_shots.gd`
  loads a real level, places a camera and writes the viewport to PNG. What you
  cannot do is take the controls and judge how it feels — that is the human's.
  Run muted (`--audio-driver Dummy`), and never let a run write `campaign.json`.
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
- Game feel and balance. You can't play it; the human can.
- Anything touching save format or enum ordering.
- Deleting authored content (`.tscn`, `.tres`, levels).

## Definition of done

- `bash tools/check.sh --changed` prints `PASS`
- Changes are on a branch, committed with a message saying *why*
- You've listed anything you changed that the human needs to verify in-editor
  (scene wiring, inspector values, anything you couldn't test)
