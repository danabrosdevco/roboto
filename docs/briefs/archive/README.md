# Archive — briefs that are DONE

**Nothing in this folder is a to-do.** Everything here was built, shipped, or
superseded. It is kept because the *reasoning* is still worth having — these
documents are why the code looks the way it does, and several are cited by
name from code comments.

**Do not start work from a document in here.** If you think one describes
something that is not true of the game, the document is history and the game
is right. Say so rather than "fixing" the game to match.

## Why a brief gets moved here

A brief in `docs/briefs/` is a thing somebody might pick up. A brief that is
finished and left there is a trap: `MARK_SYSTEM_SPEC.md` carried the line
*"Status: specced, not built. No code exists"* for a full day after it was
built in its entirety.

So: **when a brief is done, move it here and correct its status line in the
same commit.** Fix every reference to its path at the same time —
`grep -rl "docs/briefs/<NAME>.md"` across `*.gd` and `*.md` — because this
project cites briefs from code comments and a dangling path is worse than no
path at all.

## What is in here, and what replaced it

| brief | state | current truth lives in |
|---|---|---|
| `MARK_SYSTEM_SPEC.md` | built 2026-10-22, steps 1–7b | vault → `Atlas/Squad manager` |
| `MEMORY_SCREEN_SPEC.md` | built 2026-10-22 | vault → `Atlas/Squad manager` |
| `DEPARTURE_RIDE.md` | built 2026-10-11, now being removed | `docs/briefs/ORBIT.md` |
| `OPS_TABLE_LEVER.md` | built; the lever is being deleted | `docs/briefs/ORBIT.md` |
| `PLATFORM_DOOR_TO_OPS.md` | built; superseded by the move to orbit | `docs/briefs/ORBIT.md` |
| `new_chassis_audit_raw.md` | raw measurement dump | `docs/briefs/NEW_CHASSIS_AUDIT.md` |
| `new_chassis_recheck_raw.md` | raw measurement dump | `docs/briefs/NEW_CHASSIS_AUDIT.md` |
| `OPS_TABLE_FURNITURE.md` | built; the table ships and survives the move to orbit | vault → `Atlas/Home base and departure` |
| `VERIFICATION_HANDOVER.md` | adopted — buckets, checklists and the CLAUDE.md shrink all landed | vault → `Tools`, `Verify` |
| `HILLFORT_WIP_HANDOVER.md` | consumed; produced `hfw_1_fort` and `hfw_2_defend` | vault → `How to/Hand a map from TERRAIN to GAMEPLAY` |
| `SITE_CONVERSION.md` | done — ten `*_slice.gd` exist | vault → `How to/Convert a map into a site` |
| `ATTACK_AND_DEFEND.md` | done — ten `*_defend` missions exist | — |
| `ONE_PIN_PER_SITE.md` | done — `ops_table.gd` keys by Location, arenas excepted | — |
| `OPERATIONS_TABLE.md` | built and shipping; its status line still said "nothing built yet" | vault → `Atlas/Campaign and board` |
| `PROVING_GROUNDS.md` | done — `tools/build_proving.gd` rebuilt the arena the same day | — |
| `SIM_ARENA_MODE.md` | done — arena, induction and Lab all ship; partly superseded when First Contact was cut | vault → `Atlas/Campaign and board` |
| `MARKETING.md` | not done — MOVED, it is a lane charter | vault → `Lanes/MARKETING` |

`docs/concepts/archive/` holds the same thing for concept rounds that lost —
the compute-core explorations that `CORE_SKELETON` and `CORE_RELAY` beat, and
those two themselves now that they are built and shipped.

## The index

The Obsidian vault at `D:\Godot Games\DCW-Obsidian\data-center-wars` holds
`Source docs.md`, which lists every document in this tree with its status.
That is the fastest way to see what is live.
