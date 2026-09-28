# Board

The one place that says what is in flight. Opened 2026-09-23.

**Only the coordinator writes this file.** Both build agents read it and report
back in chat; their reports get folded in here. That keeps the board out of the
merge path — it is the one file that can never conflict.

The long-lived stuff lives elsewhere and this file does not repeat it:
`docs/GDD.md` is what the game contains, `docs/BRIEFING.md` is how the code is
shaped, `docs/GAMEPLAN.md` is the argument for the demo's dramatic arc.

---

## Lanes

Two build agents, one checkout (`D:\Godot Games\roboto`), one branch. Collisions
are prevented by who owns which path, not by branching.

| Path | Owner |
|---|---|
| `maps/**` (levels, blocks, `.map`) | TERRAIN |
| `Env/terrain/**`, `Env/world_objects/**` | TERRAIN |
| `tools/block_*.gd`, `terrain_bake.gd`, `minimap_bake.gd` | TERRAIN |
| `trenchbroom/**`, `textures/**` | TERRAIN |
| `docs/TERRAIN.md`, `docs/BLOCKS.md` | TERRAIN |
| `Campaign/**` (missions included) | GAMEPLAY |
| `Character/**` | GAMEPLAY |
| `Managers/**` | GAMEPLAY |
| `tools/test_*.gd` | GAMEPLAY |
| `docs/GAMEPLAN.md`, `docs/BARK_LIBRARY.md` | GAMEPLAY |
| `docs/BOARD.md`, `docs/GDD.md`, `docs/APPENDIX.md` | COORDINATOR |

**Shared — neither agent edits without saying so first:**

`Env/world.tscn` · `docs/BRIEFING.md` · `CLAUDE.md` · `project.godot` ·
`tools/check.sh`, `test.sh`, `smoke.sh`

**Missions are GAMEPLAY's, not shared.** Confirmed 2026-09-23: the terrain agent
does not build missions. TERRAIN builds and dresses the map; GAMEPLAY authors the
operation that runs on it. That keeps the one file both could want in a single
pair of hands.

---

## NOW

One item per lane. Not two.

| Lane | Item | State |
|---|---|---|
| TERRAIN | map work, unreported | awaiting first status report |
| GAMEPLAY | **causeway mission** | assigned by the human before this board existed |

After causeway, GAMEPLAY needs a new direction — see NEXT, and settle the
falloff question first.

---

## NEXT

Provisional — the tier expansion is agreed in principle but not yet scoped with
the human. Ordering is a guess until that conversation happens.

1. **Armour model** — reviewed, see NEEDS YOU #1–3. Blocked on the range
   question before anything is built.
2. **Causeway mission** — the map is the largest in the repo and the intended
   end of the ladder, and no mission points at it.
3. **Retire the obsolete ladder** — 15 of 22 mission files are outside the live
   campaign. Appendix, don't delete.
4. **Catalogue the built-but-dark frames** — Quadcopter Bomber, Marksman,
   Mortar Track, Lobber Rover all exist and none is purchasable.

---

## NEEDS YOU

Decisions and playtests only the human can make. Kept short on purpose; if this
list is long, the agents are blocked and the board has failed.

1. **Armour vs damage falloff — the one blocker.** Ruled: steep falloff on early
   guns is wanted, and range is the deciding stat. Not yet ruled: whether FLAT
   subtracts *before* or *after* falloff. "Steep falloff on early guns" points
   at **after**, which makes armour bite hardest at the range the player
   prefers to fight from. Confirm before anything is built.
2. **How big is the supply pool?** The debrief screenshot deploys seventeen
   robots. A pool only creates a decision if it is smaller than what is fielded
   today.
3. **Can the player carry anti-armour?** If yes, the long-range-god problem
   returns intact. If no, the squad becomes the only answer — which is the
   pillar.
4. **Three of four squad orders lose 100% of the time** in the Laboratory.
   Broken orders, or a tuning problem?

**Resolved 2026-09-23** — kept here until they land in the code:

- Falloff stays; early guns should drop off hard. Explosives not degrading is an
  accepted consequence, and MG and GL rovers test about equal today.
- `armour_class` goes on `ChassisDefinition` only; `Enemy` does not carry it.
- The Nest stays as it is — a structure that does not move, and the first of
  many enemy structures.
- AI shotgun switched to pellets; the in-game number is correct as it stands.
- `valley_level` is dead. `arena_level` and `homebase_level` look dead too.
- **The agents can run the game.** CLAUDE.md's "You cannot run the game" is
  stale — both build agents boot it and take screenshots. That section needs
  rewriting, and it changes what "verified" may mean in a report.

---

## LANDED

Nothing yet under this board.

---

## Protocol

**Opening a session.** Read your lane's NOW line. If it is empty, ask before
starting — do not pick your own.

**Closing a session.** Commit with a message that says *why*, not "big push".
Then report: what landed, what the gates said, and anything the human must check
in-editor. That last part is the most valuable thing produced, and until now it
has been dying in chat scrollback.

**Gates,** per CLAUDE.md — `bash tools/check.sh --changed` must print `PASS`.
`tools/test.sh` after touching the ledger, armoury or anything with an
invariant. `tools/smoke.sh` after touching anything that loads at startup.

**Staying out of each other's way.** One checkout, one branch, and another agent
is usually mid-edit. Do not `git checkout`, do not `git checkout -b`, do not
stage files that are not yours. Check the branch with `git branch --show-current`
only. To commit without disturbing anyone: build a tree with a throwaway index
(`GIT_INDEX_FILE=… git read-tree HEAD`, `git add`, `git write-tree`,
`git commit-tree`) and move your own branch to it.
