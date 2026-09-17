# CLAUDE.md — Roboto

Read this before touching anything. It is short on purpose; the long version is
`docs/BRIEFING.md`.

## What this is

A first-person squad-command shooter in Godot 4.3. You are a rogue drone
commanding robots. Levels are TrenchBroom brush geometry via FuncGodot.
Structure is persistent squad + discrete missions from a home base.

## Before you start

1. Read `docs/BRIEFING.md`. Sections 3 and 4 in particular — the invariants and
   the failure patterns. Most bugs in this project are repeats of those.
2. Work on a branch: `git checkout -b agent/<short-task-name>`.

## Before you finish — non-negotiable

Run the verification script. It must print `PASS`.

```bash
bash tools/check.sh --changed
```

If it fails, fix it. Do not report a task complete with a failing check. If you
genuinely cannot make it pass, say so explicitly and explain what's blocking.

`bash tools/check.sh` with no argument checks the whole project (~90s, 91
scripts and 175 resources). Use it when you have touched something shared.

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

- **You cannot run the game.** No display, and the repo is missing art assets.
  Parse checks and scene integrity are the only verification available. Say so
  when it matters rather than implying you tested behaviour.
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
