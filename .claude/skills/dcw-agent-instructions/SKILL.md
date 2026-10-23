---
name: dcw-agent-instructions
description: How to add a feature to Data Center Wars and how to verify it before reporting. Use when the request is a NEW chassis, map, site, mission, weapon, module or objective — and again before reporting ANY work as done, to pick which suites to run. Covers the five test buckets, the feature completeness checklists, and the traps that fail silently.
---

# Working on Data Center Wars

`CLAUDE.md` is already in context and holds the premise, the lane protocol and
the gotchas. **This skill is the part that is only needed sometimes:** what a
new feature must have, and what to run before saying it is done.

Two documents carry the detail. **Read the one that applies — do not work from
memory of it, and do not work from this file alone.** Both are kept current;
this skill is a router, not a copy, because a second copy drifts and a drifted
checklist still reports a pass.

| when | read |
|---|---|
| the request is a NEW chassis, map, site, mission, weapon, module or objective | **`docs/FEATURE_CHECKLISTS.md`** |
| you are about to report any work | **`docs/TESTING.md`** |

---

## 1 · If it is a new anything

Read `docs/FEATURE_CHECKLISTS.md` and work the matching list. **Account for
every line in your report** — done, or why it does not apply. "I added the
chassis" is not a report; the list is what "added" means.

A feature here is never one file. Nearly every entry on those lists fails
**silently**: the thing loads, nothing errors, and it is simply absent or
inert until somebody plays it. A few of the sharpest, as a taste of why the
list is not optional:

- a mission whose `requires` names an **unregistered** mission locks the whole
  campaign with no error, because it can never be completed
- `reinforcement_tag` is an **objective id**, not a free-form tag — a typo
  means the reserve wave never arrives and the fight is quietly easier
- `cores_by_node` matches **node names**, which is the opposite of everything
  else on a map, where missions resolve by `tag`
- patrol **markers are not a route** — without a `PatrolPath` in the
  `patrol_paths` group, `route_tag` finds nothing and the squad stands still
- a new weapon is **not covered** by `test_reload_motion.gd` until it is added
  to the hardcoded list inside it
- a new Location moves the board's income arithmetic, which
  `test_campaign_spine.gd` asserts

If a line on those lists is wrong or missing, **fix the list in the same
change.** A checklist nobody maintains is worse than none, because it is
trusted.

---

## 2 · Before reporting anything

```bash
bash tools/check.sh --changed     # non-negotiable, must print PASS
bash tools/bucket.sh --list       # the five buckets and their sizes
bash tools/bucket.sh <name>       # campaign | frames | kit | terrain | shell
bash tools/smoke.sh               # if anything loads at startup
```

**Run a named bucket, never a set you assembled yourself.** A bucket is a
group somebody agreed to, so "campaign passed, 40 suites" means the same thing
twice running. A hand-picked list is unreviewable and different every time —
that is the whole reason buckets exist.

`docs/TESTING.md` has the table of which bucket for which change, plus what
each tool actually proves.

### Never write "the full suite"

`tools/test.sh` **cannot currently finish**: it has no per-suite timeout and
`test_designator_squad.gd` never terminates, so everything behind it stalls.
The phrase is always either false or unverifiable. **Name the suites you ran
and their counts** — "30/30 on `test_hillfort_wip`" is a report; "tests pass"
is not.

### Look at anything visual

If the change affects something on screen, render it with a `shot_` tool and
**open the image**. A structural probe cannot see a bunker buried in a berm, a
body standing behind the core it is guarding, or a door that is simply shut.
`shot_` tools are headful on purpose — a headless render returns blank
textures and looks like proof.

### Say what you did NOT verify

The most valuable line in any report. "Built it, did not run it" is useful;
"done" when it was never launched is not. You can run the game freely and
**play it if you ask first** — what does not transfer is judging how it feels
on the human's behalf.

---

## 3 · Before you touch a shared file

Three lanes share one checkout and one branch. `CLAUDE.md`, `Env/world.tscn`,
`docs/BRIEFING.md`, `project.godot` and the three runner scripts are shared —
edit them if the work needs it, but **say so explicitly in your report**.
`docs/BOARD.md` has the ownership table. Do not create or switch branches.
