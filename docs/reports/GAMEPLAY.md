# GAMEPLAY — session reports

**Only the GAMEPLAY agent writes this file.** The coordinator reads it and folds
it into `docs/BOARD.md`. Nobody else touches it, which is why two lanes can
close a session at the same moment and never conflict.

**Append a new entry at the TOP, under this header.** Newest first. Keep old
entries — the point of this file is that the board has a memory.

Template — copy it, keep the four headings, delete what does not apply:

```
## YYYY-MM-DD — one line on what this session was about

**Landed.** What is different now, in plain terms. Not "worked on the depot" —
say what changed and where. Name the files you touched if it is not obvious.

**Gates.** check.sh: PASS/FAIL. test.sh and smoke.sh if you ran them, and what
they said. If you did not run one, say so rather than leaving it blank.

**Needs the human.** Anything to verify in-editor — scene wiring, inspector
values, a look at the thing in-game. This is the most valuable line in the
report; it is the one that used to die in chat scrollback.

**Blocked / next.** What you would do next, and anything stopping you.
```

Two things worth saying out loud, because they are the reports the coordinator
most wants and least often gets:

- **Say when something is unverified.** "Built it, did not run it" is a useful
  report. "Done" when it was never launched is not.
- **Say when you were wrong.** A reversal recorded here saves the next agent
  from repeating it. The rover collision shape that was built, regressed
  `test_vehicle` and got reverted is exactly that kind of thing.
---


## 2026-10-26 (seventh) — the bark family: K13, K14, K15, K18

**Landed.** Four approved rows, all `BarkDirector` / `Bark`, taken as one
session because fixing them separately is three visits to the same file.

- **K13(a)** — the NCO bonus is **removed, not repaired**. NCOs are deprecated
  and it compared `squad.nco` to the speaker, which is a `Bark` node and never
  the NCO body, so it could not fire. Measured 0 against 1000 before, **0 both
  ways** now. Nearest-to-camera was already the live rule, so **nothing
  audible changed.**
- **K13(b)** — `_channel_for` walks up from the Bark to the body for a faction,
  the way `Bark._resolve_squad()` already walked up for the squad. It still
  asks the speaker first, since the director does not require its speakers to
  be Barks.
- **K14** — the shuffle bag's seam guard, and it was **worse than the row
  said**. Clips are drawn with `pop_back()`, so the next one out is the back;
  the guard tested `bag[0]` and then moved the front **to the back** — so
  whenever it fired it put the just-played clip directly into the next draw.
  A *guaranteed* repeat, not a doubled chance.
- **K15** — the comment claiming reload is "filtered out for friendlies in the
  BarkSet", which was false: one BarkSet, nine reload clips, no filter.
- **K18(a)** — a paused tree no longer swallows `DOWNED`; it goes straight to
  the comms log, friendly only, no audio. **K18(c)** — `reset()` is called
  from `World.load_next_level`; it had only ever been called by the Laboratory,
  so cooldown stamps crossed levels and the dictionaries grew all session.

**I measured instead of asserting, twice.**

`probe_hud_facts.gd`'s squadless-channel line used to read as a standing fault.
It builds a Bark under a real soldier body, and that chassis defaults to
`Factions.ENEMY` — so after the fix it still printed HOSTILE, which was now
the *right* answer for the right reason. **One answer proves nothing there**,
so the probe asks from both sides and reports `ENEMY -> HOSTILE` and
`PLAYER -> FRIENDLY`.

And the new `test_barks` seam check is **seeded, over 400 draws and 50+
seams**, because the bug is probabilistic — a single-seam test would have
passed half the time with it still in. **A/B'd:** restoring the old guard
fails it at draw 4, exit 1.

**K18(b) is instrumented, not answered, and that is deliberate.** The row says
measure before changing it, and the honest measurement **is not available
headless**: `_in_earshot()` returns true when there is no camera, so a
headless run has no 55 m bound at all and would overstate contention freely.
So the change is a counter — incremented only when a candidate meets a slot
held by a *different* squad — which `reset()` reports at level unload and
which stays silent at zero. **It needs one real played session with a window.**

**Gates.** `check.sh --changed` **PASS** (80 scripts). `bucket.sh frames`
**PASS — 29 suites**. `bucket.sh campaign` **PASS — 43, 1 parked**.
`smoke.sh` **PASS**, booted clean 15 s. Not run: kit, shell, terrain.

**Needs the human.** **`Env/world.gd` is SHARED and I edited it** — one line
plus its comment, calling `BarkDirector.reset()` after the deload in
`load_next_level`. And K18(b) above wants a played session; the instrument is
already in and will print itself.

**Blocked / next.** Giving you the cleaned-up board and the outstanding
questions, as asked.

## 2026-10-26 (sixth) — K32, and two holes it found in K12

**Landed.** Every spending control in the squad manager now says **which**
reason it is shut for. The rule is written **once** — `Kit.spend_colour()` and
`Kit.gate_spend()` in `ui_kit.gd` — rather than copied onto three pages, which
is how the wording drifts and how the fourth control gets missed. The field
outranks the price, and out there the price is not mentioned at all. DIM in the
field, never PROBLEM: being on an operation is not an error.

Applied to **OPEN LINE, BUILD, ADOPT MK, RESEARCH** (Factory), **SCRAP,
REBUILD** (squad page) and **LOAD / UNLOAD** on both of the memory page's lists.

**Two corrections to the ticket's own scope, both from reading the code.**

1. **UPGRADE and MODULE are navigation, not spending.** They open the line
   detail page, and `factory_page` already records the decision that looking is
   always allowed — *"a line you cannot afford yet is exactly the line you want
   to read"*. The row listed them; I left them alone deliberately.
2. **K12's gate had two holes.** `uninstall_software()` and `repair_soldier()`
   were ungated. The first is inconsistent on its face — I gated
   `refund_supply()` in K12 on the reasoning that freeing compute is the same
   currency, and uninstalling a program does exactly that. The second is plain
   spending: it writes a `repair:` allocation. Both now refuse in the field,
   both are A/B'd in `test_ledger` (**195 checks**), and the field's own repair
   is untouched — the Mechanic's tool is `apply_healing()`, which costs nothing.

**No deadlock with the over-allocation gate**, which I checked rather than
assumed: losing a site can leave the ledger under and `mission_exit` refuses to
deploy until it is cleared, but that check runs **before** `begin_deploy()`, so
`in_field` is still false and freeing compute at base is exactly as available
as it ever was.

**Gates.** `check.sh --changed` **PASS** (84 scripts). `bucket.sh campaign`
**PASS — 43 suites, 1 parked**. `bucket.sh frames` **PASS — 29**.
`test_ledger` 195 checks, up from 189. Not run: kit, shell, terrain —
untouched.

**Rendered all three pages in the field at 1920×1080 and opened them.**
`shot_squad_manager.gd` now shoots the squad and memory pages in the field as
well as the Factory: photographing only the page that was worked on is how the
other two ship looking available and playing *denied*. The memory page's ledger
line also reads correctly now (`0 LOADED · 0 IN SEATS · 4 FREE OF 4 COMPUTE`),
which is the K11 collateral fix visible on screen.

**Needs the human.** Nothing to check in-editor. `ui_kit.gd` is shared across
the three squad-manager pages — I added two statics to it and changed no
existing behaviour there.

**Blocked / next.** **Correction: I first wrote "the READY queue is empty" here, and that was wrong** — the `## Now` list was empty, the BOARD is not. ~58 rows are still open and many are READY. Continuing through them; what genuinely needs decisions
from you — see the cleaned-up list in chat.

## 2026-10-26 (fifth) — D9 + RB6: the last domain doc

**Landed.** [[Reference/Movement and navigation]] — **D1–D9 are now all
written, and all nine carry a `verified-by` probe.** D9 and RB6 were the same
ticket from two sides and closed together.

New tool: **`tools/probe_movement_facts.gd`**, which the note names in its
`verified-by`. Nothing is instantiated — every answer comes from
`GDScript.source_code` and `SceneState`, the same bargain `probe_body_facts`
makes. It reports three things that rot silently: how big the layer is, who
overrides it, and **every authored number beside what each scene pins.**

**I re-measured rather than inheriting the row's figures, and they moved.** The
layer is **898 lines of function body across 21 entry points, 15% of the
file** — the row said ~1,040 and ~18%. The difference is that the probe counts
bodies only, which it says in its own output rather than leaving the reader to
wonder. `Reference/The robot body`'s subsystem table now carries the measured
number with a note that it supersedes the estimate.

**Three findings the ticket did not predict.**

1. **Seven of the 24 body scripts replace part of how they move, not three.**
   `spotter_drone`, `enemy_helicopter` and `diver` replace all four movement
   entry points; `rover` and `reclaimer` replace `move_along_nav`;
   `enemy_nest` and `enemy_watcher` make it a no-op. The load-bearing one is
   `off_navmesh_is_normal()` — it means *no adrift rescue and no drowning*,
   and it is as true of the Diver underwater as of the Drone in the air, which
   is why the probe labels it "off-mesh by design" rather than "flies".
2. **`step_height` and `step_forward` are the only authored numbers in the
   whole layer that disagree with their defaults.** `drayman` and
   `vehicle_rover` pin **0.75 m / 0.9 m** against 0.45 / 0.35 — the two
   wheeled frames climb higher lips and reach further past them than anything
   on legs. Authored, not drift.
3. **Ten scenes pin every budget and threshold at exactly today's defaults**,
   so editing a default in `enemy.gd` would move only the other 17 and nothing
   would report the split. This is the same trap A1 turned up on the LOD
   distances two entries ago, so the probe now does the default-vs-scene
   comparison for **every** export in the layer rather than for the one I
   happened to suspect.

**A1's handover honoured.** The nav-budget mechanism (both pools, the twins,
the per-robot interval) is in the new doc; the *trap* stays in
[[Atlas/Robots and AI]]; both notes now point at each other and neither
repeats the other. `move_and_slide` is named as **still unmeasured** under its
own heading rather than quietly left out.

**Gates.** `check.sh --changed` **PASS** (78 scripts). `bucket.sh frames`
**PASS — 29 suites**. The probe exits 0. **No game code changed** — this
ticket added one tool and wrote vault notes. Campaign, kit, shell and terrain
not run: nothing they cover was touched.

**I corrected my own probe twice before trusting it.** The first version
flagged `move_speed` as "DISAGREES WITH THE DEFAULT" across eighteen values —
which is noise wearing a warning's clothes, since move_speed is *meant* to
vary per chassis. It now marks each export as uniform-or-per-chassis and only
flags the uniform ones, and names the offending scenes instead of printing a
value histogram. The second was the "FLIES" label on the Diver.

**Needs the human.** Nothing to check in-editor. One thing worth knowing: the
doc records that **`move_and_slide` has never been timed**, so "movement is
expensive" is still a guess about the one call nobody has measured. That is a
`bench_ai.gd` job and a real one.

**Blocked / next.** K32 (the Factory's card buttons in the field). K31 needs a
design call. The board has no description work left on it.

## 2026-10-26 (fourth) — A1: the think/LOD mechanism, written down

**Landed.** [[Atlas/Robots and AI]] went **97 → 243 lines**. The new section is
*How often a robot decides anything*, and it is the mechanism the row said was
missing — the note's culling section covered the traps and nothing described
how the thing works. **Extended the Atlas note rather than writing beside it**,
which the row required: D8's stated risk, "a second doc would disagree with
it", is this project's signature failure.

Written by reading `enemy.gd:582`, which carries a banner over **174 lines and
16 `THINK_` constants** before a single function. Covers:

- **Thinking is sliced, acting never is** — and why `_tick_los` is on the
  *acting* side, which it was not at first: sliced, the Laboratory found rifle
  troopers losing ~a quarter of their damage against leapers, and 4 hoppers vs
  4 rifles going from ~33% to ~55% ally wins.
- **What `lod_scale()` returns** — 1.0 inside 35 m, lerping to 4.0 at 80 m,
  always 1.0 for your own commanded robots, and measured to the player's **eye**
  rather than to the nearest hostile, which is deliberately the opposite
  question from the distance cull.
- **The three tiers and their floors**, combat as the *cheap* tier (12×, capped
  at 0.35 s), the three watched moments, and the self-tuning budget with both
  its guards — `_think_pressed` (the frame must be late AND thinking be part of
  why) and `THINK_OVERDUE`.

**Two facts nothing in the repo stated, both derived and checked.**

1. **`lod_scale() > 2.0` means "further than 50 m."** That idiom gates three
   unrelated behaviours — the up-to-four sidestep raycasts per shot, the
   Rover's rig, the Reclaimer's tilt — and the distance falls out of the lerp
   and is written down nowhere.
2. **Those three distances are `@export`s that 10 of the 27 scenes in
   `Character/characters/ai/` pin** (`bastion`, `brood`, `bulwark`, `drayman`,
   `kite`, `lance`, `picket`, `see_engine`, `tick`, `vessel`). All ten match
   today's defaults, so nothing disagrees — but editing the script default
   alone would move the other 17 and silently leave those 10 behind. I checked
   this *because* of the "scene values beat script defaults" invariant, and it
   would have made the 50 m figure wrong per-chassis if any had differed.

**D9 overlap resolved in one direction**, as the row asked. The nav-budget
*trap* — the `get_next_path_position` / `is_navigation_finished` twins, and
"if you add a call to `nav_agent`, put it in `_tick_nav`" — stays in the Atlas,
where people trip over it. The *mechanism* belongs to
`Reference/Movement and navigation`; the Atlas now carries a callout saying so
and D9's backlog row records that it inherits it, so the two cannot end up
disagreeing.

**Gates.** No code changed — this is a vault-only ticket. `check.sh --changed`
not re-run for it (nothing in the repo moved beyond the lane report).
Every figure quoted was read out of `enemy.gd` or derived and checked against
the scenes; the 50 m threshold was computed from the lerp rather than eyeballed.

**Not verified.** I did not run `bench_ai.gd` — the note now points at it as
the tool for this area, and I am repeating its documented behaviour and the
Laboratory numbers already recorded in the source comments rather than
re-measuring them. If any of those comments is stale, so is the note.

**Blocked / next.** D9 (with RB6), then K32. K31 needs a design call.

## 2026-10-26 (later still) — K11b: lose the location, lose the compute

**Landed.** The human settled K11b the day it was raised: *"if you lose a
location you should lose the compute."* A first clear no longer claims
`compute_reward`. A claim can never be taken back — `compute_claimed` has no
un-claim — so first clears were **29 compute across the board that outlived
every site that earned them**, against 12 for holding the whole map.

**There is now exactly one source of compute in a campaign:** `starting_compute`
(2) plus `Location.compute` for whatever you hold this minute. A ceiling of 14,
and 12 of it can be taken off you.

- `extract()`'s first-clear claim is gone; `MissionDefinition.compute_reward`
  stays in the data unread, as K9 left the objective rewards.
- `_pay_compute_owed()` — which back-paid first clears on load, as a migration
  for pre-compute saves — is now `_release_orphaned_software()`. Back-paying
  would have handed an old save the exact 29 this removed. Renamed rather than
  gutted: a function called `_pay_compute_owed` that pays nothing is a name the
  next person reads instead of the body.
- New `compute_total()` = `compute_earned + site_compute()`. `compute_free()`,
  the memory page and the garrison all read it.

**The half of this that was not about the player's wallet, and nearly shipped
broken.** `ForceGenerator.garrison_supply()` is `GARRISON_BASE + compute ×
GARRISON_PER_COMPUTE`, and its own comment calls those two numbers *"the entire
difficulty curve of every defence in the game"*. It read **`compute_earned`** —
which, after this change, nothing adds to after the seed. Every defence in the
game would have sat at its opening strength for the whole campaign, for ever,
and no suite asserts the shape of that curve. It reads `compute_total()` now,
and `GARRISON_PER_COMPUTE` went **1.0 → 2.3** because the input's ceiling fell
from 31 to 14: `8 + 14 × 2.3 = 40` puts §6's authored endpoints back where they
were. Probe: holding one Location gives a garrison of **15** against an 18 raid
(you bleed), the whole board gives **40** (you hold).

Files: `Campaign/campaign.gd`, `Campaign/campaign_state.gd`,
`Campaign/force_generator.gd`, `Campaign/mission_definition.gd`,
`Character/hud/squad/memory_page.gd`, `tools/probe_economy_facts.gd`,
`tools/test_ledger.gd`, `tools/test_turn_loop.gd`, `tools/test_enemy_turn.gd`.

**Gates.** `check.sh --changed` **PASS**. `bucket.sh campaign` **PASS — 43
suites, 1 parked**. `bucket.sh frames` **PASS — 29**. `bucket.sh shell`
**PASS — 4**. `smoke.sh` **PASS**. Not run: `kit`, `terrain` — untouched.
Nothing rendered this time; no UI changed beyond one derived number on the
memory page.

**Two suite failures that were the suites, not the game.** `test_turn_loop` and
`test_enemy_turn` each hardcoded a compute figure chosen to land raids inside
the doubt band under the OLD formula (`8 + compute_earned × 1.0`). Both now
derive it from `GARRISON_BASE` / `GARRISON_PER_COMPUTE`, so the next balance
pass moves them with it instead of rotting. `test_enemy_turn`'s numbers now
match §6 exactly: ratio 2.22 at act 1, 0.87 at act 3.

**A failure mode worth more than the fix.** Renaming `_pay_compute_owed`
left `test_ledger` calling a method that no longer existed. On an untyped local
that is a runtime error which does **not** stop the suite — so five checks
silently stopped running and the suite printed **`PASS  189 checks`** where the
previous run said 191. Green, exit 0, not zero checks, nothing for `bucket.sh`
to fire on. Only comparing the counts caught it. **Read the number, not just
the word.** In [[Traps]].

**Needs the human.**

- **`GARRISON_PER_COMPUTE = 2.3` is a balance constant I changed, and it is
  unplayed.** I raised it to PRESERVE the documented 8→40 curve rather than to
  alter it — leaving it at 1.0 would have capped the best garrison in the game
  at 22 against an 18 raid. But it is still a number nobody has felt, and it is
  yours to retune.
- **The curve has a new property: your garrisons weaken as you lose ground.**
  That follows from compute being territory. It may be exactly right, or it may
  be a death spiral — a bad run now compounds. Raised in [[Open]].
- **Compute is now very scarce: a ceiling of 14 against seats at 1 each.**
  Starting `supply_cap` is 4. Nothing else changed about prices.
- Nothing to check in-editor. All script.

**Blocked / next.** A1 — the think/LOD mechanism into [[Atlas/Robots and AI]] —
which I am starting now. Then D9/RB6, then K32.

## 2026-10-26 (later) — the economy loop: K9, K11, K12, K17

**Landed.** Four decisions from 2026-10-23, all in the campaign layer, built
as one session because they all sit in `extract()` and `campaign_state.gd`.

- **K11 — held Locations pay their compute.** `compute_free()` is now
  `compute_earned + site_compute() − held`. It was `earned − held`, and that
  was `site_compute()`'s only possible caller, so the 12 compute on the board
  was credited to nobody. Probe, taking Hillfort: **`compute_free()` 2 → 2
  before, 2 → 3 after.** Collateral, found by looking: `memory_page.gd` derived
  its LOADED figure as `compute_earned − free − seats`, which becomes
  "programs minus ground" and goes negative the moment you hold anything — it
  now counts off the ledger, and the total it is "of" includes held ground.
- **K17 — income is paid after the mission.** `advance_turn()` moves time and
  nothing else; the new `pay_income()` pays and returns the figure; `extract()`
  calls it after `set_site_owner(… PLAYER)`. Probe: `advance_turn()` read
  `earned 1000 → 1008`, now reads `1000 → 1000` with `pay_income()` doing the
  8. **The ordering question in the ticket, settled: after the enemy's move as
  well.** A site they take in the same turn pays you nothing for it. Paying
  before their move would have meant hoisting the capture above
  `EnemyTurn.play()`, which lets them raid ground you just took — a bigger
  change than the row asked for.
- **K9 — objectives pay nothing.** Both payouts out of `extract()`. The
  exports stay in the data with a block saying why; `ObjectiveTracker`'s two
  getters stay and are marked reporting-only, since `probe_mission_facts`
  reads them. `result["objective_reward"]` stays a permanent 0 so the debrief
  row never appears, the way `unlocked` already does.
- **K12 — nothing is bought in the field.** Twelve functions on
  `CampaignState` ask `_refuse_in_field()` and warn when they refuse. The gate
  is in the state, not the buttons. `in_field` is **not saved and not
  restored**; `Campaign.in_mission` mirrors onto it through a **setter**,
  because `in_mission` has six assignment sites and a hand-maintained mirror
  goes stale at one of them.

**Also:** `bucket.sh` had a hole — its "a suite that asserts nothing is a
failure" guard was a word search for `PASS`, so it was satisfied by a suite's
own `PASS  0 checks` summary. That is exactly the result that fooled me during
the save pass. Fixed and **proved by tripping it**: a throwaway suite printing
that line turned the bucket from green to `FAIL … (zero-checks)`, then
deleted. `test_ledger` got the same in-suite guard.

Files: `Campaign/campaign_state.gd`, `Campaign/campaign.gd`,
`Campaign/mission_objective.gd`, `Campaign/objective_tracker.gd`,
`Character/hud/squad/factory_page.gd`, `Character/hud/squad/memory_page.gd`,
`tools/bucket.sh` (**shared**), `tools/test_ledger.gd`,
`tools/test_campaign_spine.gd`, `tools/test_endings.gd`,
`tools/probe_economy_facts.gd`, `tools/shot_squad_manager.gd`.

**Gates.** `check.sh --changed` **PASS** (89 scripts). `bucket.sh campaign`
**PASS — 43 suites, 1 parked** (`test_tutorial`). `bucket.sh frames`
**PASS — 29 suites**. `bucket.sh shell` **PASS — 4 suites**. `smoke.sh`
**PASS**, booted clean 15 s, 1 warning. `test_ledger` 191 checks (was 170; +21
is the new field-gate A/B). Rendered `live_factory_in_field.png` at 1920×1080
and opened it. **Not run:** `kit`, `terrain` — nothing in either was touched.
`test.sh` not run; it still cannot finish.

**I shipped a bug and the render caught it.** Folding "in the field" into the
seat button's `enough` flag made it read **`NEEDS 1 COMPUTE` under a header
showing `COMPUTE 4`** — the screen telling the player something untrue. A
structural probe would never have seen it. The field is now a separate reason
with its own words (`NOT IN THE FIELD`). This is the argument for item 3 of
the Definition of Done in one picture.

**Needs the human.**

- **Nothing here has been played, and this is a large balance change.** K9
  alone removed **9,490 resources and 11 compute** — the biggest income in the
  game. What still pays one-off is **9,035 resources and 29 compute**; holding
  the entire board pays **230 a turn and 12 compute**. Those four figures come
  off `probe_economy_facts.gd`, not from arithmetic in my head.
- **A defence mission now pays nothing at all** beyond salvage. Its whole
  reward is keeping the site's income. That follows from the decision and may
  still be wrong to feel.
- **K11b — a decision I did not take.** First-clear compute totals **29 and is
  permanent** (nothing un-claims it, so losing every site still leaves you all
  29) against **12** for holding the whole board, and a capture pays both at
  once. That makes "for as long as you hold it" a top-up on a larger permanent
  reward. It is a balance call; it is in [[Open]] and as Backlog K11b.
- **`over_allocated()` is now reachable without a requisition** — losing a site
  can put the books under on its own, which is what `site_compute()`'s comment
  always said should happen. `mission_exit.gd` then refuses to deploy with
  `REQUISITIONED — FREE n COMPUTE`, naming a cause that may not be the real
  one. Nobody has hit it in play.
- Nothing to check in-editor: no scene or inspector changes, all script.

**Blocked / next.** Per the rewritten `## Now`: A1, then D9/RB6, then **K32**
(the Factory's card buttons still look live in the field — refused by the gate
and legible only from the line across the top; doing it right means the same
reason-separation at ~6 sites, which is why it is its own ticket). K31 and
K11b need design calls.
## 2026-10-26 — the save pass: SV1, SV2, SV3, SV4, SV6

**Landed.** Six files, one of them new, all in the campaign layer and its
tools. **`Campaign/campaign_state.gd` is the only game code touched.**

- **SV1 — a load now restores the whole campaign.** `restore_from()` moved 22
  of `to_dict()`'s 29 fields; the seven it forgot were `line_marks`,
  `line_modules`, `turn`, `sites`, `under_attack`, `under_attack_turn`,
  `lessons_seen`. It has three callers and only one of them is the rewind:
  `load_profile` and `new_profile` both go through it, so **every boot came up
  at turn 0 on the authored board with every production line at Mk 0, and the
  next autosave wrote that over the file** — and a new campaign inherited the
  same seven from whatever was open. All 29 move now.
- **Two things fell out of SV1.** `from_dict` now `duplicate()`s `line_marks`
  and `line_modules`, which were being handed out still shared with the JSON
  parse exactly as `sites` had been — restoring one snapshot into two states
  gave them one dictionary. And **a mark or module adopted in the field is now
  undone by a failed run**, where before the line kept it while every record
  went back to Mk 0 kit; the rewind is self-consistent now. Measured:
  `probe_economy_facts.gd`'s rewind table reads `line mk 0` in both rows.
- **SV2 — no state is born pointing at the legacy save.** `save_path` defaulted
  to `SAVE_PATH`, `user://campaign.json`, and only `Campaign._ready` blanked
  it, so `reset_campaign()` and all forty-odd tools and suites that build a
  state directly were aimed at a real campaign. Default is `""` now.
  `load_dict` / `load_from_disk` lost the same default and require a path —
  **audited, every caller already passed one**, and the one tool that writes a
  campaign without `save_to_disk` (`make_board_campaign.gd`) uses its own
  `FileAccess`. `SAVE_PATH` is now read by **no code**; the live path to the old
  single save is `SaveSlots.LEGACY`.
- **SV3 — the test that could not fail is replaced.** New suite
  **`tools/test_restore_from.gd`**, `# BUCKET: campaign`, no world, 14 checks:
  both restore directions into a state that was never that campaign, the move
  list read out of the source against `to_dict()`'s keys, that a restore does
  not move the campaign's file, SV2, SV4, and the shared-dictionary trap.
  `test_endings` keeps its self-restore — a fair check of *that* campaign's
  rewind — with a comment saying it is not the guard, plus one restore into a
  different state.
- **SV4 — `last_played_utc` is stamped** in `save_to_disk`, after the file
  opens. The profile menu sorts on it and nothing had ever set it, so
  most-recent-first was really the file's mtime and any tool that touched a
  save moved it to the top of the player's list.
- **SV6 — `migrate()` is deleted.** It warned about a newer save and returned
  its argument. The warning moved into `load_dict` where the path can be named;
  `is_outdated()` is the whole gate; the comment where the function was says
  why there is none. **`load_from_disk` now goes through `load_dict`** instead
  of being a line-for-line second copy of the same open-parse-gate sequence —
  every failure answer unchanged, all null before and after.
- Three probes had stale claims about the gap and were corrected:
  `probe_save_facts.gd` (§4 rewritten for the deleted `migrate`),
  `probe_economy_facts.gd` (a **hardcoded** list of the seven fields printed as
  "by reading it" — now derived) and `probe_squad_facts.gd` (§5's whole finding
  was this bug; it now reports whether the line and the record agree, and says
  SV1 has reopened if they do not).

**Gates.** `check.sh --changed`: **PASS**, 84 scripts. `bucket.sh campaign`:
**PASS, 43 suites**, 1 parked (`test_tutorial`) — including `test_restore_from`
at 14/14 and `test_endings`' two restore checks green. `bucket.sh shell`:
**PASS, 4 suites**. `smoke.sh`: **PASS**, booted clean for 15 s, 1 warning
line. `probe_save_facts.gd`: `NOT MOVED (0)` in §2 and **0 / 0 / 0** in §3,
against `NOT MOVED (7)` and 7 / 7 / 7 on the same probe before the change.
`probe_squad_facts.gd` and `probe_economy_facts.gd` both exit 0.

**The suite was A/B'd, because a suite that cannot fail is the bug it was
written about.** Deleting `turn = was.turn` from `restore_from` turns
`test_restore_from` red 4 of 14, exit 1 — caught in all three ways, in both
directions.

**Not verified.** The frames, kit and terrain buckets were not run; nothing
outside the campaign layer was touched. **Nothing was played**, so this says
the save works and says nothing about how the game feels. The v3-in-a-v2-build
path (SV5) is still only reasoned about — the warning was moved, not tested
against a real v3 file, because there is no such build. And the **three capture
cores** still want your eyes; unrelated to this, still waiting.

**I was wrong about one thing, from the ticket's own instruction.** SV3 said to
give `probe_save_facts.gd` a `# BUCKET:` line so the gap would be asserted.
`bucket.sh` only ever globs `tools/test_*.gd`, so that would have done exactly
nothing — a tag nobody reads on a probe that asserts nothing. Hence a suite
instead. The row now records the correction.

**Needs the human.** **No scene or inspector work** — this is all script. Two
things to look at in GitHub Desktop: the field list in `restore_from` (29
assignments, and `lessons_seen` among them is the one line that reverses an
earlier comment, which the comment now explains), and the **deletion** of
`migrate()` with `load_from_disk` collapsed onto `load_dict`. Nothing was
committed.

**Blocked / next.** `SAVE_PATH` can be deleted now that no code reads it, and
`SaveSlots.adopt_legacy()` may be able to go with it — both are **your call**,
and the second one is a decision about somebody's old campaign, not a cleanup.
Both are logged as open questions in the vault. Next on the board is the economy loop: K17, K11, K9 and
K12's field-purchase gate, all decided, all in these same files.


## 2026-10-26 — K25: eleven cast-failure orphans, and the recoilless makes one of them real

**Landed.** Nine files, **all game code**, and **four of them are shared
ground**: `Env/world.gd` (every level load goes through it), `Managers/lab.gd`,
`Character/characters/ai/enemy.gd` and `Env/world_objects/chassis_hologram.gd`.
The others are `Campaign/squad_spawner.gd`, `Character/components/rank_kit.gd`,
`Character/components/squad_commander.gd` (two sites),
`Character/weapon/hatchling/hatchling_payload.gd` and
`Character/characters/ai/equipment/ai_grenade.gd`. **No `.tscn` or `.tres` was
touched.** Every one takes the house form from
`Campaign/enemy_force_spawner.gd:415-418` — instantiate untyped, cast, `free()`
the untyped one if the cast failed — and **every bail now warns**, which it did
not before in four of the eleven.

**The one that matters is reachability, and it is one authored row away, not
dead.** `Campaign/items/item_rocket.tres` is **`kind = EQUIPMENT`** with an
`ai_scene` of `ai-wep_recoilless.tscn`, which is an **`AIWeapon`, not an
`AIEquipment`** — and **neither builder of an equipment slot checks the kind**:
`squad_spawner.gd:319` asks `fits_ai()` only, and `enemy_loadouts.gd:420` asks
nothing but `ai_scene != null`. So the three `as AIEquipment` casts are not
guarded by their callers at all; they are guarded by the fact that no
ChassisMark, line spec or enemy spec currently names the recoilless in an
equipment list (checked repo-wide; the only place that does is
`tools/test_equipment.gd:370`). Put it on one robot and
`Enemy._evaluate_equipment_use()` orphans a whole weapon scene **every 1.5 s of
combat** (`EQUIPMENT_RECON_TIME`), for as long as the fight lasts. That gap is
its own defect and is **reported, not fixed** — see [[Backlog]].

**Measurements.** A throwaway `--headless --verbose` harness drove nine of the
eleven bail paths directly and freed everything each path is supposed to own,
against a **control arm** doing the same work and orphaning nothing.

| arm | leaked instances | resources still in use | RIDs | exit |
|---|---|---|---|---|
| control | 0 | 0 | 0 | 0 |
| **before** | **405** | **180** | **15 `CanvasItem`** | **139** |
| after | 0 | 0 | 0 | 0 |

Named in the before log: `scan_effect.tscn`'s three `ShaderMaterial`s, the whole
of `soldier_rifle.tscn` (meshes, shapes, `robot_metal.tres` and its three PNGs),
`Frag_West.fbx`'s four materials, `explosion.tscn`'s materials and shapes,
`tracer.tscn`, `spark_burst.tscn`, `oil_spray.tscn` and the `soldier.gd`,
`rank_kit.gd` and `scan_effect.gd` scripts. Harness deleted.

**Gates.** `check.sh --changed` **PASS** (81 scripts, 51 scenes). `smoke.sh`
**PASS** (booted clean, 15 s, 1 warning line) — run because `world.gd` is on the
boot path. **All five buckets green, exit 0 each:** `campaign` **42** (1 PARKED,
`test_tutorial`) 5m36s; `frames` **29** 8m26s, slowest `test_mortar` 63 s, and
**`test_nest` did not flake this time**; `kit` **16** 2m39s; `terrain` **13**
(3 report-only, 1 PARKED) 4m46s; `shell` **4** 26s. `test.sh` not run — it
cannot finish here.

**Needs the human.** Nothing in the editor; no scene or inspector value changed.
Two judgement calls are yours: (1) whether the catalogue kind gap above is a
catalogue fix (`recoilless` should not be `kind = EQUIPMENT` with a weapon
scene) or a builder fix (filter on kind in both builders) — I left it alone
because it changes what gets filtered; (2) `Env/world.gd`'s new bail
**releases the `PauseHold`** before returning, which it must, or a bad level
scene leaves the game paused for good — worth a second pair of eyes because
that file is on every level load.

**Not verified.** **No render.** Nothing on screen changes on today's authored
data, and that is measured rather than assumed: an audit arm instantiated and
class-checked every candidate and **all of them pass the cast** — 19 `_level`
scenes are `TrenchBroomLevel`, 27 chassis definition scenes are `Node3D`, 11
baked hats are `Node3D`, `squad.tscn` is a `Squad`, both grenade projectile
scenes are `AIGrenadeProjectile`. So the only new artefact in the live game is a
warning line. **`Env/world.gd:79`'s own bail was not driven** — a cast failure
there used to error on `add_child(null)`, and a runtime error under `--script`
hangs rather than exits, so there is no pre-fix leak report to produce for it;
same for `chassis_hologram` and `lab.gd`, of which only `chassis_hologram` could
be driven after the fix. **Game feel and balance: not assessed.** I did not play
it.

**I was wrong about one thing, from the brief.** K25's row says
`squad_commander.gd:1013` "is polled several times a second, so this one
repeats". It does not: `_dials[squad]` caches the answer, and the comment two
lines above the leak says so — the orphan is **once per distinct item per
squad**, not per poll. The site that actually repeats on a timer is
`enemy.gd:3876`, at 1.5 s.

**Blocked / next.** Nothing blocked. K25 closes the **K22 family** — K24, K26,
K27, K28 and K25 are all done. The two loose ends it leaves are the catalogue
kind gap above and `K30` (`ai_world_weapon_drone bomb.gd`), which K26 already
raised.

## 2026-10-26 — K27: eight tool-path orphans. Four of the eight were exiting 139 on their normal path

**Landed.** Eight files, all under `tools/`. **No game code, no `.tscn`, no
`.tres`, no shared runner.** Two of them — `tools/level_split.gd` and
`tools/dress_pittsburgh.gd` — **are TERRAIN's territory**; flagging that
explicitly. Every verdict below is an A/B of the pre-fix file (a copy of HEAD,
driven on the real path, deleted afterwards) against the fixed one, read off
`--headless --verbose`, not off the exit code.

- **`level_split.gd`** — `art` at `:103` holds the level's whole art subtree
  and `level` at `:57` is a second unparented orphan; neither was freed on any
  of nine exits. New `_shed(level, art)` on every one, **dry run included**.
  Dry run on `hillfort_wip_level`: exit **139**, 3195 leaked instances, 756
  leaked RIDs across 8 server types → **exit 0, 0 leaked**, identical report
  (953 nodes moved). `free_bases(bases)` at `:110` was already correct.
- **`reinstance.gd`** — `scene` at `:43` leaked on all three exits, and the
  base cache with it: `reown()` fills it at `:45`, *above* the dry-run exit,
  so the `free_bases()` at `:67` only ever covered `--apply`. New `_shed()`.
  Exit **139**, 1748 leaked instances, 427 resources still in use → **exit 0,
  0/0**.
- **`dress_pittsburgh.gd`** — the `{}` the ticket named at `:257` is
  **unreachable without a writing run**: the dry run returns two lines above
  it, so that cache only fills under `--apply`, which rewrites
  `pittsburgh_art.tscn`. Named and freed anyway. The leak that *is* on the dry
  run is `art` at `:199`, the whole Pittsburgh art scene: exit **139**, 2774
  leaked instances, 574 resources still in use → **exit 0, 0/0**, identical
  placement (170 placed, 241 refused).
- **`bake_hats.gd`** — `out` at `:116` freed on all three exits. This is the
  clean-exit case: **exit 0 both before and after** while leaking 222
  instances, 11 `Headgear` holders, 7 materials and 2 `Resource still in use`
  on real texture PNGs → 0/0, same 100 meshes across 11 hats. Measured on a
  copy with `OUT_DIR` redirected to `user://`, so **the shipped hat scenes
  were not rewritten**.
- **`shot_bunker_arrival.gd`** — `level.free()` on the missing-slice bail at
  `:83`. One mistyped slice name orphans a whole level *per yaw*: exit **139**,
  5507 leaked instances, 471 resources still in use, 14 RID classes → **exit
  0, 0/0/0**.
- **`test_viewmodel_poses.gd`** — the line the ticket named (`:77-78`, not a
  PlayerEquipment) **cannot fire**; all 13 scenes have `update_view`. Its
  sibling two lines down (`vm == null`) **fires on every run** on
  `scanner_hud_weapon.tscn` and leaks the whole scanner: `Node3D "Scanner"`,
  `Node3D "ScannerTool"`, three `AudioStreamPlayer3D`, and 6 `Resource still
  in use` (3 GDScripts, 3 WAVs). Both bails now `item.free()`, copying the
  comment the success path at `:120` already carries. 18 + 6 → **0 + 0**.
- **`test_same_site_ride.gd`** — both `_Pad` stubs freed. See below.
- **`probe_piece_bounds.gd`** — `instantiate() as Node3D` replaced with the
  untyped-then-cast form from `enemy_force_spawner.gd:415-418`. Reachable
  straight from the `SCENE` argument: a Control-rooted scene left 15 leaked
  instances and 4 resources still in use → **0/0**.

**The open question, answered.** *Does a script-only orphan with no mesh or
texture trip the sweep?* **Yes, but only its mild half.** Four control arms: a
bare orphan `Node3D` = 1 leaked instance / 0 resources still in use; the same
with an inner-class GDScript = 3 / 0; freed = 0 / 0; H10's own shape, a `Node`
holding a `PackedScene` in meta = 8 / **5**. An inner-class script has no
`resource_path` and a bare `Node3D` owns no server RID, so neither reaches "a
destructor frees an RID into a dead server" — which is what 139 is. Worth
freeing, never a 139 candidate.

**Gates.** `check.sh --changed`: **PASS** (73 scripts, 51 scenes/resources).
`smoke.sh`: **PASS** (booted clean, 15s, 1 warning line). `bucket.sh kit`:
**PASS, 16 suites**. `bucket.sh campaign`: **PASS, 42 suites** (1 PARKED,
`test_tutorial`). `bucket.sh terrain`: **PASS, 13 suites** (1 PARKED,
`test_terrain`; 3 report-only). The two suites I edited are unchanged in
result: `test_viewmodel_poses` **34 checks, 0 FAIL, exit 0** before and after;
`test_same_site_ride` **11 PASS, 0 FAIL, exit 0** before and after. `frames`
and `shell` not run — nothing I touched is in them. `test.sh` not run, by
house rule.

**Needs the human.** Nothing in-editor: no scene, resource or shared file was
touched. Two judgement calls worth a look. **(1)** `dress_pittsburgh.gd`'s
`--apply` path and `level_split.gd`'s `--apply` path were fixed but **not
run** — the editor is open and both write content, so the `{}`-cache fix and
the post-save `_shed()` are reasoned, not observed. **(2)** `bake_hats.gd` was
proved on a redirected-output copy; the shipped version has not been run
against the real `Character/characters/ai/hats`, deliberately.

**Blocked / next.** K25 — the eight cast-failure leaks — is the remaining
member of this family, and `probe_piece_bounds.gd` here was a ninth of exactly
that shape found inside a K27 tool. Worth re-sweeping `tools/` for
`instantiate() as ` once K25 lands.

---

## 2026-10-26 — K26: the four AI-equipment orphans. Unreachable, real when driven, and now all five say so

**Landed.** Five files, all `Character/characters/ai/equipment/`, all in
GAMEPLAY's lane. **No `.tscn`, no `.tres`, no shared file.**

- `ai_grenade.gd`, `ai_mine.gd`, `ai_smoke.gd`, `ai_deploy.gd` — the
  `spawn_host()` call is now **above** the `instantiate()`, so the
  `host == null` bail happens before there is anything to orphan. Each bail
  now `push_warning`s and names the equipment.
- The three silent `*_scene == null` returns in `ai_mine`, `ai_smoke` and
  `ai_deploy` now warn too (`ai_grenade` already `push_error`ed).
- `ai_repair_kit.gd` — **beyond the four sites K26 named**, and the one
  genuinely reachable silent return of the family: both of its early returns
  now warn. The ordered path never consults `can_use()`, so a repair the player
  points at nobody lands on "no patient", spends the charge, and
  `order_use_equipment()` returns `""` — success.

**Can the guard fire?** No, at none of the four — but *not* for K24's reason,
and that matters. `AIEquipment.spawn_host()` returns null only when the owner
is unparented **AND** the equipment node is out of the tree; those are two
different objects and nothing makes them exclusive, so unlike
`drone_bomb._explode()` the guard is well-formed. It is dead because
**`Enemy._spend_equipment()` (`enemy.gd:3913-3916`) `host.add_child`s the
equipment on the line before `execute()`**, and the only three other callers
(`test_ai_kit` ×2, `test_hatchling`) `root.add_child` it first. That is a
property of the callers, not of the guard — a weaker clearance than K24's, and
the reason the reorder was worth making anyway.

**Does it leak when driven?** Yes, all four, heavily. A/B with a throwaway
`--headless --verbose` harness (equipment and owner both unparented, everything
the path owns freed by hand, `quit(0)`), control arm orphaning nothing:

| arm | leaked instances | resources still in use | exit |
|---|---|---|---|
| control (execute() not called) | 0 | 0 | **0** |
| before the fix | **250** | **186** | **139** |
| after the fix | **0** | 0 | **0** |

Named in the leak report: `AI_Grenade_Projectile`, `ClusterMineCanister`,
`Smoke_Canister`, `Drone_Pack_Canister` — plus, from the grenade alone, the
whole of `explosion.tscn` (every Curve, CurveTexture, ParticleProcessMaterial,
mesh and the Explosion1.wav) because `ai_grenade_projectile` preloads it, and
4 classes of RID including 17 `RendererSceneCull::Instance`. **The pre-fix run
exited 139 here**, which is unusual for this family — K24's two real leaks both
exited 0 while leaking. Harness deleted.

**Also measured, and the reason the warnings are not cosmetic.**
`Enemy._spend_equipment()` runs `slot.consume()`, the cooldown and the HUD
timestamp **after** `execute()`, unconditionally — `execute()` returns `void`
and nobody asks it whether anything happened. So every early return in the kit
spends a charge on nothing, and on the ordered path the designator is told it
worked.

**Gates.** `check.sh --changed` **PASS**, twice — 83 scripts / 51 scenes on the
first run, 73 / 51 on the re-run after the `ai_repair_kit` edit. The count
dropped because another lane's files left the changed set mid-session, not
because mine did: all five are in `git diff --name-only HEAD` on the second
run, which I checked rather than assumed.
`bucket.sh frames` **PASS, 29 suites**, 8m7s, exit 0, slowest `test_mortar` at
61s. `bucket.sh kit` **PASS, 16 suites**, 2m21s, exit 0. **The frames run
predates the `ai_repair_kit` edit** — the two are independent, but rather than
assert that, I ran `test_item_facts` standalone afterwards (the only suite in
the project that references the repair kit, and a `campaign` one): **PASS,
exit 0**. `smoke.sh` not run — nothing here loads at startup. Nothing visual
changed, so no render: the only
new on-screen artefact is a warning in the log, and it is quoted above.

**Needs the human.**
- **The grenade is the only equipment with no `equipment_name`.**
  `ai_grenade.tscn` leaves the `@export` at its default `"Equipment"`, and
  `ai_emp_grenade.tscn` is an *instance* of it overriding only `grenade_scene`,
  so it inherits that too. The other five scenes all set it ("Cluster Mine",
  "Heavy Mine", "Smoke Canister", "Drone Carrier Pack", "Hatchling Charge"), so
  every warning in this family — including the pre-existing `spawn_host` one —
  reads "Equipment" for exactly the frag and the EMP. One inspector string in
  `ai_grenade.tscn` fixes both; **I did not touch a `.tscn` with the editor
  open.**
- **No suite drives `ai_grenade.execute()` at all**, nor the drone pack's.
  `test_ai_kit` covers `ai_smoke` and `ai_mine`; `test_hatchling` covers the
  `ai_deploy` script via the hatchling scene. The grenade's execute path is
  gated only by `check.sh` and by my own harness.

**Blocked / next.** `Character/weapon/ai_world_weapon_drone bomb.gd:19` —
reported, not fixed, because the fix is not one line. It
`get_tree().current_scene.add_child(new_bomb)`: a null `current_scene` errors
rather than leaking, **and parenting to `current_scene` is the
mission-outliving bug `AIEquipment.spawn_host()` and `AIWeapon._level_node()`
both exist to fix** — this is the last ordnance spawner that still does it. It
extends `AIWorldWeapon`, which has no `_level_node()`, so the fix is a new
helper or a walk up to the carrier body, not a line. Its own base class already
records that `ai_drone_bomb_weapon.tscn` is referenced by nothing, and I
confirmed that — so `fire_bomb()` is unreachable today. K27 is the next row in
this family.

## 2026-10-26 — K28: the two-levels-in-one-frame overlap, measured. It is a cleanliness issue, not a bug

**Landed.** **Nothing in `world.gd` or `lab.gd` changed** — and that is the
result, not a shortfall. The overlap K28 describes is real and I photographed
it; the walk it was supposed to poison is not inside it.

- **New: `tools/probe_level_overlap.gd`.** Brackets a real `hillfort_wip` →
  base transition using World's own `child_entered_tree` /
  `child_exiting_tree`, so it measures `load_next_level` without touching it.
  Every count is taken twice, `!= null` and `is_instance_valid`, because a
  freed node passes the first.
- **The cheap half of the row is done.** The three tools the H10 fix missed no
  longer double-call `cm.on_level_loaded()` after `await
  world.load_next_level()`: `tools/probe_order_facts.gd`,
  `tools/probe_slow_tick.gd`, `tools/shot_arena_ops.gd`. Each now carries the
  `# NO SECOND on_level_loaded()` comment copied verbatim from
  `tools/test_site_win.gd:59`, so the next reader does not put the line back.

**What the walk actually sees.** The window is exactly as described, and it is
one process frame long.

| sample | frame | World's level children | `"enemies"` returns | under the outgoing level |
|---|---|---|---|---|
| before the transition | — | 1 | 30 (30 valid) | 30 |
| incoming level enters the tree | 746 | **2** | **30 (30 valid, 0 queued)** | **30** |
| same frame, after a message-queue flush | 746 | **2** | **30 (30 valid, 0 queued)** | **30** |
| outgoing level leaves the tree | 746 | 2 | **0** | 0 |
| `load_next_level()` returned | 748 | 1 | 4 (4 valid) | 0 |

`AIManager.all_ai` after the transition: **4 entries, 4 valid, 4 under the
incoming level, 0 freed-but-held, 0 orphans.** Same for the base → mission
direction: 30 entries, 0 orphans, no stale base body.

**Why it is harmless, in four measured parts.** (1) The delete flush is at the
**end of the same process frame** as the `queue_free()`, and
`register_world_objects()` sits behind `await process_frame` + `await
physics_frame` — it ran at frame 748, two frames clear. (2)
`PauseHold.take(&"level_load")` holds `tree.paused` across the whole of
`load_next_level`, so nothing pausable ticks in the window. (3) **No physics
step falls inside the window**, so every per-tick group walk — `site_operation`,
`holdable_core`, `diver`, `drayman`, `mechanic`, `reclaimer`, `rover` — cannot
run there; I checked the enclosing function of all seven and not one is
`_ready`. (4) **Nothing in level content walks a group from `_ready` or
`_enter_tree`.** The only two in the project, `Managers/game_manager.gd:12-15`
and `Character/hud/squad_hud.gd:193`, are on persistent nodes under World and
run once at boot, and the second walks `"squads"`.

**`lab.gd:120-122` has a bigger margin.** Measured frame by frame with a
synthetic subtree: a `queue_free()`d parent's children are out of their groups
by **+1 process frame**. Lab walks the group at **+2** (`_clear_level`) and
registers at **+3**, and `_clear_level` already guards with
`is_instance_valid` and `is_queued_for_deletion`.

**One genuinely new engine fact, now in [[Traps]].** `_propagate_exit_tree`
goes **children-first**, so by the time a parent's `child_exiting_tree` fires
its descendants have **already left their groups** — the group reads 0. A
handler on that signal is therefore useless for inventorying what is going
away, and worse, it looks like proof the overlap never happened.

**Gates.** `bash tools/check.sh --changed`: **PASS**, 61 scripts, 51 scenes.
`bash tools/smoke.sh`: **PASS**, booted clean, 15 s, 1 warning line.
`bash tools/bucket.sh campaign`: **PASS, 42 suite(s)**, exit 0, 5m13s
(1 PARKED: `test_tutorial`). `bash tools/bucket.sh frames`: **PASS, 29
suite(s)**, exit 0, 8m12s. `probe_order_facts.gd`: exit **0**, which closes an
open question in `Traps` — it was carrying the H10 test bug, not a leak of its
own. `probe_level_overlap.gd`: exit **0**.

**My own mistakes, both self-reported.** (1) `bucket.sh frames` was **red on
the first run** — `test_nest`, *"...and cannot be ordered anywhere"*. The
baseline rule says any red is mine, so I chased it: green **22/22 standalone**
and green on a clean re-run of the whole bucket. It is a wall-clock check
(`await _wait(1.0)`, then assert the hive drifted < 0.1 m) with 48 hostiles
deployed, and it goes red under bucket load. Added to `Traps`. (2) The probe's
second phase originally drove lab's sequence over World's **real**
`current_level`, which frees the base out from under Campaign and the base UI
— the run **exited 139** with every line still printed, the exact H10 shape and
exactly the green-looking lie this project keeps paying for. Rewritten to use a
synthetic subtree; exit 0. The reason is in the probe's header so nobody tries
it again.

**Needs the human — one decision, and it is yours because the file is
shared.** `remove_child()` before `queue_free()` in
`World.deload_current_level()` would match the project's own written rule and
would still be correct. **The measurement does not earn it**: `Env/world.gd` is
a shared file every level load goes through, and there is no observed defect to
point at. Same for `lab.gd`. Say the word and it is two lines. Nothing to check
in-editor — **no `.tscn` or `.tres` was touched**, and no file outside
`tools/` was changed.

**Not verified.** Anything a player sees or feels during a level transition —
a flicker, a hitch, audio from the outgoing level, the HUD at the moment of the
swap. **That is game feel and it is yours**; I ran it headless, which proves it
works and says nothing about how it looks. I did not play it. I also did not
run `kit`, `terrain` or `shell` (nothing I touched reaches them) and did not
run `shot_arena_ops.gd`, which refuses `--headless` by contract — its edit is a
deleted line plus a comment and it parses, but it has not been run headful.
`probe_slow_tick.gd` was likewise not run (two 1000-frame phases); same
one-line edit, parses clean.

**Blocked / next.** Nothing blocked. K25 is the next row in the suggested
order, and `probe_home_base.gd` is still the one unmeasured 139 suspect from
the H10 family.

---

## 2026-10-26 — K24: the three instantiate-then-decide orphans, measured

**Landed.** All three K24 sites now **build the node after the guard that can
bail**, which is the form the row preferred — none of them needed a
free-on-bail, so no `queue_free()`/`free()` was added anywhere.
`Character/hud/debrief_screen.gd` `_cover()`, `Env/world_objects/site_slice.gd`
`_seat_core()`, `Character/weapon/drone_bomb.gd` `_explode()`. The drone
bomb's bail was also **silent** and now `push_warning`s, per the standing rule.
`Env/world_objects/` is **shared ground** — `site_slice.gd` is one of mine
this session, flagging it explicitly. No `.tscn` or `.tres` was touched.

**Two of the three were real; one was a false positive.** Measured, not read:
each bail path was driven directly from a throwaway `--script` harness that
freed everything the path is supposed to own, then run `--verbose`.

- **debrief_screen — real leak, unreachable guard.** Before:
  `Leaked instance: ColorRect` plus `1 RID of type "CanvasItem" was leaked`.
  After: clean. But `_cover()` is only called from `_on_extracted`, only
  connected in `_ready()`, which only runs in the tree — so `get_parent()` is
  never null in the live game, and both tools that build a `DebriefScreen`
  (`shot_ui.gd`, `test_debrief_turn.gd`) parent it first. **The row's "runs on
  every extraction debrief" is true of the function and not of the bail.**
- **site_slice — real, and the only one printing the H10 tell.** Before:
  `Leaked instance: Node3D "Hold"` plus
  `Resource still in use: res://Env/world_objects/holdable_core.gd (GDScript)`.
  After: clean. Reachable on **authored data**: `probe_site_cores` is PASS
  today, so no live map fires it, but a capture point authored with no
  `Interactible` under it does.
- **drone_bomb — FALSE POSITIVE. The guard cannot fire.** `_explode()` is only
  reached from `_detonate()`, i.e. from a contact signal, so the bomb is in the
  tree and therefore has a parent; and a bomb *out* of the tree has no
  `get_tree()`, so the `current_scene` read one line above errors before the
  guard. Measured: `current_scene = null, bomb parent = root`, Explosion
  spawned at `(1, 2, 3)`. Reordered and warned anyway — both are free.

**Worth recording: neither live site exited 139 in isolation.** Both exited
**0** while leaking. 139 needs the orphan *and* a server torn down that owns
one of its RIDs. So **a clean exit code does not clear an orphan** — the
`Leaked instance` / `Resource still in use` lines under `--verbose` are the
evidence, and they name the object and the resource path.

**Gates.** `check.sh --changed`: **PASS** (60 scripts, 51 scenes).
`smoke.sh`: **PASS**, booted clean, 1 warning line. Buckets, all five:
**campaign 42 PASS** (1 PARKED, `test_tutorial`), **frames 29 PASS**,
**kit 16 PASS**, **terrain 13 PASS** (1 PARKED `test_terrain`, 3 report-only),
**shell 4 PASS**. Nothing went red, so there was nothing to A/B against the
2026-10-26 baseline. Happy paths re-proved: `probe_slices` **0 problem(s)**,
exit 0, cores still seat on every live site; `probe_site_cores` PASS.
Note the handover's counts were a day stale — `bucket.sh --list` says campaign
**43** and terrain **14**; the 42 and 13 are what actually *ran*, the rest
PARKED.

**Looked at.** The extraction cover is the one visible thing whose build order
moved, so it was rendered **headful at 1152×648** after the change →
`docs/marketing/wip/k24_debrief_cover.png`, with the `ColorRect` logged as
parented to the DebriefScreen's parent, at `(1152, 648)`, colour
`(0.025, 0.04, 0.035, 1)`. The image is a full-screen near-black rectangle,
which is exactly what the cover is — it proves the rect still covers the
viewport and nothing else. The debrief **page** itself was not re-rendered;
`test_debrief_turn` (campaign) builds it and passes, and nothing in this change
touches it.

**Needs the human.** Nothing in-editor: no scene, resource or inspector value
was touched. `docs/marketing/wip/k24_debrief_cover.png` is new and has no
`.import` yet, so the editor will import it on its next scan.

**Not verified.** Game feel and balance — not played, not asked to.
The **drone bomb's in-game** detonation: `_explode()` was driven directly and
spawns the Explosion at the impact position, but no suite covers `drone_bomb`
at all and a quadcopter was never flown. The **debrief bail in the live
game** cannot be reached, so the fix there is defensive only. Whether any of
these three ever contributed to a real 139 in a real run is **unproven** — the
evidence is the leak report, not a crash.

**Blocked / next.** K25, K26 and K27 are the same family and all READY. The
harness recipe is three lines and is now written down in the vault's `Traps`:
call the bail path on a bare `.new()`, free what the path owns, run
`--headless --verbose`, grep `Leaked instance` and `Resource still in use`.
K26's four AI-equipment sites are worth doing for the **silent returns** even
though the row already suspects the leak never fires — exactly the shape found
here on the drone bomb.

---

## 2026-10-26 — H10's game bug fixed, and the last three stale level lists

**Landed. Two changes, and the first one turns the campaign bucket green.**

**1 · The capture-path leak — H10's root cause, the half that was game code.**
`Env/world_objects/holdable_core.gd:842` read
`_Tap.new().anchor_scene`: it stood up a whole `CaptureTap` — a
`StaticBody3D` — to get one `@export` default, then dropped it unparented and
unfreed. **An orphaned node that still holds a Resource segfaults Godot 4.3 at
exit**, because ObjectDB's final sweep deletes it after the servers owning its
RIDs are gone, so a resource destructor frees an RID into a dead server.

**Fixed by preload, not by `free()`, and the reason matters:** `anchor_scene`
is declared `@export var anchor_scene: PackedScene = preload(...)`, so
`.new()` was **only ever reading the script default** — it could never see a
`.tscn` override. Promoting that default to
`const DEFAULT_ANCHOR_SCENE` on `capture_tap.gd` and reading the const from
`holdable_core` is therefore behaviour-identical, keeps one source of truth,
and builds no body at all rather than building and discarding one on every
capture. The long note lives on the const.

**The sibling at `holdable_core.gd:582` is correct and was left alone** — it
`add_child()`s the tap at `:594`.

**2 · K20 — the last three hand-kept level lists**, all naming the retired
`hillfort_level.tscn` and never the live `hillfort_wip_level.tscn`:
`tools/probe_core_clearance.gd`, `tools/mission_ops.sh:252`, and
`tools/probe_footing.gd`'s fallback default plus its usage comment.

**`probe_core_clearance.gd` stays TYPED, deliberately.** H14's
`tools/_live_sites.gd` derives sites from `world.tscn`, but this list asks a
different question — scenes holding core prefabs, four of them
`gameplay/*_ops.tscn` wrappers rather than levels — so deriving it would
answer the wrong one. It just has to name the live fort.

**`mission_ops.sh` now WARNS on a missing level.** It was a bare
`[ -f "$lvl" ] && add_cover_spawner "$lvl"`, so a level retired out from under
the list was skipped in silence — which is precisely how the retired fort sat
in it unnoticed. Every early return warns.

**Gates.** `check.sh --changed`: **PASS**. `smoke.sh`: **PASS**, booted clean
15s, 1 warning line. **`bucket.sh campaign`: PASS, 42 suite(s)** (1 PARKED,
`test_tutorial`) — it has been red all week and the five reds were all this one
leak. **`bucket.sh frames`: PASS, 29 suite(s)**. The three suites individually,
before and after:

| suite | before | after |
|---|---|---|
| `test_site_win` | 14/14, exit **139** | 14/14, exit **0** |
| `test_hillfort_live` | 34/34, exit **139** | 34/34, exit **0** |
| `test_core_retake_live` | 13/13, exit **139** | 13/13, exit **0** |

**And the `N resources still in use at exit` line is gone entirely**, which is
the mechanism's own signature rather than a proxy for it.

**K20 immediately found a bug, and I A/B'd it rather than report it as mine.**
Repointing `probe_core_clearance.gd` took it from **8 clashes to 10**. The two
new ones are on the live fort: **`ShoulderCore` at (-123, 23, -20)** against
ten `Collision` shapes and **`PillarsCore` at (17, 23, 50)** inside
`entity_0_worldspawn`, both on the plateau at y=23. Proven by running a
pristine `HEAD` copy under a throwaway name — 8 clashes with the retired fort,
10 with the live one — so these are new *information*, not a regression. Logged
as **K23**; the level is TERRAIN's. The other 8 clashes are pre-existing and
partly deliberate, as the probe's own header explains.

**Needs the human.** Nothing in-editor from this change — no `.tscn` or
`.tres` touched. **`tools/mission_ops.sh` is a tool TERRAIN also uses** and
`Env/world_objects/` is shared ground — flagging both.

**Not verified.** Nothing played, nothing rendered. The capture path now builds
no tap to read a default, and **whether a capture still looks and feels right
in game is untested** — the suites prove the anchor is raised and the core
changes hands, not that the moment reads well. **K23's two clashes need a
render, not a probe**: a body standing on a core plinth passes every overlap
test, and I have not looked at either core.

**My own mistakes.** Two greps with `\t` in a BRE pattern silently matched
nothing, so an edit I believed had applied had not — caught both times by
reading the output rather than the exit code. And the H10 row I wrote on
2026-10-24 said **four** campaign suites when the bucket had five; I had built
the list from the fast tier, which skips `test_sim_arena` because it boots
`world.tscn`. The H9 agent caught it.

**Blocked / next.** The K22 sweep landed and is now **K24–K28**: three orphan
leaks on live game paths, eight cast-failure leaks (start with
`squad_spawner.gd:147`, the twin of an already-fixed file), a silent four-way
AI-equipment family, eight tool paths, and **K28 — `world.gd:127` calls
`queue_free()` with no `remove_child()` while `load_next_level()` parents the
replacement in the same frame, so two levels are in the tree when
`register_world_objects()` walks it.** That last one is not a leak and may be a
real correctness bug. `probe_mission_facts.gd`'s 139 is still unexplained.

## 2026-10-26 — K21: `test_ammo`'s one honest FAIL was the SUITE, not the game

**Landed.** One file: `tools/test_ammo.gd`. **No game code changed.**

The FAIL was `...and does NOT start with grenade, which needs its item carried
— 4 in the pool with nothing fitted`, exit 1, bucket `kit`. The arithmetic was
right and the **premise** was false: something *is* fitted.
`Campaign._carry_issued()` — added **2026-10-23, commit `aa2eaa51`**, a pure
addition — puts the issued Ancient Rifle and the issued **Frag** straight into
the player's record, so a new campaign musters with
`equipment_ids = [&"frag", &""]` and `grenade` has one carrier from the first
frame. Four in the pool is correct, and the owning code says so in its own
comment: *"otherwise mission one opens with an empty grenade slot and a trip to
the MEMORY screen to tick two free things on."*

**Proved, not inferred.** A throwaway tool booted a real `world.tscn` and read
it back: `weapon_ids = [&"m4"]`, `equipment_ids = [&"frag", &""]`,
`is_issued(&"frag") == true`, the loadout holding a `Grenade` node in
`Slot.EQUIPMENT` with `ammo_type=grenade`, grenade **4/4** — and `smoke` **0/0**
beside it. Deleted after. **The failure pattern was itself the evidence:** of
eight `requires_carrier` types only `grenade` was non-zero. A pool seeding
thrown ammo blindly would have failed all eight.

`test_ammo`'s check was last written **2026-10-17**, six days before the rule
changed, and asserted a flat zero for every carried type. Rewritten to assert
the rule that was always meant — **the pool agrees with what is in your
hands**: zero carriers ⇒ zero reserve, a carrier fitted ⇒ a reserve. The
carrier count is read off the live `PlayerEquipment` nodes in `Slot.EQUIPMENT`
by a new `_fitted_thrown()` helper, which is an independent observation of the
player's hands rather than a restatement of the pool's own books. Added one
check pinning the issued Frag itself, so a change that stopped issuing it fails
here instead of quietly sending every branch down the zero path and going green
having stopped testing the interesting case. The old rule, its date and the
commit are in a load-bearing comment.

**Nothing was lost by adapting it**, which is the part worth checking before
touching a check like this: `test_equipment._test_carrier_required_ammo` still
pins the unfitted case properly — it applies a record with an **empty**
`equipment_ids`, asserts 0 count / 0 capacity, then one frag, then two, then
none again — and `test_induction` (bucket `campaign`) already asserted *"the
issued Frag is in your hands too"* off the record. The rule `test_ammo` was
contradicting was under test on both sides the whole time. `test_ammo` cannot
arrange "nothing fitted": the campaign decides its loadout.

**Gates.** `check.sh --changed`: **PASS** (54 scripts, 51 scenes).
`test_ammo` alone: **1 FAIL / exit 1 → 32 PASS, 0 FAIL, exit 0**.
`bucket.sh kit`: **PASS, 16 suites, exit 0**, 2m32s, slowest `test_lance` 26s.
Not run: `smoke.sh` (nothing that loads at startup changed), `bucket.sh
campaign` (no campaign code touched — and its baseline is 3 red on H10's
unfixed `holdable_core.gd:842` leak), anything terrain or visual.

**Found in passing — a new decoy, measured.** `ItemDefinition.ammo_type` is
read in **exactly one place**, `equipment_loadout.gd:647`, inside `if node is
PlayerWeapon`. So for `kind = EQUIPMENT` it is read by nothing, and **6 of 11
equipment items leave it `&""`** — `frag`, `emp`, `hatchling`, `repair_kit`,
`repair_tool`, `scanner` — while `drone_pack`, `mine_cluster`, `mine_heavy`,
`recoilless` and `smoke` set it, which is what makes it look authoritative.
Three of the blanks do draw on the AmmoPool. **A thrown item's ammo type lives
on its scene** (`player_grenade.gd:23`), so anything mapping `equipment_ids` to
ammo types through the catalogue silently misses the issued Frag. That is why
the new helper reads nodes and not the record. Added to the vault's `Traps`;
it also belongs as a `Where the truth lives` row and I did not add one.

**Needs the human.** Nothing in-editor: no `.tscn` or `.tres` was touched, so
there is nothing to reload. One judgement call is **yours and I did not make
it**: K21's fix lands on **what the player is issued at the start of a
mission** — four frags in hand before they have chosen anything. I verified it
is deliberate and consistent; whether four is the right number, and whether
mustering with a grenade already in the pouch is the opening you want, is game
feel and balance. **I did not play the game.** The suite now follows whatever
`_carry_issued` does, so changing that number will not make it red.

**Blocked / next.** Nothing blocked. The adjacent thing I would do next is the
`Where the truth lives` row for `ItemDefinition.ammo_type` above, beside the
existing `weapon_damage` row — the two are the same mistake on the same
resource.

## 2026-10-24 — H12: the minimap miss now warns, and the bake list is a SUPERSET (measured)

**Landed.** Two of H12's three parts. The third — the Salient bake itself — is
the human's and is still outstanding.

- **`Campaign/minimap_data.gd` — `for_mission()` warns on a miss.** It was one
  silent `return null`; it is now three warning paths (no `level_scene`, no
  baked `.tres`, and a `.tres` that exists and does not load as a
  `MinimapData`), each naming **the mission, the level, the `.tres` it wanted
  and the `minimap.sh` argument that bakes it**. A **null mission stays silent
  on purpose**, and that is not a loophole: `Campaign/mission_map_board.gd`
  `_show(null)` calls this on every base refresh with nothing queued, so
  warning there would bury the real misses under base-UI noise. The comment
  says so.
- **`tools/minimap_bake.gd` — the mission half of the level list is derived.**
  New static `level_list()` = `_live_sites.mission_levels()` + `sim_levels()`
  + a typed `const EXTRA_LEVELS`, deduplicated. Static deliberately, so a probe
  can ask what the list is **without running a bake** — the old `var _levels`
  could not be asked at all, because `_init` is a coroutine and
  `minimap_bake.gd.new()` does not even parse.
- Two new hard stops in that tool. An **empty derivation aborts** (prints
  `FAIL`, `quit(1)`, no `MINIMAP BAKE DONE`, so `minimap.sh` never reaches
  `--import`) instead of baking six archive maps and reporting success. And a
  `--` filter that matches **nothing** now FAILs instead of printing
  `MINIMAP BAKE DONE` — which is live, because the house `-- --no-save` makes
  `only` = `"--no-save"`, the same shape that had `probe_sites_live.gd` printing
  an empty table and `0 problem(s)`.

**THE TRAP THE ROW WARNED ABOUT IS REAL, and here are the numbers.** The typed
array was **17 level paths against 9 live mission levels**, so
`mission_levels()` alone would have **silently stopped baking eight maps, every
one of which has a `.tres` on disk today**: `railhead` (the base —
`audit_levels.gd` flags a base with no minimap), `appendix/valley` (the
Laboratory's arena, and 14 suites load it), `heliostat` (a built, unconverted
WIP site), `appendix/arena` + `appendix/homebase` + `appendix/mutaha` (archive,
and dropping their maps would have quietly pre-empted H17), `proving` (a **sim**
arena, so it comes back from `sim_levels()` and is named rather than skipped),
and the retired `hillfort`. Measured with a throwaway probe that parsed the
level paths out of the file on disk and diffed them against the helper, not from
reading the code.

**One row deleted, and it is the only behaviour change to the list:**
`res://maps/hillfort_level.tscn`, the **retired** level. Its live replacement
`hillfort_wip_level` now arrives through the derivation, and a stale row naming
a retired level inside a tool is exactly H14's family of seven. The stale
`maps/minimaps/hillfort_level.{tres,png,png.import}` on disk were **left
alone** — authored output, and deleting it is not mine. Net 17 → 16 rows. Every
surviving `EXTRA_LEVELS` row now carries a comment saying who loads it.

**Load-bearing comments preserved, not stripped.** The old list's note about
causeway/georgetown/polaris needing a re-bake whenever their ops layer moves
(because markers come from the objectives in the **scene**, not the mission —
Causeway shipped a map with an empty marker set) was re-homed into the header
block. So was the railhead/depot note. Added: the expected one-line
`camera_switcher` compile error the `world.tscn` read now prints, so nobody
hunts it.

**Gates.**

- `check.sh --changed`: **PASS** (49 scripts parse, 51 scenes/resources
  consistent).
- `smoke.sh`: **PASS**, booted clean 15s, 1 warning line. A/B'd that warning by
  reproducing the boot with the log kept: it is "A Thread object is being
  destroyed without its completion having been realized", pre-existing and
  unrelated. **No minimap warning at boot** — which is the null-mission path
  proving it stays quiet.
- `bucket.sh campaign`: **42 suites, 3 red — `test_core_retake_live`,
  `test_hillfort_live`, `test_site_win`** (1 PARKED: `test_tutorial`), 5m18s.
  That is the current known baseline exactly. `grep -c "^FAIL  "` over the whole
  log returns **1** and that is `bucket.sh`'s own summary line — not one failing
  assertion in the bucket. All three print every check and `0 failure(s)` and
  then die in teardown; `test_site_win` re-run alone exits **139**. H10's
  unfixed `Env/world_objects/holdable_core.gd:842` orphan. **Not mine** and not
  touched.
- `bucket.sh terrain`: **PASS, 13 suites** (3 report-only, 1 PARKED:
  `test_terrain`), 4m48s.
- **The warning proved by firing it, not by reading it:**
  `tools/test_minimap_objectives.gd` (campaign bucket, exit **0**) walks all 27
  live mission rows and emits **exactly two** warnings, both Salient —
  "mission 'salient_1_overthetop' is on level res://maps/salient_level.tscn and
  so wants res://maps/minimaps/salient_level.tres, which is not baked …". Two
  warnings for two missions on one unbaked level, and no false positives
  anywhere else.
- Gap independently confirmed by `tools/audit_levels.gd`:
  `salient_level.tscn >> no minimap`.

**Needs the human. ONE COMMAND, and it is the whole of what is left on H12:**

```
bash tools/minimap.sh salient
```

**With the Godot editor CLOSED** — it opens a window to render (the dummy
renderer returns blank textures) and then runs `--import`, which must not run
against an open editor. It writes `maps/minimaps/salient_level.{png,tres}`.
Until it runs, both Salient operations still brief "NO MAP DATA"; the
difference after today is that they say so in the log. I did **not** attempt
it, per the brief.

Also for the human:

- **I touched a file outside my lane.** `tools/minimap_bake.gd` is **TERRAIN's**
  per `docs/BOARD.md:363`. H12's row names that file as the work, so it was
  sanctioned, but TERRAIN should know. `Campaign/minimap_data.gd` is mine.
- **No `.tscn` or `.tres` was edited**, so nothing needs reloading in the
  editor.
- Everything is **uncommitted**.

**Not verified.**

- **The bake itself.** Nothing here proves `minimap.sh salient` produces a good
  map — only that Salient is in the list and that the list is right. The
  Salient's `.tres` still does not exist.
- **The new abort branches were not fired.** Both the empty-derivation stop and
  the no-match-filter stop are code-read only: firing either means running
  `minimap_bake.gd`, which is headful and is the thing I was told not to run.
  The normal path is unaffected — `minimap.sh` passes `-- ""` when given no
  argument, so `only` is `""` and both branches are skipped.
- **The bake list was verified as a list, not as a run.** `level_list()` was
  called from a throwaway probe; no level was actually baked.
- **Game feel.** Not played, not rendered. A briefing with a Salient map on it
  has never been looked at by anybody, including me.
- Whether `appendix/arena`, `appendix/homebase` and `appendix/mutaha` deserve
  minimaps at all is **H17's** call; I kept them precisely so that this ticket
  did not decide it.

**Mistakes.** One, caught before it shipped: on the first pass I swapped the
`EXTRA_LEVELS` comments for `appendix/valley_level` and `heliostat_level`,
labelling the Laboratory's arena a WIP terrain site and vice versa. Fixed in
place. It is the exact mistake these comments exist to prevent, which is a point
in favour of writing them.

**Blocked / next.** Nothing blocked on code. Backlog K20 is the sibling and is
untouched: `tools/probe_core_clearance.gd` still carries a hand-kept level list
and still names the retired Hillfort and never the live `hillfort_wip`;
`tools/mission_ops.sh:252` and `tools/probe_footing.gd`'s fallback default do
too. The helper exists, so each is a two-line change — and `minimap_bake.gd`
being derived now removes the last reason to leave them.

**Reported, not edited** (and still stale, carried forward from H15):
`docs/GDD.md:48`, `docs/TESTS.md:134`, `tools/test.sh:45` and
`docs/marketing/SHOT_BRIEF.md:121/127` all carry depot wording. COORDINATOR's,
MARKETING's and a shared runner.
## 2026-10-24 — H15: the depot is deleted. Four render rigs held its FLOOR, not its path

**Landed.** `maps/depot_level.tscn` and `maps/minimaps/depot_level.{tres,png,png.import}`
are **gone**. There is one base level again — `maps/railhead_level.tscn`, which
`Env/world.tscn` has loaded all along — and H8 is settled with it.

**The row's consumer list was wrong in both directions, and the errors matter.**

- **`test_tutorial.gd` never read the depot.** The row said it "reads the
  base's lessons out of it while the game reads the railhead", and the vault
  said the same. It does not and never did: it loads `Env/world.tscn` and
  walks whatever base that carries, so it has been on the railhead since the
  base changed. Nothing to repoint. It is red because the live base has
  **zero** `TutorialLabel`s — measured — not because it was pinned to a decoy.
- **`shoot_core_skeleton.gd` is not a consumer either.** It loads
  `proving_level`, and the only time it names the depot is in a comment
  explaining why it refuses to use it.
- **`block_homebase.gd` is not a consumer of the scene.** It writes
  `maps/depot/depot_level.map`, the brush source.
- **One consumer the row did not name:** nothing, in the end — but
  `tools/shot_depot_door.gd` reads like one and is not. It is called "depot"
  and loads `railhead_level`. Checked `uid://di44xwffknyvf` as well as the
  path, and every `.tscn`'s `[connection]` lines: no scene instanced the depot.
  The only other carriers are `Env/wor7E58.tmp`, `Env/worE2BF.tmp` and
  `maps/depot_level.tscn~RF*.TMP` — dead Godot editor leftovers from September.

**The real work was the four render rigs, and it was not a path substitution.**
`mock_damage.gd`, `mockup_gun.gd`, `mockup_drone.gd` and `mockup_shots.gd` each
held a typed `STAGE = Vector3(0, 1.2, 0)` — the depot's inner floor at 0.19
plus the metre from a 2 m capsule's centre to its feet. **The railhead's floor
at the same x/z is 1.19**, so carrying the number across would have buried
every subject to the waist and still produced a plausible picture. All four now
derive the stage by raycast. `mock_damage.gd` already did, which is why it
needed one line.

**And one of them had nowhere to stand.** `mockup_shots.gd`'s kit line-up is
~25 m of row with the camera ~21 m back; the depot swallowed that indoors
because it was an 84 m hall, and the railhead's platform is a train. The first
repoint came back as **a black rectangle with five pale smears in it** — the
camera inside a carriage wall — and only opening the image said so. All four
rigs now stage on the railhead's **open upper deck at y=11**, measured clear to
120 m in all sixteen directions and 200 m overhead.

**The sun was never the problem, and the file said it was.** Measured: the
depot, the railhead, proving and all four store-shot levels each instance the
same `Env/world_environment.tscn` — one `WorldEnvironment`, one
`DirectionalLight3D`, identical bearing `(-0.268, -0.500, -0.824)` at identical
energy. `mockup_shots.gd` carried a comment asserting that none of the five
shot levels has a light and `homebase_level` is the only map in the repo that
does; **false on every clause**, and corrected in place. `mock_damage.gd`'s
`LIT` bearing transferred untouched because of it.

Also: `_texts()` binned from `test_tutorial.gd` (H19 left it for this ticket;
confirmed no other caller anywhere in `tools/`). `minimap_bake.gd` lost the
depot row **and nothing else** — H12 owns that list's redesign.
`05_depot_manager` in `mockup_shots.gd` repointed to the railhead with
`HoloTable` as its anchor; **the id is deliberately unchanged**, because it is
the shot number in `SHOT_BRIEF.md` and the argument the tool takes.

**`TutorialLabel.in_library` KEPT**, with a comment on the export saying it has
no reader. Removing an `@export` empties every scene still carrying it in
silence, and the five carriers are in `maps/appendix/homebase_level.tscn` —
TERRAIN's, and itself queued for appendix-or-delete under H17. Dropping
authored values out of somebody else's archive to retire a bool is the wrong
trade; data first, field second.

**Gates.** `check.sh --changed`: **PASS**. **Project-wide `check.sh`** (the
deletion gate): **all 624 scripts parse, all 1009 scenes and resources
consistent** — so nothing anywhere is left holding a dangling `ext_resource` or
a stale `load_steps`. Its brush pass fails on **59 `.map` files**; **measured,
not asserted**: the newest `.map` in the whole project is from **2026-10-17**
and **not one was modified today**, so none of them is mine. `smoke.sh`:
**PASS** — booted clean, 15s, 1 warning line (an engine thread-cleanup warning
at quit, unrelated). `bucket.sh terrain`: **PASS, 13 suites** (3 report-only,
1 PARKED: `test_terrain`), exit 0. **`bucket.sh campaign`: 42 suites (1 PARKED:
`test_tutorial`), 3 red — `test_core_retake_live`, `test_hillfort_live`,
`test_site_win`.** That is **three of the four the brief named, not four**:
`test_arena_assault` is green now, which is exactly what H10's report predicts,
since H10 fixed the test-side cause in all four and left the game-side one. And
**there is not a single failing assertion in the entire bucket** — `grep -c
"^FAIL  "` over the whole run returns 1, and that one is `bucket.sh`'s own
summary line. All three print every check clean and then die in teardown with
leaked RIDs and "133 resources still in use", which is H10's signature for the
unfixed `holdable_core.gd:842` leak — and those three are precisely the suites
that reach `start_held()`. Nothing of mine is in that path.
`test_tutorial` A/B'd across my own edit: **2 FAIL / 3 PASS, exit 1, byte-for-
byte the same verdict before and after** — it is PARKED and still red on the
base having no lesson signs. `audit_levels.gd` re-run: the depot is gone from
its walk and the railhead's own minimap is present, so the deletion left no gap.

**Rendered and opened, not just run.** Every render below was looked at, at
1152x648 with the eye at 1.50 m, headful, through the signal filter:
`mock_damage` frames + kinetic (the five-state progression row), `mockup_gun`
at 0.25 and 0.48, `mockup_drone`'s body comparison, and **every one of
`mockup_shots`' seven passes** — kit (line-up and a portrait), props, frames,
rank, vrank and `05_depot_manager`. The two that could actually have failed
were checked deliberately: the **kit line-up**, which is the widest row, and
**vrank**, which has the longest camera pullback at 9.4 m. Both clear.
Vehicles sit exactly where they used to: `FEET` is 1.01, which is the depot's
old 1.2 minus its 0.19 floor, so the subject-to-floor offset is unchanged and
only the floor moved.

**Needs the human.**
- **A `.tscn` was deleted on disk while your editor is open.** Reload before
  you touch anything in the inspector. `maps/depot_level.tscn`,
  `maps/minimaps/depot_level.tres`, `.png` and `.png.import` are gone; all four
  are in HEAD and recoverable.
- **Cross-lane files I touched, all deliberate:** `tools/minimap_bake.gd` and
  `tools/block_homebase.gd` (TERRAIN), `Env/world_objects/tutorial_label.gd`
  (TERRAIN, comment only), and `maps/**` for the deletion itself.
- **`docs/GDD.md:48` still says "Home base is `depot_level`".** Stale, and the
  COORDINATOR's file — reported, not edited. `tools/test.sh:45` and
  `docs/TESTS.md:134` carry the same stale wording; `test.sh` is shared so I
  left it. `docs/marketing/SHOT_BRIEF.md:121/127` names `depot_level`,
  `ChassisBays` and `DummyTerminal` for shot 5 — MARKETING's to correct.
- **A judgement to overrule if you disagree:** I **kept**
  `maps/depot/depot_level.map` and `tools/block_homebase.gd`. The brush
  geometry is authored TrenchBroom content that was lost to an overwrite once
  already, and it is TERRAIN's. Running the tool still writes a valid map; it
  just no longer feeds a scene, and the file now says so.
- **Dead weight I did not sweep, because the editor is open:**
  `maps/depot_level.tscn~RF535a4d68.TMP` and `~RF5381b711.TMP` (1 MB of orphan
  editor backups), plus `Env/wor7E58.tmp` / `Env/worE2BF.tmp`, which hold a
  stale `world.tscn` still pointing at the depot.

**NOT verified.** Whether the roof is the *right-looking* stage for a kit
catalogue — it is brighter, clearer and unobstructed, and it is a **look**
judgement, which is yours. I did not play the game. I did not run `bucket.sh`
frames, kit or shell, and I did not run `test.sh`.

**Blocked / next.** H12 is unblocked: `minimap_bake.gd` now has no depot row,
and its list is ready to be derived from `world.tscn`'s missions.

---
## 2026-10-24 — H10: the clean-printing exit 139, root-caused. Three faults, one family

**Landed.** The family, measured with no Master and no level: **an orphaned node
that keeps a Resource alive segfaults Godot 4.3 at exit.** ObjectDB's end-of-run
sweep deletes whatever is still alive *after* the servers that own its RIDs are
gone, so a resource destructor frees an RID into a dead server. The A/B that
pins it: an orphan `StaticBody3D` + `CollisionShape3D` holding nothing exits
**0**; the same one holding a single `PackedScene` in its meta exits **139**; a
bare `Node` holding that `PackedScene` exits **139**. It is not the node and not
the physics body — it is the resource dragged past shutdown.

Three distinct instances, which is why "one bug" never fitted all five suites:

1. **GAME BUG — `Env/world_objects/holdable_core.gd:842`, NOT FIXED, the
   human's call.** `var scene: PackedScene = _Tap.new().anchor_scene` stands up
   a whole `CaptureTap` — which `extends StaticBody3D`, and whose `anchor_scene`
   export holds `capture_anchor.tscn` — purely to read one export default, and
   never frees it. One leak per `start_held()`. 20-line reproduction: `_Tap.new()`,
   read `.anchor_scene`, `quit(0)` → **139**; add `.free()` → **0**. The leaked
   nameless `StaticBody3D` and `capture_anchor.tscn`'s sub-resources are visible
   in `test_site_win --verbose`. This accounts for `test_site_win`,
   `test_hillfort_live` and `test_core_retake_live` — exactly the three suites
   that call `start_held()`. One `free()` is the whole fix; I did not make it,
   because the ticket reserves game code for the human.
2. **TEST BUG — fixed in four suites.** Each called `cm.on_level_loaded()`
   explicitly straight after `await world.load_next_level()`, which **already
   calls it** (`Env/world.gd:124`). That redeployed BOTH spawners in the same
   frame as the first deploy, and on its own exits 139. A/B: drop the call →
   **0**; keep it 10 physics frames later → **0**; 1 or 2 frames later → still
   **139**. Dropped from `tools/test_arena_assault.gd`,
   `tools/test_core_retake_live.gd`, `tools/test_hillfort_live.gd` and
   `tools/test_site_win.gd`, each with the reason in a comment.
3. **TEST BUG — fixed in `tools/test_sim_arena.gd`.** It built a scratch
   `sim_arena_ui` (`lab_ui`) and a row box, neither parented nor freed — fault 1's
   shape inside a suite. Two lines free them.

**`test_ammo` is NOT in this family, and that matters.** It is one honest `FAIL`
at exit 1 — *"does NOT start with grenade … 4 in the pool with nothing fitted"* —
and the `ObjectDB instances leaked at exit` beside it is the line every run of
this project prints. It is a real regression wearing H10's clothes and needs a
row of its own. This is exactly the masking the ticket was opened about.

**Gates.** `check.sh --changed`: **PASS** — 48 scripts parse, 51 scenes and
resources consistent. Worth recording that the first run of it was **FAIL on
`tools/mockup_shots.gd`** (`Identifier "STAGE" not declared`), which was **not
mine**: the file's mtime was later than my own first edit, so another lane was
mid-edit in the shared checkout, and a re-run twenty minutes later was green
without me touching it. My five files were also parse-checked individually with
the same `--check-only` invocation `check.sh` uses — **PASS on all five** — and
`grep -c "Ã\|â€"` is 0 on each. Suites run
individually, after the fix: `test_arena_assault` **21/21, exit 0** (was 139),
`test_sim_arena` **53/53, exit 0** (was 139), `test_site_win` **14/14, exit 139**,
`test_hillfort_live` **34/34, exit 139**, `test_core_retake_live` **13/13, exit
139** — the last three stay red until fault 1 is fixed. `test_ammo` **1 FAIL,
exit 1**, unchanged. No bucket run, no `smoke.sh`, no `test.sh`.

**Needs the human.** (a) The decision on `holdable_core.gd:842`. (b) Nothing in
the editor: no scene, resource or inspector value was touched — the only files
changed are the five `tools/test_*.gd`. (c) `tools/mockup_shots.gd` is red in
`check.sh --changed` and belongs to whoever is editing it.

**Blocked / next.** `probe_mission_facts.gd` still exits 139 and is a **fourth,
separate** leak: 23 `NavAgent` and 345 `RendererSceneCull::Instance` RIDs at
exit, and **removing its Master detach changes nothing** (A/B'd, both 139), so
its own comment about that is correct. Not root-caused. Also unverified: the
exact object left dangling by fault 2 — the trigger and the cure are both
proven, the dangling object is not identified; `probe_home_base.gd` and
`probe_order_facts.gd`, which the vault blames on Master, were not re-measured;
and no suite outside the six named here was examined, so other tools that
`.new()` a Node and never free it are very likely still red. Nothing about game
feel was judged and the game was not played.

**I was wrong twice, on the record.** I first blamed the leaked orphan nodes
reported by `--verbose` (identical in the crashing and clean arms, so not the
cause), and then `CsgBake` (an A/B with the bake suppressed still exits 139).
Both are ruled out. The vault's claim that *any* tool booting `master.tscn`
under `--script` exits 139 is also too broad — booting Master and quitting
exits 0, and so do `test_analytics` and `test_endings`, which boot Master and
load a real level. `Traps.md` and the OA9 row now say so.

## 2026-10-24 — H14: seven tools stopped carrying their own list of sites

**Landed.** `probe_slices.gd` and `probe_sites_live.gd` each held a typed
nine-row table of "site → [level scene, slice node]", and the first row of both
named `maps/hillfort_level.tscn` — the **retired** Hillfort. The campaign has
deployed `maps/hillfort_wip_level.tscn` since the rebuild, so both probes
printed a tidy `ok` about a level the game does not load and said nothing at all
about the one it does.

Fixed by deleting the list, not by typing a better one. A hand-kept list in a
tool IS the defect, and the project already solved this shape once with the
`# BUCKET:` tags the runner reads off each suite.

- **New: `tools/_live_sites.gd`.** `mission_levels()` reads `Env/world.tscn`'s
  `missions` array through the PackedScene's `SceneState` — the same route
  `probe_level_facts.gd` uses — and returns the distinct `level_scene` of every
  non-`sim` mission in campaign order. `sim_levels()` returns the practice track
  separately so a caller can **name what it skipped** instead of dropping it.
  `sites()` adds the slice, found as the first node whose script extends
  `site_slice.gd`, read off the state where it can be and only instantiating as
  a fallback. The **label is derived too** — `coast_slice.gd` → `coast` — so
  every converted table prints the row names it always did, with `hillfort` now
  reading `hillfort_wip`.
- **Why `sim` is the dividing line.** `MissionDefinition.sim` marks the arenas
  that are a free action and not territory (§15); they carry no slice on
  purpose. `arena_3_firing_line` → `maps/proving_level.tscn` is the only one,
  and every converted tool now prints `sim arenas, not sites, skipped: …`.
- **Established before changing anything:** `world.tscn`'s `missions` is 19
  missions over 10 distinct levels; 18 non-sim over **9**. The retired
  `hillfort_level.tscn` is in none of them. The `Campaign/missions/` folder was
  not used for this — it holds missions that are not in the game.
- **Converted, all seven.** `probe_slices`, `probe_sites_live` (the row), plus
  `probe_bunker_clear`, `probe_bunker_sites` and `scan_bunker_spot`, which
  carried the identical stale table, and `probe_standing_circle` and
  `shot_bunkers`, which carried **both** Hillforts and so spent a tenth of
  their output on the dead one.
- **A level with no slice still FAILS.** Deriving the slice must not turn
  "somebody regenerated this level from a template and it lost its slice node"
  into "not a site" — that is the exact failure `probe_sites_live` exists for.
  `_live_sites` hands the row over with an empty node and script, and every
  caller fails it loudly.
- **One extra guard.** `probe_standing_circle` takes its user args as site
  filters, so the house `-- --no-save` matched nothing and it printed an empty
  table and `0 circle(s)` — a silent pass. It now fails on a filter that
  matches nothing, and its header says not to pass that flag.

**What the probes said, before and after.** `probe_slices`, row one:
`ok hillfort 1 core(s), bunker 'Hillfort_Postern', 3 entr(ies)` →
`ok hillfort_wip 6 core(s), bunker 'HFW_Bunker', 3 entr(ies)`. `probe_sites_live`,
row one: `hillfort yes 1 yes yes ok` → `hillfort_wip yes 6 yes yes ok`. The
other eight rows are unchanged apart from order, which is now campaign order.
Both are 0 problems / exit 0 before and after — **which is the point: they were
green on the wrong level.**

**Gates.** `check.sh --changed`: **PASS** (61 scripts, 51 scenes). `smoke.sh`:
**PASS**, booted clean 15 s, 1 warning. `bucket.sh terrain`: **PASS**, 13
suite(s) of the 14 listed (3 report-only, 1 PARKED — `test_terrain`), 4m52s.
Probes run headless, muted, and none of them touches `CampaignState` or
`SaveSlots` — `campaign.json` was checked by mtime before and after and is
untouched. Ran and read: `probe_slices` (0 problems), `probe_sites_live` (0),
`probe_bunker_clear` (0), `probe_bunker_sites` (0), `scan_bunker_spot`
(`hillfort_wip`, and a bogus label to see the error path list the derived
names), `probe_standing_circle` (**2 failures, pre-existing — see below**).

**One transient red worth recording.** The first `check.sh --changed` of the
session FAILED with `Identifier "count" not declared` in `probe_save_facts.gd`,
`probe_squad_facts.gd` and `test_line_specs.gd`. That is H9's migration mid-edit
in the shared checkout, not this work: the next run passed, and the script count
moved 45 → 49 → 50 → 60 → 61 across runs as the other lane committed. If a check
here goes red in files you have not touched, run it again before believing it.

**Found in passing, proven not mine.** `probe_standing_circle` is **red on
Georgetown**: `lockside RelayLock/Collar` and `…/Circle` report `no ground under
it at all`. Proven pre-existing by **A/B** — `git show HEAD:…` into a throwaway
file, run filtered to `lockside`, gives the identical two failures — so the
probe was already red with the same finding and the conversion did not cause it.
It is a live mission level and a real core, and it is in no backlog row. Worth
someone's afternoon.

**Deliberately left typed, and why.** `minimap_bake.gd`'s list is a *superset* —
both bases, the appendix, the lab's levels — so `mission_levels()` alone would
shrink it; backlog **H12** already owns deriving it, and the helper is now there
for whoever takes it. `probe_core_clearance.gd`'s list is "scenes holding core
prefabs", four of them `gameplay/*_ops.tscn` wrappers rather than levels, so it
is a different question — **but it does still name the retired Hillfort and
never the live one, which is a real stale row.** Also still typed:
`mission_ops.sh:252` and `probe_footing.gd`'s fallback default. The
hillfort-specific build/nav/paint/shot tools name the retired level because it
is their *subject*; those are correct as they stand.

**Not verified.** `shot_bunkers.gd` is converted but **not run** — it is a
headful camera that opens a window and walks nine levels, and nobody asked for
the pictures. It parses, and it uses the same two lines as the six probes that
were run, but the renders themselves are unseen. `probe_bunker_sites` prints
core counts that look doubled (`hillfort_wip` 13 against the level's 6) because
it adds a *second* slice to a level that already carries one — that is its
pre-existing design, unchanged here and unexamined. Nothing visual was rendered,
because nothing visual changed: this is tool plumbing only. No game code, no
scene, no level, no `.tres` was touched, so there is no game-feel or balance
claim here at all.

**Needs the human.** Nothing in-editor — no `.tscn`, `.tres` or game script was
touched. Two calls are yours: whether the Georgetown `RelayLock` circle is worth
a row of its own, and whether `probe_core_clearance.gd`'s stale Hillfort entry
should be folded into H12 or handled on its own.

**Shared files.** None of `Env/world.tscn`, `project.godot`, `CLAUDE.md`,
`check.sh`, `test.sh` or `smoke.sh` was modified — `world.tscn` is only *read*.
`tools/shot_bunkers.gd` and `tools/scan_bunker_spot.gd` are bunker-siting tools
that TERRAIN also uses; flagging them explicitly. Everything is left
uncommitted on `agent/cleanup-appx-and-catalogue`.

**Blocked / next.** Nothing blocked. The obvious next pass is H12, which is now
a two-line change on top of `_live_sites.gd` plus `base_level` and the lab
plans.

---
## 2026-10-24 — H9: the legacy `count` + `chassis` squad form is gone, data first

**Landed.** `EnemySquadSpec` had two ways to describe a squad. Now it has one.

**The enumeration, which is item one because the hazard is an empty map.**
Godot drops unrecognised properties in silence when loading a resource, so
removing the fields before migrating the data would have emptied every mission
still on the old form with no error and no warning. So: enumerate, migrate,
prove, *then* remove, prove again.

- **41 `.tres` files set `count`** (38 missions + 3 loose specs in
  `Campaign/squad_specs/`). `Campaign/items & catalogue/test_item_catalogue.tres`
  also matches a grep for `^chassis =` and is **not** one of them — that is
  `ItemCatalogue.chassis`, an array of frames. Left alone.
- **626 spec sightings in missions, of which 43 were legacy-form** (empty
  `roster`, `count > 0`, `chassis` set). They are **39 distinct authored
  specs**: 18 sub-resources each in `Campaign/missions/appendix/mission_valley.tres`
  and `…/mission_valley_basin.tres` (those two files are identical but for uid,
  level, id and display name), plus the 3 loose specs — two of which each
  mission ext_resources, which is why the sighting count is 43 and not 39.
- **The other 583 sightings were already roster-form and still carried a stale
  `count`:** 564 at `count = 0` and **22 at `count = 3`, all in
  `mission_hillfort_1_relay.tres`** — a roster of three beside a count of
  three that nothing read.
- **Live / not live, off `Env/world.tscn`'s `missions` array (19 missions), not
  the folder.** **None of the 39 legacy specs is in a live mission.** Both
  valley files are referenced by nothing at all — no mission list, no suite, no
  tool, no uid — and `squadspec_3 shotguns.tres` is referenced by nothing
  either, not even by the two valley missions that use the other two loose
  specs. Second routes checked: `.gd`, `.tscn`, `.tres`, bare uid search, and
  the eleven tools that walk `Campaign/missions` by `DirAccess` (only
  `probe_level_facts.gd` descends into `appendix/`). `.godot/exported/*.res`
  holds stale build copies of all of them; that is cache, not a route.

**The migration.** All 39 to `roster`, mapping each PackedScene to the one
`ChassisDefinition` that names it: `soldier_shotgun.tscn` → `chassis_shotgunner`,
`enemy_nest-chaser.tscn` → `chassis_hopper`, `enemy_chaser.tscn` →
`chassis_chaser`, `enemy_helicopter.tscn` → `chassis_helicopter`,
`soldier_chassis.tscn` → `chassis_soldier`. Then `count` and `chassis` deleted
from `Campaign/enemy_squad_spec.gd`, and the **586 stale `count` lines stripped
from 35 mission `.tres`** so no file names a property that no longer exists.

**How the force was proved preserved — not asserted, diffed.** New
`tools/probe_enemy_force.gd` prints every spec in the project body by body:
callsign, posture, body count, and the **sorted scene files of the frames**,
across both mission folders and the loose specs. It reads both forms through
`"count" in spec` rather than `spec.count`, so the same probe compiles and runs
on either side of the change — which is the whole point, since a probe that
only builds against one side cannot compare the two. Three runs:

| run | specs | bodies | legacy-form |
|---|---|---|---|
| before anything | 626 | **2787** | 43 |
| after migrating | 626 | **2787** | 0 |
| after deleting the fields | 626 | **2787** | 0 |

**The before/after reports are byte-identical apart from one line** — the
legacy counter going 43 → 0. Every callsign, posture, per-spec count and frame
list is unchanged, and the third run emits no "empty roster" warning, which is
what an emptied mission would have looked like. A matching total was never
going to be enough on its own: the two forms name different things (a
PackedScene vs a `ChassisDefinition`), so the identities had to match too.

**Consumers fixed, found by grepping every file that mentions
`EnemySquadSpec`** (27 of them, `.claude/` excluded): `force_generator.gd` ×2
(the weight fallback now reads `body_count()`; the `made.count = roster.size()`
write is gone), `enemy_force_spawner.gd` ×2 (the skip warning, and
`_bodies_of`'s legacy branch), `tools/test_force_generation.gd`,
`tools/build_salient_mission.gd` ×2, `tools/test_wake.gd`. `body_count()` is
**kept** — it is one line over `roster` now, but eleven call sites ask it and
it is the name that carries the lesson about the skip that once threw away
45 hostiles in Valley Siege.

**One suite was red on correct behaviour and was repurposed, not deleted.**
`test_force_generation._counts_agree()` asserted `s.count == s.roster.size()`
— it existed to catch the stale field. It now asserts `body_count() ==
roster.size()`, so the check stays real instead of vanishing with the field.
19 checks, 0 failures, including that line.

**Docs corrected.** `docs/CONTENT_RULES.md` §6.5 rewritten (and it now carries
the two conversion traps below), a dated correction note added to
`docs/GAMEPLAN.md` §8.3, and the stale "every shipped spec still carries a
count of 3" comments in `Env/world_objects/ops_table.gd`,
`tools/measure_resistance.gd` and `Env/world_objects/enemy_commander.gd` made
true again without stripping why they are there. Vault: `Reference/Enemies.md`,
`Where the truth lives.md`, `Tools.md`, `Backlog` H9 → DONE, new H21.

**Two things measured that a body count cannot see, and they are judgements.**
A `ChassisDefinition`'s `base_health` / `base_accuracy` / `base_sensor_range`
**override** the scene's authored values (`_apply_frame`, anything above zero
wins), and the legacy path deliberately wrapped the PackedScene in a definition
with all three zeroed so the scene won. So a faithful-looking migration still
moves stats:

- hull agrees everywhere (60 / 45 / 60 / 100 against the scenes' own), **except
  `squadspec_3 shotguns.tres`**, where `soldier_chassis.tscn` authors 100 and
  `chassis_soldier` says 60 — and that file is referenced by nothing
- accuracy and sensor range move on the chaser, hopper and gunship specs:
  `chassis_chaser` 0.6 and `chassis_hopper` 0.8 against the script's 0.75
  default, and sensor 55 / 60 / 60 m against 45
- `chassis_soldier` has `starting_weapon_id = &"m4"` and `soldier_chassis.tscn`
  bakes no `AIWeapon`, so that one spec's bodies would now be **issued a gun
  they used to spawn without**

**I took the real definitions anyway**, because that is what all 586 other
specs in the game use and because all 39 affected specs are in content nothing
loads. If any of those three files is ever brought back into the campaign,
those are the numbers to look at. Recorded in `Reference/Enemies.md`.

**Gates.** `check.sh --changed`: **PASS** (59 scripts, 51 scenes/resources —
most are other lanes' uncommitted files in this shared checkout).
`smoke.sh`: **PASS**, booted clean, 15s, 1 warning line. `bucket.sh frames`:
**PASS — 29 suites**, 8m0s, slowest `test_mortar` at 61s. `bucket.sh campaign`:
**FAIL — 42 suites, 1 PARKED (`test_tutorial`), 5 red:** `test_arena_assault`,
`test_core_retake_live`, `test_hillfort_live`, `test_sim_arena`,
`test_site_win`. Zero `FAIL` lines in any of them. Inside the green ones:
`test_force_generation` 19/19 (including "ACT 1 IS THE AUTHORED NUMBER — 82 vs
measured 82", i.e. the basin's supply total did not move),
`test_mission_objectives` 107/107, `test_mission_tags` 77/77,
`test_site_operation` 17/17. In `frames`, `test_wake` — whose spec-building
code I edited — 19/19.

**The fifth red was A/B'd rather than assumed.** My brief named H10's four and
`test_sim_arena` is not one of them, so: run alone → **53/53 PASS,
`0 failure(s)`, exit 139.** Then the six scripts this ticket changed restored
from `HEAD` into the working tree, the same suite run against **pre-H9 code with
post-H9 data**, and restored (all six `cmp`-verified identical afterwards) →
**53/53 PASS, `0 failure(s)`, exit 139.** Identical. It is H10's family, and
**H10's row understates the set: in `campaign` it is five, not four.** Three
earlier entries in this file record the same five from sessions that changed no
game code. I have not edited H10's row — a sibling is on that ticket — so it is
flagged here and in the handover instead.

**Did NOT verify.** **Game feel and balance: not played, not judged** — this is
a data-shape change in content nothing loads, but nobody has walked any valley
to see it. **Did not deploy a mission and count bodies on the ground**;
`spawn_check.gd` and `measure_resistance.gd` were not run — the probe compares
authored forces, not landed ones, and the spawner path for roster specs is
unchanged code. Nothing visual changed, so **no render was taken**. The
`base_*` override deltas above are **read off the resources, not observed in a
fight**. `bucket.sh kit`, `terrain` and `shell` not run — nothing they cover
changed.

**Needs the human.**
1. **`.tres` files were edited on disk — reload before touching the inspector.**
   40 of them: the 5 migrated (`appendix/mission_valley.tres`,
   `appendix/mission_valley_basin.tres`, the 3 in `Campaign/squad_specs/`) and
   the 35 stripped of their stale `count` lines. `Env/world.tscn` was **not**
   touched.
2. **H21, and it is deliberate:** `EnemyForceSpawner.default_chassis` is now
   read by nothing — its only reader was the legacy fallback — but
   `Env/world.tscn:111` still assigns it. I left the export declared and
   commented DEAD rather than edit a shared scene the editor has open; that is
   exactly the edit H9 exists to warn about, and it wants its own pass.
   `SquadSpawner.default_chassis` is a different field and is **live**.
3. **Three files are referenced by nothing and are now migrated but still
   dead:** `appendix/mission_valley.tres`, `appendix/mission_valley_basin.tres`
   and `Campaign/squad_specs/squadspec_3 shotguns.tres`. Deleting authored
   content is your call, not mine — say the word and they go. The third is
   also misnamed: "3 shotguns", pointing at `soldier_chassis.tscn`.

**Files outside my lane or shared.** `Env/world_objects/ops_table.gd` and
`Env/world_objects/enemy_commander.gd` (comment-only), `docs/CONTENT_RULES.md`,
`docs/GAMEPLAN.md`, and three `tools/` runners —
`tools/measure_resistance.gd` (comment-only),
`tools/build_salient_mission.gd`, `tools/test_wake.gd`,
`tools/test_force_generation.gd`. New file: `tools/probe_enemy_force.gd`.
No commit, no branch, no `git add`.

**My own mistakes.** First draft of this entry claimed `test_force_generation`
30/30 and `test_site_operation` 19/19 from eyeballing the printed blocks. Both
wrong — 19 and 17 when counted off the log. Corrected before posting, and worth
recording because an invented count is the exact failure
`docs/TESTING.md` asks for named counts to prevent.

**Blocked / next.** Nothing blocked. H21 is the loose end, and H10's row wants
`test_sim_arena` added to it.

---
## 2026-10-24 — H19: the two deprecated HUD screens are gone, consumers first

**Landed.** Three files deleted — `Character/hud/debug_overlay.gd` (245 lines),
`Character/hud/debug_overlay.tscn` and `Character/hud/tutorial_library.gd`
(229 lines) — and every consumer removed *before* them, in that order.

**The consumer list, from a repo-wide grep of `DebugOverlay`, `TutorialLibrary`,
`tutorial_library`, `_open_tutorials`, `debug_overlay`, excluding `.claude/`:**

- `DebugOverlay` had **exactly one** consumer in the whole repo: its own
  `debug_overlay.tscn`, which names the script as an `ext_resource`. Nothing
  else — no scene, no `[connection]`, no `.tres`, no `.map`, no FGD, no
  autoload, no input-map action for the `~` toggle its header advertises, and
  no reference to its `uid://cgixlpeuaxv87`. The scene went with the script, so
  the `load_steps` arithmetic never came up.
- `TutorialLibrary` had **two**: `Managers/master.gd` (**a shared/core file** —
  flagged) and `tools/test_tutorial.gd:174`. In `master.gd` that is the
  `_TutorialLibrary` preload, the `_tutorials` field, `_open_tutorials()`,
  `_close_tutorials()`, the `_menu == "tutorials"` ESC branch in `_input`, and
  `"tutorials"` in the `_menu` doc comment. A tombstone comment replaces the
  section, because the next person's question is "why is there no tutorials
  screen" and the answer is "nothing ever opened it".
- In `test_tutorial.gd`, the four library checks at `:173`–`:189`.

**Two routes the row did not mention.** `Character/hud/lab_results.gd:11`
described itself as "same frame as the options and tutorials screens" — a
comment pointing at a file that no longer exists, so it is corrected. And
**this file, at `:1708`**, carried an open family-sweep finding against
`tutorial_library.gd:collect()` — a lesson sign authored as an instance of
`tutorial_label.tscn` would vanish from the library silently. That latent bug
is closed by deletion; the sibling finding about `tools/audit_audio.gd` and
inherited weapon scenes is untouched and still open.

**Kept deliberately.** `TutorialLabel.in_library` stands, per the row — H8/H15
is retiring the depot's signs and that is their call. **Counted before leaving
it: one file carries it, `maps/appendix/homebase_level.tscn`, 5 nodes, all
`in_library = false`.** The export now means nothing, and removing it would
have silently emptied those 5 entries. Also kept: `_texts()` in
`test_tutorial.gd`, now called by nothing since the library block was its only
caller — left in place because H15 repoints the rest of that suite and the
brief said not to touch it beyond the library half. The `# PARKED:` reason, the
header summary and one `printerr` string in that file lost the word "library",
which is three words of comment, not a repoint.

**No surviving file loses a property.** The only `@export`s removed anywhere
were `player`, `squads` and `auto_discover_squads` on `debug_overlay.gd`, whose
sole carrier was the `.tscn` deleted alongside it. `_TutorialLibrary` was a
`const` and `_tutorials` a private `var`, neither serialised, so `master.tscn`
is untouched. Verified by diff: no `-` line in any surviving script is an
`@export`.

**Gates.**

- `check.sh --changed`: **PASS** — 58 scripts parse, 51 scenes and resources
  consistent. (That set is larger than my change: `--changed` sweeps the whole
  dirty working tree, so it is also green over the sibling lanes' in-flight
  files.)
- `bucket.sh shell`: **PASS, 4 suite(s)** (`test_factions`, `test_pause_hold`,
  `test_settings`, `test_splash_skip`), 0m25s. **Baselined before the change at
  PASS 4/4 as well**, so the pause menu is green on both sides of it —
  `test_settings`' "ESC returns to the pause menu" is the check that covers the
  ESC branch I removed.
- `smoke.sh`: **PASS** — booted clean headless for 15s, 1 warning line.
  `master.gd` loads at startup, so this one was earned.
- `test_tutorial` (bucket `campaign`, and `# PARKED:`): **still red, 2 FAILs,
  exit 1 — pre-existing, and A/B'd rather than asserted.** The two failures are
  "the homebase signs are toasts (0 sign(s))" and "(setup) found the weapon
  sign", both upstream of anything I touched; the suite then takes its bail-out
  and the library block was unreachable even before the deletion. Because the
  original file preloads a now-deleted script, a straight revert cannot run, so
  the A/B was done against **pristine copies of both files restored from HEAD
  under temporary names** (`tutorial_library_h19ab.gd`,
  `test_tutorial_h19ab.gd`, preload repointed, both since deleted — no live
  file was swapped). Identical output: same 2 FAILs, same 3 PASSes, exit 1.
- Full `check.sh`, project-wide — **the gate that actually matters for a
  deletion, and it is clean: all 643 scripts parse, all 1011 scenes and
  resources consistent.** That is the real proof that nothing anywhere was left
  holding a dangling `ext_resource` or a `load_steps` that no longer matches
  its count. Its third pass, overlapping brushes, **fails on `.map` files
  only** (`arena`, `autosave/arena.2–4`, `autosave/civil-unrest-4.1/.10/.11`,
  `autosave/oyster-bay.1–3`, and more in the earlier run: `solar/*`,
  `tower.map`, `depot_level`, `homebase_level`, `proving_level.1`, `test-02`,
  `testmap2`). **Not mine, and measured rather than assumed:** my change
  contains no `.map` at all (`git diff --name-only HEAD -- '*.map'` is empty)
  and every failing map is byte-identical to HEAD, so those failures live in
  committed TERRAIN content. I did not A/B the brush pass pre-change —
  `--changed` is the contract and it reports "no maps to check".
  *Process note:* I stopped that run once it was into the brush pass rather
  than leave a Godot pair grinding unattended beside your open editor; it had
  already flushed both sections above, and its child exited on its own (Godot
  process count 11 → 9). The 9 remaining are your editor and the sibling lanes'
  runs — **I killed none of them**, deliberately.

**Needs the human.**

- **The Godot editor is open and three files were deleted under it.** Its
  `.godot/global_script_class_cache.cfg` still registers `DebugOverlay` and
  `filesystem_cache8` still lists all three. That is stale cache, not a
  reference — it clears on the editor's next scan — but expect the editor to
  grumble once, and if `master.tscn` or `world.tscn` is open, **reload before
  saving** so it does not write back a stale copy of `master.gd`.
- **`master.gd` is a shared/core file.** It is the only file outside the HUD
  folder that changed. Worth a read of the diff: 45 lines out, 25 in, all of it
  the tutorials path plus one comment.
- **Not rendered, and nothing to render.** The deleted screens were reachable
  by nothing, so no pixel changes. The one screen the change touches is the
  pause menu, and `_show_pause_menu`'s item list was not edited — there is no
  `shot_` tool for the pause menu, and writing one was out of scope. If you
  want eyes on it, ESC in game is faster than a new tool.
- **Game feel: not assessed.** I did not play it, and this change should have
  no feel at all — but that is a prediction, not a verdict.

**Blocked / next.** Nothing blocked. **H15 is now unblocked and smaller than
its row assumes** — the library half of `test_tutorial.gd` is already gone, so
H15 inherits only the depot-facing half. H8/H15 should decide
`TutorialLabel.in_library`'s fate; the count it needs is in this entry. Vault
updated: `Backlog` H19 → DONE, `Decisions` line 25 given an "Executed
2026-10-24" clause, `Reference/HUD and barks` tutorial-channel and
questionable-content entries moved from DEPRECATED to DELETED, and **`Where the
truth lives`' "what does a level's tutorial teach" row rewritten** — its real
answer was a file this ticket deleted, which is the one row that would have
actively misled the next session.

**I was wrong about one thing, and corrected it.** The first tombstone comments
I wrote dated the deletion 2026-10-23, which is the date the *decision* was
taken; the deletion is 2026-10-24. Fixed in all three files before reporting.


---
## 2026-10-24 — H7 and H5: a decoy catalogue deleted, and test.sh can no longer hide a failure

**Landed.**

**H7.** `Campaign/item_catalogue.tres` deleted. **It was a SEVEN-item stub**
(m4, shotgun, repair_kit, frag, optics, repair_tool, scanner, plus one
chassis) — the backlog row said nine, `build_chassis_marks.gd`'s comment said
nine, `test_pricing.gd`'s said ten, and the vault said nine. **Four records of
a decoy's size, all wrong**, which is a fair description of what a decoy does
to everything that mentions it. Nothing loaded it: those two comments were the
only references in the repo, and both are rewritten with real figures — the
live catalogue is **32 items and 12 chassis**, not the 34 one of them claimed.

**H5.** Ported from `bucket.sh` into `tools/test.sh`:
`TIMEOUT="${SUITE_TIMEOUT:-240}"`, the `timeout` wrapper, a 124 branch that
counts a timeout as a failure, and `TIMED_OUT_NAMES` in the verdict. The
comment carries the reason a timeout here is not just slowness: **`quit()` is
the last line of a suite's `_init()`**, so a runtime error aborts before it and
the SceneTree spins forever — which is how `test_line_specs` timed out at 240s
this morning instead of printing a FAIL.

**H5 grew a second half, found by using it.** Asked "which fast-tier suites
failed?", `test.sh` printed *"SUITE FAILURES — see above"* over a **1.7 MB
log** and named nothing. And the common failure here **exits 139 with no FAIL
line at all** — every assertion clean, then a segfault in cleanup — so there
was nothing to grep for either. **A failure you cannot locate is the one that
gets called pre-existing without being checked**, which is the mistake this
lane nearly made this morning. Added `FAILED_NAMES`, with the exit code per
suite.

**Gates.** `bash -n tools/test.sh`: OK. `check.sh --changed`: **PASS**, 17
scripts, 11 scenes/resources.

**The timeout was proven by firing it, not by seeing green.** `SUITE_TIMEOUT=3`
capped 38 suites and exited 1; `=6` capped 27 and named every one; the default
cap produced **no** spurious timeout across 66 suites.

**`bash tools/test.sh --fast`, default cap, 66 suites run (40 skipped, 2
parked):** `failed: test_arena_assault(139) test_core_retake_live(139)
test_hillfort_live(139) test_site_win(139)`. **Four suites, all SIGSEGV, and
nothing else.** Re-run individually: each exits 139 with **zero** FAIL lines.
Confirmed across the whole 1.67 MB capture that **no suite printed a single
assertion failure** — so nothing is logically broken, including the five frames
whose mark ladders this lane rewrote earlier today.

**H10 rewritten with that evidence.** It is at least 6 suites across 2 buckets
(the four above, `test_ammo` at exit 1 with leaked ObjectDB instances, and
`probe_mission_facts.gd` after a full Master deploy), it is one teardown or a
small family rather than six bugs, and all four confirmed ones deploy and tear
down a real level. That is where to start.

**Needs the human.** Nothing in-editor. `tools/test.sh` is a **shared file** —
flagging it explicitly.

**Two items of the four asked for were already done, and one of them was my
own error.** H11 had been fixed by another lane the previous day, and their
wording is more accurate than the finding that opened the row: I had concluded
"no shipped site uses FuncGodot" from grepping `_level.tscn` only. **Every
site's `_art.tscn` is full of FuncGodot brushes** — 8 to 515 references each.
Same mistake as three others this week: grep the file whose NAME matches the
concept, miss the one next door. The D2 chat had already caught it and
corrected `Traps` and `Where the truth lives` with better evidence than I had.

H8 was already resolved into H15 on 2026-10-23, and **H15 already listed the
eight depot consumers this lane then rediscovered from scratch** — a stale
read of a backlog that had grown by roughly twenty rows. H15 is a session of
its own: repoint `test_tutorial` off the decoy it currently tests, then eight
tools, then retire the level and its minimap, partly behind H19.

**Not verified.** Nothing played, nothing rendered; neither item touches
anything on screen. No claim about feel.

**Blocked / next.** H15 is the outstanding half of what was asked. H10 is now
well enough characterised to be worth a session.

## 2026-10-24 — RB2/RB3/RB4 as one deletion pass: bosses, the dead templates, and the robot FGD

**Landed.** Nine files deleted, four edited. Bosses are cut, the two bare-`Enemy`
scenes are gone, and robots no longer go through FuncGodot's FGD at all.

Deleted: `Character/characters/ai/miniboss.gd`, `boss_guardian.tscn`,
`enemy_template.tscn`, `enemy_shotgun.tscn`, and the entity resources
`fgd_boss_guardian.tres`, `fgd_enemy_shotgun.tres`, `fgd_enemy_chaser.tres`,
`fgd_enemy_leaper.tres`, `fgd_world_bonfire.tres`.

Edited: `addons/func_godot/fgd/func_godot_fgd.tres` and
`trenchbroom/robot_fgd.tres` (both stripped to `fgd_world_ceiling-lamp` only),
`maps/appendix/civil-unrest_level.tscn`, `Campaign/kill_kinds.gd` (comment
only), `tools/probe_body_facts.gd` (a print string that named `Boss`).

**THE BACKLOG ROW FOR RB4 WAS WRONG, AND WRONG IN THE PROJECT'S OWN SIGNATURE
WAY.** It said four entity resources were "outside the FGD", read off
`trenchbroom/robot_fgd.tres`, which lists two. **That file has
`base_fgd_files = [func_godot_fgd.tres]`, and the base listed all six** — so
TrenchBroom could reach every one of them through the inheritance chain. The
finding that warned about one-file inferences was itself a one-file inference.

RB4 also said to delete `robot_fgd.tres`. **`trenchbroom/trenchbroom_config.tres`
names it as `fgd_file`**, so deleting it would have broken map authoring for
the arena and the proving ground, which are live. It was kept.

**The test that actually settled liveness was the one neither pass had run:
which `.map` names the classname.** Only `maps/civil-unrest-4.map`, for
`boss_guardian`. Nothing placed the other five — `fgd_enemy_leaper` and
`fgd_world_ceiling-lamp` included, which were the two "registered" ones.

**Three judgement calls, all flagged rather than taken quietly.**

1. **`kill_kinds.gd`'s `enemy_shotgun` and `boss_guardian` strings STAY**, and
   now carry a comment saying why. On inspection they are genuinely dead
   lookups — a deleted scene can never produce a kill, and `guardian` was never
   a kind with a chassis. But this table is read when a debrief resolves a
   kill, career tallies in `campaign.json` may carry what they resolved to, and
   two dead dictionary entries cost nothing against orphaning a player's stats.
2. **`fgd_world_ceiling-lamp` survives.** It is not a robot, and no decision
   about robots reaches a lamp.
3. **Surgery on an archive level rather than deleting it.**
   `maps/appendix/civil-unrest_level.tscn` instanced all three doomed scenes,
   so six nodes and three `ext_resource` lines came out and `Squad2`'s
   `squad_members` was repaired (it named two of the removed nodes). **This is
   a cross-lane edit — `maps/` is TERRAIN's.** Chosen over deleting the level
   because deleting authored content nobody asked about is wider than the
   ticket.

**Gates.** `check.sh --changed`: **PASS** (15 scripts, 11 scenes/resources) —
**after it caught me**: removing three `ext_resource` lines left
`load_steps=360` where 357 was expected. `smoke.sh`: **PASS**, booted clean,
15s, 1 warning. `bucket.sh frames`: **PASS, 29 suites**. `bucket.sh terrain`:
**PASS, 13 suites** (3 report-only, 1 PARKED). `probe_body_facts.gd`: exit 0,
and **orphan body scenes fell from 5 to 2** — the survivors being
`capture_anchor.tscn` and `tick.tscn`, both of which have live second routes.
`bucket.sh campaign` and `kit` **not re-run** after this pass; they were green
to their known-red baseline earlier the same day and nothing here touches
campaign state or items.

**Needs the human.** **`maps/civil-unrest-4.map` still contains a
`boss_guardian` entity**, so `civil-unrest_level.tscn` now diverges from its
own source and regenerating it would fail on a deleted entity. It is an
archive map nothing builds from, and the `.map` is TERRAIN's, so it was left
alone — but it is real residue and somebody should decide whether the map goes
too. Also: `CLAUDE.md` is untouched and still describes levels as TrenchBroom
brush geometry, which is [[Backlog]] H11.

**Not verified.** Nothing was played, nothing was rendered — this pass removed
only unreachable content, so there was nothing to look at. No statement is made
about feel.

**Blocked / next.** H7, H5 and H11 are the cheapest remaining hygiene items and
were checked rather than assumed: **nothing loads the 9-item stub catalogue**
(only two comments mention it), `bucket.sh` already holds the entire per-suite
timeout that `test.sh` lacks and its own comment at line 36 names the gap, and
H11 is one paragraph. A1 is queued in the vault's `## Now`.

## 2026-10-24 — the vehicle mark ladders redesigned, and the suite that hung instead of failing

**Landed.** Six chassis ladders rewritten to the human's spec, in
`Campaign/chassis/`: every turret line now starts on the **Ancient Machine
Gun** and earns its real gun later.

| line | Mk 0 | Mk 1 | Mk 2 |
|---|---|---|---|
| Walker | ancient mg | autocannon | autocannon + heavy_mg |
| Bulwark | ancient mg | heavy_mg | heavy_mg |
| Kite | ancient mg | heavy_mg | heavy_mg |
| Rover | ancient mg | ancient mg | heavy_mg |
| Picket | rocket_pods | rocket_pods | rocket_pods |
| Lance | light_cannon | light_cannon | light_cannon |

Mk 0 is `starting_weapon_id` on the `[resource]` block; Mk 1 and Mk 2 are the
two `ChassisMark` sub-resources, in declaration order.

**Picket and Lance keeping one gun the whole way is deliberate** — they buy
hull, sensors and accuracy. Recorded in the vault's `Decisions` so nobody
"upgrades" them back.

**The whitelists went backwards, on purpose.** Five of the six widenings from
the SQ1 fix earlier the same day became unnecessary — Bulwark and Lance no
longer touch the autocannon, nobody but Lance needs the light cannon, Kite
does not want rocket pods, Picket wants neither mortar nor cluster launcher. I
**reverted all five** rather than leave unused permissions in the data looking
like intent, which also undid the one narrowing I was uneasy about
(`cluster_launcher` is back to an empty whitelist). Net change across both
passes: **`heavy_mg` gains `kite`, `machine_gun` gains `bulwark`.** Nothing
else moved.

**A suite I broke, and the trap underneath it.** `test_line_specs` read
`mark_spec(1).weapon_ids[1]` — valid while Walker Mk 1 filled both mounts,
out of bounds the moment Mk 1 became a single autocannon. **It did not fail;
it hung, and the bucket killed it at 240s.** `quit()` is the last line of
`_init()`, so an error that aborts the function never reaches it and the
SceneTree spins forever. Repointed the check at Mk 2 — now the tier that fills
the second mount, so the suite's intent is unchanged — and made the expected
value compute defensively, so a future ladder change turns it **red instead of
silent**. The trap is in the vault's `Traps`; it is also the argument for H5.

**Gates.** `check.sh --changed`: **PASS**. `probe_chassis_marks.gd`:
**0 problems, exit 0** — and it was the `takes()` assertion added in the SQ1
pass that proved all six ladders legal, including `machine_gun` on the Bulwark
turret. `probe_squad_facts.gd` §8: **0 refused combinations**.
`test_line_specs` alone: **44 PASS, exit 0**. `bucket.sh kit`: **16 suites, 1
failed — `test_ammo`**, pre-existing, A/B proven by reverting the whole SQ1 fix
and re-running. `bucket.sh campaign`: **42 suites, 1 PARKED, 5 failed** —
H10's exact five, and the run fell from 9m20s to 5m37s once the hang was gone.
`smoke.sh` **not run**.

**Needs the human.** **Twelve `.tres` files changed on disk while the editor
was open** — six chassis, six items. Reload before touching the inspector.
Nothing else needs in-editor checking.

**Not verified: whether any of this is any good.** Nothing was played and
nothing was rendered. Four lines now open on a gun that is explicitly the old
and feeble one, two lines never change weapon at all, and **whether that
progression reads as earning something or as being under-equipped for two
tiers is a feel question that was not tested.** The mark prices up the rail are
still unplayed. Both are the human's.

**My own mistakes this session, plainly.** One: I reported the SQ1 whitelist
widening as the fix, and the ladder redesign immediately made five sixths of it
dead — the widening was correct for the design as it stood and I should have
asked whether the ladders were settled before touching their permissions. Two:
I broke `test_line_specs` and would have reported the campaign bucket as
"H10's five, unchanged" if I had not checked the one new name against
yesterday's list.

**Blocked / next.** C5 (Reclaimer's second arm) is specced and carries one
design question inside it: `weapon_replaces_built_in` is a single boolean for
the whole frame, so with two slots it has to mean "the first mount replaces the
welder, the second does not" or the welder dies anyway. RB2/RB3/RB4 remain one
coherent deletion pass.

## 2026-10-24 — SQ1: six production lines no longer disarm themselves on load

**Landed.** Six `chassis_whitelist` fields widened, in `Campaign/items/`:
`item_autocannon` (+bulwark, +lance), `item_light_cannon` (+walker, +bulwark),
`item_heavy_mg` (+kite), `item_rocket_pods` (+kite), `item_mortar` (+picket),
`item_cluster_launcher` (empty → `[picket]`). Plus one assertion added to
`tools/probe_chassis_marks.gd`.

The bug, found by D6: `apply_line_spec()` writes a mark's ids without asking
`ChassisDefinition.takes()`. Eight authored (line, mark, id) rows failed that
gate — **every upgrade the Bulwark, Kite and Picket had**, plus Walker Mk 2 and
Lance Mk 2. It played fine, because `SquadSpawner._fit_loadout` only checks
`fits_ai()`. Then on load `_return_unfittable_squad_kit()` asked `takes()`, put
the gun in stores, and nothing refilled the mount.

**It was data, not code.** The marks were the design intent; the whitelists
were stale relative to them. Two things worth recording:

- **`requires_chassis` is read by no game code at all** — only
  `audit_economy.gd` and two probes. `fits_chassis()` reads
  `chassis_whitelist` only. The obvious fix of "widen whitelist *and*
  requires_chassis" would have been half wasted.
- **7 of 8 failed `fits_chassis()`; the 8th failed the turret clause.**
  Picket Mk 1's `cluster_launcher` had an *empty* whitelist, which passes
  "fits everything" and then fails "a turret insists on being named". Naming
  picket **narrows** that item — checked first that Picket's mark is the only
  squad-side namer and that the player's carry path does not go through
  `takes()`.

**The durable half.** `probe_chassis_marks.gd` printed `0 problem(s)` while all
eight rows were broken — it checked catalogue resolution, mount counts and
duplicate tiers, but never the frame's own gate. It now asserts
`frame.takes()` on every (line, mark, id), **and the assertion was proven by
reverting one row and watching it go red at exit 1**, not just by seeing green.

**Gates.** `check.sh --changed`: **PASS** (13 scripts, 6 scenes/resources).
`probe_chassis_marks.gd`: **0 problems, exit 0** — was 0 before the assertion
existed, and the negative test confirms it now bites. `probe_squad_facts.gd`
§8: **0 (line, mark, id) combinations refused, down from 8** — the probe that
found the bug confirming it end to end. `bucket.sh kit`: **16 suites, 1 failed
— `test_ammo`**, which is **pre-existing**: every assertion PASSes, there is no
FAIL line, and it exits non-zero at teardown with leaked ObjectDB instances.
A/B'd by reverting the whole fix and re-running — still exit 1. That is H10's
signature, so H10 is now **at least 6 suites across 2 buckets**, not 5 in one,
and the row has been widened to say so. `smoke.sh` and `bucket.sh campaign`
**not run**.

**Needs the human.** Six `.tres` files changed on disk **while the editor was
open** — reload them before saving anything from the inspector, or Godot will
write the old whitelists back. Nothing else needs in-editor checking; no scene
wiring moved.

**Not verified: anything about how this FEELS.** Nothing was played and nothing
was rendered. Six lines can now keep the guns their marks always promised, and
whether Bulwark Mk 2's light cannon or Kite Mk 2's rocket pods are any *good*
on those frames is untested and unjudged — that is a balance question and it is
the human's. The mark prices up the rail remain unplayed, as recorded in the
vault's `Open`.

**Blocked / next.** RB2/RB3/RB4 are one coherent deletion pass now that bosses,
`enemy_template.tscn` and the robot FGD path are all decided cut. RB1 is a
one-line `push_error` in `lab.gd:265` and should just be done inline rather
than tasked.


## 2026-10-23 — D7: the order layer written down, nothing in the game changed

**Landed.** `Reference/Orders and squad AI.md` in the vault, and
`tools/probe_order_facts.gd` — the only two files added. **A reading job:
`squad.gd`, `squad_commander.gd`, `enemy.gd`, `soldier.gd`, both spawners and
the equipment kit were read, not edited.** The probe is new in `tools/`, which
is GAMEPLAY's; nothing shared was touched in the repo.

What is now written down, after a real deploy on `basin_1_anchor` and
`hfw_1_fort`:

- **The player has TWO live verbs, not four.** Tap T issues
  `Verb.ADVANCE`, which sets **`SquadObjective.DEFEND`** — the verb is the old
  DEFEND renamed, and `SquadObjective.ADVANCE` is reached by no player verb at
  all. Hold T sets `FOLLOW`. `Verb.CONTACT` is passed by nothing;
  `Verb.ATTACK` has **no `case` in `_issue_order`'s match** and so marks the
  ground and tells the squad nothing.
- **`SquadObjective.WITHDRAW` has no setter anywhere** — scanned, every `.gd`
  outside `tools/` — and `AISmoke.can_use()`'s first trigger tests for it, so
  "screen the withdrawal" can never fire.
- **Nothing appoints an NCO**, so `OVERWATCH` and `FLANKER` are unassignable,
  `FALLBACK` is assigned nowhere, and **the player's squad never bounds** —
  both orderable objectives route to `_defensive_assign_roles`.
- **`Squad.default_objective` is read by nothing live**: it needs
  `target_objective`, which is authored on zero nodes. Your squad therefore
  arrives in a mission on `NONE`.
- `assault_combat_leash` is exported and read by no code; `player_ordered` is
  read only by analytics while its comment claims it decides things.

Nine rows opened as `OA1`–`OA9` in the vault's `Backlog`, five of them wanting
a design call rather than a fix. Five new traps and five new
`Where the truth lives` rows; **one existing row in that file corrected** — it
said `DEFEND` was not orderable, and `DEFEND` is what the tap sets.

**Gates.** `check.sh --changed`: **PASS** (12 scripts). `bucket.sh frames`:
**PASS, 29 suites, 8m10s**, slowest `test_mortar` at 62 s. `smoke.sh`: not run
— nothing that loads at startup changed. `test.sh`: not run, and never will be
from here.

`probe_order_facts.gd` prints **10/10 PASS** and its verdict line. **Its exit
code is 139 and that is not its bug** — any tool that boots `master.tscn`
under `--script` segfaults in cleanup after `quit()`, measured today on
`probe_home_base.gd` too (332 resources still in use, ObjectDB leaked).
Freeing the `Master` first does not help. That is why it is a `probe_` with a
printed verdict and not a suite, and it is more evidence for Backlog H10 —
the five red `campaign` suites are probably one teardown.

**Needs the human.** Nothing to check in-editor; no scene, resource or script
in the game was modified. What needs a person is the five judgement calls in
`OA1`–`OA9`: whether a squad should ever withdraw on its own, whether "send
the vehicles at that one" is a verb worth wiring, whether the player's squad
should bound while holding a point, whether it should fall in on you at a
mission start, and whether `Verb.ATTACK` should be dropped. **Every leash,
follow distance and interval was deliberately left out of the backlog** and
recorded as a feel number in the reference note instead.

**Not verified.** Game feel and balance — not played, only run headless.
Whether the squad standing still on `NONE` at a mission start reads as broken
or as correct in the hand is exactly the judgement running it cannot give.
Both deploys were headless, so nothing visual was rendered or looked at;
nothing in this session changes anything on screen.

**Reversal to record.** The finding handed to this session said `DEFEND`,
`WITHDRAW` and `PATROL` "cannot be ordered by the player". Two thirds right:
`DEFEND` is the single thing the player orders most. The mistake is the
natural one — reading the two enums and matching the names — and it is now a
`Where the truth lives` row so the next reader does not repeat it.

**Blocked / next.** Nothing blocked. `OA9` and `H10` are the same
investigation and worth one session. `RB6`'s suggested D9 (`enemy.gd`'s
movement and navigation) is still the largest undocumented subsystem.

---

## 2026-10-23 — D8: the robot body's class hierarchy written down, nothing in the game changed

**Landed.** A reading job from the vault brief `Briefs/D8 — The robot body`.
**One new repo file; no game file touched, nothing committed, no branch made.**

- `tools/probe_body_facts.gd` (new, `# REPORTS:`, exit 0, ~2s) — prints five
  sections: the class chain of all 23 body scripts read off
  `Script.get_base_script()`; every `ChassisDefinition` with its root script,
  class, whether a spawner can place it and whether it is route A or route B
  armed; the body scenes no chassis claims; what each layer declares; and the
  full `AI` member list plus the names `enemy.gd` and `test_character.gd`
  declare twice. **Nothing is instantiated** — every answer comes from
  `Script` and `SceneState`, so it does not need a level or run `_ready`.
- Vault, outside the repo: `Reference/The robot body.md` (new), plus appends
  to `Traps`, `Where the truth lives`, `Backlog` (RB1–RB6), `Open` and `Home`.

**Three things worth the board's attention, all read-only findings.**

1. **All three spawners cast `as Soldier`** — `squad_spawner.gd:273`,
   `enemy_force_spawner.gd:335`, `lab.gd:265`. A body on bare `Enemy` cannot
   be placed by anything, on either side. `lab.gd` is the only one that drops
   it **in silence** (RB1). `enemy_template.tscn`, the scene a new frame is
   copied from, is bare `Enemy` (RB3).
2. **`AI` carries the signal system and nothing else.** `health`,
   `max_health`, `faction`, `alive`, `gravity`, `handle_movement`,
   `apply_damage`, `die` and 9 more are declared **twice**, independently, in
   `enemy.gd` and `test_character.gd` — parallel declarations, not overrides.
   That is the root cause of the duck-typing (`if "health" in body`) and of
   `Campaign._write_back_player()` being a second, lossier copy of
   `SquadSpawner.write_back()` (RB5, BLOCKED pending the human).
3. **`Boss` / `miniboss.gd` / `boss_guardian.tscn` is unreachable from every
   direction** — no callers, no chassis, extends `Enemy` so no spawner would
   take it, its only body sits in an unreferenced level chain, and its FGD
   entity is not in `trenchbroom/robot_fgd.tres`. Second routes checked;
   **not deleted** — authored content needs a design call (RB2).

**Gates.** `check.sh --changed`: **PASS** (12 scripts). `bucket.sh frames`:
**PASS, 29 suites, 8m9s**, slowest `test_mortar` at 63s. The probe itself runs
clean headless and exits 0. `smoke.sh` not run — nothing that loads at startup
was touched. `test.sh` not run, ever.

**Needs the human.**

- **Nothing to check in-editor.** No `.tscn`, no `.tres` and no game script
  was opened for writing.
- **Two judgement calls are flagged in the handback, not in the docs**: whether
  the Walker/SpotterDrone/rover "what you give up" table is the right framing
  for someone adding a chassis, and whether `Boss` is dead or merely parked.
- **Game feel and balance: not verified.** Nothing was played and nothing was
  rendered — this session ran no `shot_` tool because it produced no visual
  change.

**Blocked / next.** RB6: `enemy.gd`'s movement-and-navigation subsystem is
~1,040 of its 5,787 lines and is the one part of the file that earns its own
reference doc. Everything else in there is either small or already covered by
the vault's `Atlas/Robots and AI`.

---

## 2026-10-23 — D6: the campaign-layer robot written down, nothing in the game changed

**Landed.** A reading job from the vault brief `Briefs/D6 — Your squad`. One
new repo file; **no game file touched, nothing committed.**

- `tools/probe_squad_facts.gd` (new, `# REPORTS:`, exit 0, ~15s) — boots a
  DETACHED CampaignManager off `world.tscn`'s own packed values, the way
  `probe_economy_facts.gd` does, and prints eight sections: every record's
  frame / line mark vs record mark / fitted ids / state / career / all eleven
  derived fields; whether a second `recompute_stats` moves anything; whether a
  plain `Array` survives each of the four typed exports; `to_dict()`'s keys
  derived against the record's export list plus a no-recompute round trip;
  the mark-vs-line divergence across a real `restore_from`; the precedence
  arithmetic; `can_fit()`; and every authored (line, mark, id) row against
  `ChassisDefinition.takes()`. **Not `# BUCKET:`ed even though the brief asked
  for it** — `bucket.sh` globs `tools/test_*.gd`, so the tag on a probe is read
  by nothing. Same call D5 made. Logged as vault Backlog SQ4.
- Vault: `Reference/Your squad.md` (new); appends to `Backlog` (new section,
  SQ1–SQ6), `Traps` (three), `Where the truth lives` (five rows).

**What the probe found that was not known.** Three worth the human's eye:

1. **Six lines are armed by their marks with kit the frame's own `takes()`
   refuses** — 8 rows: walker Mk 2, bulwark Mk 1+2, lance Mk 2, picket Mk 1+2,
   kite Mk 1+2. `apply_line_spec` never asks, `_fit_loadout` checks only
   `fits_ai()`, so it plays fine — and then `_return_unfittable_squad_kit()`
   runs **on load** and takes the gun off. Measured: a Bulwark on a Mk 1 line
   loads with `weapon_ids [&""]` and the autocannon in stores, and nothing
   refills the mount. → SQ1, which needs a design call before a fix.
2. **`effective_tuning` is written by `recompute_stats` and read by nothing.**
   Six authored (line, mark) pairs; no reader for `repair_rate`,
   `salvage_rate` or `reload_rate` anywhere in `Character/`, `Campaign/` or
   `Managers/`. → SQ2.
3. **All four typed `@export` arrays on `SoldierRecord` drop a plain `Array`
   from script**, silently — K1's class of bug, reachable from code. → Traps.

**Gates.** `check.sh --changed`: **PASS** (12 scripts, shared checkout — most
of those are other lanes'). `bucket.sh campaign`: **42 suites, 1 PARKED
(`test_tutorial`), 5 failed** — `test_arena_assault`, `test_core_retake_live`,
`test_hillfort_live`, `test_sim_arena`, `test_site_win`. That is **exactly**
Backlog H10's five, each printing `0 failure(s)` and dying in cleanup; nothing
here touches them. `probe_squad_facts.gd` and `probe_chassis_marks.gd` both
run clean (the latter: 12 lines, 0 problems). Did **not** run `smoke.sh` —
nothing loads at startup that changed. Did **not** run `bucket.sh frames`.

**Needs the human.** SQ1 is the one: widening the turret whitelists and
`requires_chassis` on `autocannon` / `light_cannon` / `mortar` /
`rocket_pods` / `heavy_mg` / `cluster_launcher` changes what six lines can
hold, so it is a content call, not a refactor. SQ6 (`Status.WOUNDED` is
written and never read) needs a design call on whether a wound should cost
anything. **Nothing was verified by playing**, so nothing here is a statement
about how the Factory or the squad page feels.

**Blocked / next.** SQ3 and SQ5 are small and uncontroversial. SQ4 wants to
land with SV1. I touched `docs/reports/GAMEPLAY.md` — **two sibling GAMEPLAY
chats (D7, D8) were running at the same time**, so if this entry sits oddly
against theirs, that is why.

---

## 2026-10-23 — D5: HUD and barks written down, nothing in the game changed

**Landed.** A reading job from the vault brief `Briefs/D5`. One new repo file,
no game file touched:

- `tools/probe_hud_facts.gd` (new, `# REPORTS:`, but **exits 1 if any chassis
  frame is mute on any line**) — instances every chassis scene and every AI
  scene with a Bark, out of the tree, and prints per line which array the
  voice actually plays from (`bark_set`, its `fallback`, `bark_clips`, or
  none). Also every BarkSet on disk, `BarkDirector`'s constants, a measured
  check of the NCO bonus, the comms log's vocabulary from `_compose()`, the
  HUD scene's children, the filter's real uniforms, and every signal
  `world.tscn` wires into the HUD. Static, under a minute, exit 0.
  **Not `# BUCKET:`ed** even though the brief asked: `bucket.sh` only collects
  `tools/test_*.gd`, so the tag on a probe would be read by nothing.
- Vault: `Reference/HUD and barks.md` (new); `Traps`, `Where the truth lives`
  (voice row corrected, tutorial row corrected, two rows added), `Home`
  extended; Backlog D5 done, **K13–K16** added, K1 re-scoped, H6 given a
  lead; the brief's status.

**The finding.** `bark.tscn` assigns `bark_set_droid.tres` to every Bark, and
that one BarkSet has clips on all seven lines — so **`bark_clips` is reached on
none of 32 scenes**, and K1's dropped Bulwark clips cannot be heard. Frames
differ by pitch only; your Soldier and most enemy infantry share 0.96–1.06.
Second: `BarkDirector`'s NCO +1000 never applies (it compares `squad.nco`, a
Soldier, to the Bark node `bark()` passes) — measured 0 vs 1000. → K13.
Third: the shuffle bag's seam guard tests the wrong end and doubles the repeat
it exists to prevent. → K14.

**Gates.** `check.sh --changed`: PASS (4 scripts). `test_barks.gd`: exit 0,
3/3 checks. `bucket.sh shell`: PASS, 4 suites. `bucket.sh frames` **not run**
— nothing in it was touched. Render: `shot_arena_ops.gd` headful, 1152 × 648,
eye 1.50 m, through the filter, five frames, opened. It runs its own camera,
so the `F  SELECT MISSION` prompt in frame is from wherever the player body
stands, and it has no damage arcs, contact marks or scan sweep in it.
`BRAVO-4 IS DOWN` in the comms log is the induction's staged downing.

**Needs the human.** Nothing to check in-editor — no scene was edited. The
judgement calls: whether friendly `RELOADING` should be heard (K15); whether
the NCO should be the mouthpiece once K13 makes it possible; whether your
squad and enemy infantry should sound different (one BarkSet, same pitch).

**Follow-up, same session — the human ruled on the findings.** Tickets in the
vault Backlog: K13 re-scoped (NCOs are deprecated, so the bonus is removed, not
fixed; the squadless-HOSTILE half stays), K14 approved, K15 re-scoped to a
comment fix (friendly reload stays), K16 parked (scanner deprecated, coming
back), new **K18** (director: paused barks lost, one slot per channel, `reset()`
never called), **F6** (hostile voice), **S10** (one voice route, after F6),
**H19** (remove `DebugOverlay` and the tutorial library — H18 was taken by
another lane in the same minute). Decisions logged. Code: **deleted**
`Character/hud/hit_indicator.gdshader` and `horror.gdshader` (unreferenced;
tracked in git); DEPRECATED header comments on `debug_overlay.gd`,
`tutorial_library.gd` and `HUD.activate_scan_effect`; one comment in
`damage_directions.gd` updated for the deleted shader. Comments only otherwise.
`check.sh --changed` PASS (9 scripts), `smoke.sh` PASS. `bucket.sh shell` not
re-run for the comment-only edits.

**Blocked / next.** K13, K14 and K18 are small and READY. Mistake of my own: the
first run of `shot_arena_ops.gd` was given an absolute output path; it joins
everything to `res://`, so nothing was written until I passed
`.godot/d5_hud_shots`.

---

## 2026-10-23 — D4: saves and profiles written down, nothing in the game changed

**Landed.** A reading job from the vault brief `Briefs/D4`. One new repo file,
no game file touched:

- `tools/probe_save_facts.gd` (new, `# REPORTS:`) — prints every key of a v2
  save, script vars vs `to_dict` keys, what `from_dict` reads vs what
  `to_dict` writes, which `to_dict` containers are the live object, and — the
  point of it — **what `restore_from()` does not move**, measured by
  restoring a state of sentinels into a different state. Then replays
  `load_profile` and `new_profile` through a CampaignManager built from
  `world.tscn`'s packed values, checks `migrate()`, writes a save to a
  throwaway path and reads it back, and lists the keys and versions of the
  player's real saves (opened read-only). Static, under a minute, exit 0.
- Vault: `Reference/Saves and profiles.md` (new); `Traps`, `Where the truth
  lives`, `Home` extended; Backlog D4 done, **SV1–SV5** added (SV, because
  the Simplify section already owns S1–S6), one line added to D3's K12; the
  brief's status.

**The finding.** `restore_from()` moves 22 of the 29 fields. The seven it
misses — `line_marks`, `line_modules`, `turn`, `sites`, `under_attack`,
`under_attack_turn`, `lessons_seen` — are **never loaded by `load_profile`**
and **carried into the next profile** by `load_profile` / `new_profile`. So
every boot or CONTINUE comes up at turn 0 with the authored board and every
line at Mk 0, and the next autosave writes that over the file. The real saves
agree: `tdog.json` has four site ops cleared and `turn: 0`, `sites: {}`.
`test_endings.gd:179`, which the code cites as the guard, restores a state
into itself and cannot fail. → Backlog SV1 / SV3. **Not fixed — save
behaviour is ask-first.**

**Also found.** `CampaignState.save_path` defaults to `user://campaign.json`
and the `--script` backstop does not reach it (SV2). `last_played_utc` is never
stamped (SV4). A v3 save would load in this build (SV5). The project rename on
2026-10-06 moved `user://` from `app_userdata\Roboto` to `…\Data Center Wars`,
and the older saves are still in the old folder. **Every save on this machine
but one (`aa-2.json`) is v1, and so OUTDATED.**

**Gates.** check.sh --changed: PASS (4 scripts — includes other lanes'
uncommitted files). The probe: exit 0, and its before/after stat of
`user://campaign.json` and `user://saves` reads unchanged. It wrote only
`user://probe_save_facts/` (deleted on exit). `bucket.sh campaign`: **FAIL,
42 suites (1 PARKED), 5 red** — `test_arena_assault`, `test_core_retake_live`,
`test_hillfort_live`, `test_sim_arena`, `test_site_win`, each with **zero
`FAIL` lines**. That is exactly Backlog H10's list (exit in cleanup), and this
session changed no game code. Inside it: `test_profiles` 33/33,
`test_profile_menu` 32/32, `test_endings` 29/29. A before/after listing of
`app_userdata\Data Center Wars\saves` and `…\Roboto\saves` is identical; only
`logs/` and the suite's own `test_menu_saves/` sandbox moved.

**Needs the human.** SV1 — the go-ahead, and the rewind call: should a failed
run keep `lessons_seen` (today: yes, on purpose) while a load restores it?
That probably means two move lists. SV2, SV4, SV5 are each one line and each
touches the save, so they are yours to approve. Nothing to check in the
editor; no scene was touched.

**Blocked / next.** Not verified: the rewind row (read from `extract()`, not
run — though D3's K12 measured the Factory mid-mission); `adopt_legacy()`
re-adopting after every profile is deleted (read from the code — `--no-save`
switches adoption off, so the probe cannot run it); and that `tdog.json`'s
`turn: 0` was caused by this rather than predating territory.

## 2026-10-23 — D3: the economy written down, nothing in the game changed

**Landed.** A reading job from the vault brief `Briefs/D3`. One new repo file,
no game file and no number touched:

- `tools/probe_economy_facts.gd` (new, `# REPORTS:`) — reads the
  CampaignManager's values out of `Env/world.tscn` as packed data, puts them
  on a DETACHED `campaign.gd` (never in the tree, so it never opens the
  player's profile; `save_path` empty, autosave off) and runs the real
  `_seed_new_campaign()` + `_adopt_state()`. Prints the seed, both ledgers
  after a boot, every key format made to appear once, a site-capture test, a
  rewind test, and the full price table for 32 items and 12 frames, the 9
  Locations and the 19 missions. Static, seconds, exit 0.
- Vault: `Reference/Economy.md` (new); `Traps`, `Where the truth lives`,
  `Atlas/Campaign and board`, `Home`, `Open` corrected or extended; Backlog D3
  done, K11 and K12 added, S1 unblocked with D3's answer; the brief's status.

**Two things the brief and the vault had wrong.** `allocate()` is the
RESOURCE ledger, not compute — compute is `compute_held`, written by
`install_software()`/`buy_supply()`. And **held Locations pay no compute**:
`site_compute()` has no caller and `compute_free()` never reads it (K11).

**My own mistake, caught by the probe.** Its first run copied state with
`restore_from(to_dict())` and the scratch copies leaked purchases into each
other — because `to_dict()` returns the live `allocations` dictionary. That
turned out to be the real bug: `Campaign._pre_run` is taken the same way, so
a failed run keeps resources spent in the field and drops what they bought
(K12). The probe now deep-copies, and measures both snapshot shapes.

**Gates.** check.sh --changed: PASS. `bucket.sh campaign`: 42 suites, 1
PARKED (`test_tutorial`), **36 pass, 5 FAIL** — `test_arena_assault`,
`test_core_retake_live`, `test_hillfort_live`, `test_sim_arena`,
`test_site_win`, exactly Backlog H10's five, none touched by this session
(it changed no game file). `test_ledger`, `test_requisition`, `test_endings`
and `test_campaign_spine` pass. smoke.sh not run — nothing that loads at
startup changed.

**Needs the human.** Nothing in-editor — no scene or resource was touched.
Three design calls are now in `Open`: should held ground pay compute (K11),
is Argus's requisition in the game (nothing calls it), and is "nothing costs
anything per turn, repair is never charged" deliberate. **Not verified:** the
field-purchase path in K12 was measured on the ledger, not through a live
deploy with TAB; game feel and balance not touched or judged.

**Blocked / next.** K12 is READY and small. K11 waits on the Open question.

**Addendum, same day — the human answered the three questions.** Recorded in
the vault's `Decisions`, and the three are out of `Open`: holding a Location
gives its compute (not per turn); income comes from what you hold *after* the
mission; no upkeep, replacing dead robots is the upkeep; the ledger is never
over-allocated and Argus's requisition is not in yet; no purchases in the
field; `in_shop` stays as the research gate. Backlog rewritten to match: K11
now READY (one sub-question: does an attack's `compute_reward` still pay on
top), K12 is now "no purchases in the field" with the snapshot fixes folded
in, **K17** new (income one operation late), S1 split into **S7** (dead shop
calls and the stores), **S8** (`_kit_payout` and the SCRAP tooltip), **S9**
(retire `BUY_ITEM` — rename, never delete, enums are append-only). The probe
gained one line, which confirms a robot built on a Mk 1 line comes out Mk 1.
check.sh --changed: PASS. Bucket not re-run: the only repo change is that
probe line.

## 2026-10-23 — D2: levels written down, nothing in the game changed

**Landed.** A reading job from the vault brief `Briefs/D2`. One new repo file,
no game or level file touched:

- `tools/probe_level_facts.gd` (new, `# REPORTS:`) — walks every scene in
  `maps/` and `maps/appendix/` (27) and prints, per scene: live or not and
  what loads it (world.tscn missions/base, the Laboratory, dead missions,
  tool/suite references), terrain vs FuncGodot counted **through the art**,
  navmesh regions with polygons, the slice, and the markers the code looks up.
  Ends with an experiment: a level whose `_art` file is missing (written to
  `user://`, deleted after). Static, ~1 min, exit 0.
- Vault: `Reference/Levels.md` (new); corrected `Traps`, `Where the truth
  lives`, `Atlas/Levels and maps`, `Home`; Backlog D2 done, H11 reworded,
  H12–H17 added; the D2 brief's status line.

**I corrected the brief I was given.** Its "measured" section said zero
shipped sites use FuncGodot. That came from grepping the `_level` files only.
Every site's buildings are FuncGodot block prefabs in the `_art` scene, and
Georgetown and Polaris have no heightfield at all. The vault's Traps and Where
the truth lives had already repeated the wrong claim; both are fixed.

**Gates.** check.sh --changed: PASS. `bucket.sh terrain`: PASS, 13 suites
(3 report-only, 1 PARKED: `test_terrain`), 4m51s, shared tree. smoke.sh and
test.sh not run (nothing that loads at startup changed). The probe exits 0.

**Needs the human.** Three judgement calls are listed in the vault note. They
are heliostat (dead, or unconverted?), whether `appendix/valley_level` stays
as the suites' arena, and whether to delete the eight unreferenced scenes
(H17).

**Blocked / next.** H12 (Salient has no minimap) and H13 (Salient's ops layer
is restored by nothing) are the two with player-visible consequences.

**Follow-up, same day, on the human's answers.**
- **`CLAUDE.md` changed (shared file).** The "What this is" paragraph now
  describes both build routes and the level/art pair. H11 is done.
- **`tools/minimap_bake.gd` changed (TERRAIN's file, at the human's request).**
  `salient_level.tscn` is now in the list. **Not baked:** `minimap.sh` opens
  a window and then runs `--import`, which must not run with the editor open.
- **`tools/probe_level_facts.gd`** now prints the tag each slice entry marker
  resolves to. That found H20: on Georgetown, `GT_Mill` and `GT_Pier` resolve
  to untagged pins, so a reinforcement sent from either one spawns at the post
  nearest the player. This is probed and read from the code, not played.
- Vault: tickets H15 (deprecate the depot), H18 (Generate Terrain path) and
  H20 are new; H17 records that the human confirmed the old scenes as old;
  heliostat is recorded as WIP.
- check.sh --changed: PASS. The probe exits 0.

## 2026-10-23 — D1: missions and objectives written down, nothing in the game changed

**Landed.** A reading job from the vault brief `Briefs/D1`. Two new files, no
game file touched:

- `tools/probe_mission_facts.gd` (new) — per live mission, the authored
  objectives and what `active_objectives` keeps (`--static`, seconds), then a
  real deploy of all 19 that prints `ObjectiveTracker`'s list with each line
  marked `authored` or `RAISED`, the surviving exit gates, the site's core
  counts, and what `open_way_out()` would pay. ~10 min.
- Vault: `Reference/Missions and objectives.md`, plus rows in `Where the truth
  lives`, `Traps`, `Backlog` (K7–K10, H10, H4 updated), `Open`, `Home`.

What it found, all measured unless marked:
- **Every site op's one required objective is raised at runtime** —
  SiteSlice's `BunkerObjective`, no id. 18 of 19 live ops.
- **Mutaha**: both live ops prune two relays the slice has already seated
  cores on; `SiteOperation.held_cores()` counts the freed pair as held
  (2 on the attack, 5 on the defence), so `mutaha_3_defend` cannot reach
  GROUND LOST (that consequence code-read).
- **Coast, Mutaha, Salient** `LevelExit` instances have no
  `requires_objectives_complete` — stepping on the pad is a successful
  extraction at any time (read off the scenes, not walked).
- **`open_way_out()` pays for lines not done**: 940 res + 1 cpu on Polaris,
  720 Causeway, 680 Salient, 220 Georgetown. Defences pay their cores' rewards
  (up to 1,500 res + 3 cpu), against §2's "a defence pays nothing".
- 19 dead objective ids across five levels, second route checked.
- The campaign is won by clearing `missions.back()` = `basin_2_defend`.

**Gates.** `check.sh --changed`: PASS (65 scripts, 42 scenes).
`bucket.sh campaign`: **FAIL — 42 suites, 1 PARKED, 5 failed**:
`test_arena_assault`, `test_core_retake_live`, `test_hillfort_live`,
`test_sim_arena`, `test_site_win`. I changed no game file. Three print
`0 failure(s)` and exit non-zero; `test_site_win` re-run by hand segfaults in
cleanup (exit 139). Two stop with no summary. Not root-caused — vault Backlog
H10. smoke.sh not run (nothing that loads at startup changed).

**My own mistakes.** First draft of the note said winning at Hillfort paid
~120 res for uncaptured optional cores. Wrong: `HoldableCore._guard_authored`
un-ticks a core line whose core is not yours. Caught by adding the payout
measurement to the probe; the real free money is on non-core lines. I also
added a "free Master before quit" to the probe believing it cured its exit
139. It did not; the comment now says so.

**Needs the human.** The four judgement calls now in the vault's `Open`:
does a bunker win clear the whole map, should a defence pay objective rewards,
is `basin_2_defend` meant to be the campaign's win, and is
`salient_1_overthetop` meant to be repeatable. None of the game feel was
played.

**Blocked / next.** K7 (Mutaha cores) and K10 (labels) are READY and small.
K8 touches TERRAIN's level files. H10 is worth doing before anyone trusts the
campaign bucket again.

**Landed.** The human asked for a step between the button and the money: a
screen showing Mk 0 / Mk 1 / Mk 2 and what each carries.

Most of it already existed. `_line_detail` has drawn the rail since the Mark
system landed — **it was simply unreachable from UPGRADE.** `UPGRADE <cost>`
on the card called `_advance` and charged you on the spot, and the only route
to the rail was the MODULE button, which is locked until the top mark. So on
a Mk 0 line there was no way to see the ladder at all. The one decision this
system asks for was the one thing you could not look at first.

- **Both corner buttons open the line.** `UPGRADE 150 ▸` and `MODULE 400 ▸`,
  and **neither is disabled any more** — looking is always allowed, and a
  line you cannot afford is exactly the one you want to read. The colour
  carries affordability; the page behind carries the refusal.
- **`_adopt_row` is the only thing on that page that spends.** `ADOPT MK 2
  300`, with `REVISES 1 IN SERVICE` beside it, or `SHORT 210` when you cannot.
  A refusal is a sentence rather than a greyed button: you reached this page
  deliberately.
- **The rail marks what each mark ADDS with a `+`.** Every tier still lists
  its whole kit — the question is "what does a Mk 2 carry" — but three nearly
  identical lists is a spot-the-difference puzzle. **Matched as a multiset,
  not with `has`**: the Soldier goes one frag at Mk 1 to two at Mk 2, and a
  membership test would have called the second one carried-over and shown no
  change for something you paid for. Mk 0 takes no prefixes; it is the
  baseline.
- **The NEXT MARK bars are bounded** to the rail's width. They were filling
  the screen: HULL 200 → 220 drawn as 1800 px of bar with a 90 px ghost on
  the end, on a readout whose entire job is making that gain obvious.
- `_last_built` now prints on the detail too — `rebuild()` returns before it
  for a detail view, so adopting from here confirmed itself onto a screen the
  player was not looking at.

**A bug I found by photographing a line I had not photographed before.**
`ItemDefinition.effect_summary()` built the Utility Harness's text with
`"x%.3g CHARGES"`, and **GDScript's `%` has no `g` conversion** — it logs
"unsupported format character" and hands back the format string unchanged. The
harness has been advertising its own source code wherever its effect is drawn,
and it is the only item in the catalogue with a quantity multiplier, so
nothing hit it until a frame that TAKES the harness got a shot. It reads
`X2 CHARGES` now, and `smoke.sh` went from 3 warning lines to 1.

**Gates.** `check.sh --changed`: **PASS**. `smoke.sh`: **PASS**, 15s, 1
warning line. `test_squad_manager` **101/101** (up from 91 — ten new, all on
this flow), `test_line_specs` 44/44, `test_line_opening` 19/19,
`test_memory_screen` 38/38, `test_item_facts` 1/1. **Not `test.sh`.**

The spend check is the point of the new block: a one-character slip back to
`_advance` in the corner restores the old behaviour exactly, and every other
check on that page would still pass.

Rendered and opened: `live_factory_open.png` (the card corner, which was
never photographed before — every line in the old shot is shut, so it showed
OPEN LINE and nothing else), `live_factory_line.png` (Rover, Mk 1, with
`SHORT 210`) and **`live_factory_line_kit.png`** (Soldier — the line whose
marks carry equipment, and the one that proves the multiset diff: `MARK I` /
`FRAG` / `+ FRAG`).

**Needs the human.**
- **Prices and pacing are unjudged.** I ran it, I did not play it. Whether
  150 → 750 up the rail is right, and whether `+` is a strong enough mark for
  what a tier adds, are yours. Dimming the carried rows was the first version
  and it read as DISABLED, which is why it is a prefix.
- **Shared file touched:** `Campaign/item_definition.gd`, for the format bug.
  `maps/proving_level.tscn` and the hud/world scenes are untouched this time.

**Blocked / next.** Nothing blocked. Still outstanding from yesterday: menu
hover has no motion, and there is no keyboard or gamepad navigation anywhere
in the squad manager.

---

## 2026-10-22 (later still) — the squad manager had no motion at all, and the first version of the fix was dead on arrival

**Landed.** The menus, which the human reported as flat. They were: not one
tween existed in any of the four squad-manager files, while the in-game HUD
tweens in three. `open()` was `visible = true`.

Four things, all in `ui_kit.gd` + `squad_manager_ui.gd`:

- **An arrival.** The ground comes up in 0.09 s and the contents follow,
  0.19 s all in. Not a wipe — `cyberspace_wipe.gd` is a door into somewhere
  else and this is a panel over the world. **Closing stays instant**: the
  pause hold, cursor, mouse mode and `release_pending` all let go on the same
  frame, so fading out would show a ghost menu over a running game.
- **A staggered entrance**, 0.022 s a card, capped at 0.30 s a page.
  `Kit.stagger` finds the OUTERMOST PanelContainers, so the chrome stays put
  and the contents arrive, and it needs nothing from the pages.
  **Entrances only** — opening, or a tab you actually moved to. Every purchase
  rebuilds the whole page and replaying the entrance on each would make buying
  four things look like the screen was struggling.
- **The purse counts.** RESOURCES and COMPUTE roll over 0.35 s instead of
  snapping. It is the only thing on the screen that moves by itself.
- **A refusal is no longer silence.** `sfx_denied` was assigned in NO SCENE in
  the project against 23 `play(&"denied")` calls, so every one was mute;
  `ClickA.ogg` at 0.72 pitch is wired in `hud.tscn` now, plus a 5 px shake.

**The first version did not work at all, and nothing visual would have caught
it.** Every tween was dead: the screen holds a PauseHold, and bound tweens do
not advance under it — even with `PROCESS_MODE_ALWAYS` on the UI, inherited by
the cards, and `can_process()` returning true on every one of them. They all
sat at alpha 0. In the game that is not a subtle bug, it is **a screen that
never appears.** `TWEEN_PAUSE_PROCESS` on all five tweens is the fix, and the
comment in `ui_kit.gd` says so at length because the next person will
reasonably assume ALWAYS is enough.

**`Kit.motion`,** a static switch every helper honours by applying its end
state instantly. It exists because a rolling number is INTERMEDIATE for a
third of a second: `test_squad_manager` reads `_resources.text` and
`_compute.text` directly and was passing only because neither value happened
to change before those lines. Off in all three shot tools too, so a grab
cannot catch a card mid-fade. It is also the shape a reduced-motion option
would take; nothing reads it from Settings today.

**Gates.** `check.sh --changed`: **PASS**. `smoke.sh`: **PASS**, 15s, 3
warnings. `test_squad_manager` **91/91** (up from 89 — the two new ones are
the motion checks), `test_line_opening` 19/19, `test_memory_screen` 38/38,
`test_line_specs` 44/44. **Not `test.sh`** — it still cannot finish.

Rendered `live_squad_walker.png` with motion off: every card at full alpha,
nothing half-drawn. That is the regression check, not evidence of the motion —
which is what the two new suite checks are for, because a no-op looks exactly
like a finished animation one frame later.

**Needs the human.**
- **Go and feel it.** `play.cmd`. Whether 0.19 s is right, whether the stagger
  reads as the screen registering or as lag, and whether the shake is too much
  are all yours. Every number is a constant at the top of the MOTION block.
- **`Character/hud/hud.tscn` WAS EDITED ON DISK WHILE YOUR EDITOR IS OPEN** —
  one new AudioStreamPlayer and the `sfx_denied` binding. Reload it there
  before saving anything from the editor.
- **Shared files touched:** `Character/hud/hud.tscn`,
  `Character/hud/squad/ui_kit.gd`, `Character/hud/squad_manager_ui.gd`.

**Blocked / next.** Not done, and deliberately: **hover is still a stylebox
swap** with no motion, and **there is no keyboard or gamepad navigation at
all** — `ui_kit.gd` sets `focus_mode = FOCUS_NONE` on every button it makes,
so the whole screen is mouse-only in a game whose other hand is on WASD.
Those are the next slice.

**I was wrong about.** I wrote in the MOTION comment that
`PROCESS_MODE_ALWAYS` was enough for these tweens to run under the pause hold,
and shipped the first version on that assumption. It is not, and the feature
was entirely dead until the suite said so. I also first sampled the animation
at a fixed 50 ms, which landed inside the expensive frame that builds the page
and reported a working stagger as broken; it waits for the first card to move
now.

---

## 2026-10-22 (later) — the sim arena loses an exercise, the core moves to the floor, and a fourth objective nobody authored

**Landed.** Three things the human asked for, in one pass over the Proving
Ground.

*First Contact is cut.* `mission_arena_1_contact.tres` is deleted and with it
every reference: `Env/world.tscn`'s mission list, three tables in
`ops_table.gd`, four tools and nine suites, and two briefs. **It was the only
unlocker of `emp` and `hatchling`**, so both moved onto `arena_3_firing_line`
rather than falling out of the campaign silently. Take And Hold is now the
opening operation and the whole of training.

*The core moved to the middle of the floor.* `place` z 65 → **z 8**: 93 m from
the spawn down to 36, out of the bay behind the enemy position and onto the
arena floor where the first fight is. **Not z 0** — there is a cross-wall over
the whole centreline whose deck is 4.59 m up, and placing on the nominal
centre buries the pad in it. `probe_arena_cores.gd` said so by name, which is
the only reason I know; the .tscn number looked perfectly reasonable. z 8 is
the first flat open floor past it, and the wall is now the cover you cross to
reach the core. The enemy post moved with it (`BayCorePost` → `FloorCorePost`,
-6/0/12) and the counter-attack was re-aimed: ANSWER spawned at the bunker,
which from the new core is an 80 m run, so it comes out of the blockhouse
instead. Briefing rewritten to match.

*The busted objective was a fourth one nobody authored.*
`compute_core_point.tscn`'s ROOT is an `InteractObjective` with no id — a real
site authors one on each instance, and `TrainingCore` instancing it for the
art could not. It survived the prune (`MissionObjective._ready` exempts a
blank id, which is exactly the hole), joined the tracker, and rendered as a
permanent **CAPTURE THE OBJECTIVE** that nothing could ever tick, because
`HoldableCore._take_terminal()` had just disconnected it from the one terminal
that would have done it. The HUD was also counting it: it read **0/3 and
listed four**; it now reads 0/2 and lists three.

Fixed in three places, because it is a class and not an instance:
`TrainingCore` stands down any objective inside art it adopts (it cannot free
it — the script is on the root the art hangs off); `MissionObjective` now
WARNS by name when an id-less objective survives the prune; and the same
adoption now points the `HoldableCore` at the `Dock` marker the prefab has
shipped all along, which it was missing because the search looks at itself and
its parent and ours was neither.

*New tool:* `tools/shot_arena_ops.gd` — deploys a real operation onto the
arena, prints every objective with its interact point, and photographs the
plan and each objective at eye height. A render of `proving_level.tscn` is a
picture of the room; everything that matters here is raised at runtime.

**Gates.** `check.sh --changed`: **PASS**. `smoke.sh`: **PASS**, booted clean,
15s, **3 warning lines, down from 7**. Suites, by name and count:

- `test_arena_assault` 21/21 · `test_sim_arena` 53/53 · `test_training_core` 10/10
- `test_opening` 20/20 · `test_mission_objectives` 107/107 · `test_hillfort_live` 34/34
- `test_turn_loop` 15/15 · `test_ledger` 170/170 · `test_campaign_spine` 26/26
- `test_ops_board` 24/24 · `test_endings` 29/29 · `test_profiles` 33/33
- `test_scrap` 16/16 · `test_induction` 41/41 · `test_requisition` 13/13
- `test_minimap_objectives` 1/1 · `probe_arena_cores` 0 failures

**I did not run `test.sh`** — it still cannot finish.

**Three suites were green while testing nothing, and that is the more useful
finding.** `test_scrap` bought a module with `buy_item()`, which refuses a shut
line, so the purchase silently did not happen and the half-price-for-kit path
the suite exists for never ran — every check around it passed. Its ledger
assertion also read `ItemDefinition.cost`, which has not been the price since
the bands landed; it measures the purse now. `test_opening` asserted "against
four" against a six-robot force and had been red for days. `test_sim_arena`
asked whether training was over AFTER clearing the only exercise.

Rendered: `docs/marketing/wip/arena_plan.png`, `arena_from_spawn.png` and one
per objective. I opened them. The core is visible from the spawn through the
blockhouse arch at 36 m, which it was not at 93.

**Needs the human.**
- **`Env/world.tscn` WAS EDITED ON DISK WHILE YOUR EDITOR IS OPEN.** Reload it
  in the editor before you save anything from there, or the in-memory copy —
  which still has First Contact in its mission list — writes back over this.
  This is the failure in `never-swap-files-while-the-editor-is-open`.
- **Game feel is unjudged.** I ran it, I did not play it. Whether the core at
  36 m is the right distance, and whether a counter-attack out of the
  blockhouse lands better than one out of the bay, are yours.
- **The BUNKER's capture still has no dock** and warns every run: the entrance
  kit ships no `Dock` marker, and where a drone should land on a doorway is an
  art call I did not want to guess. One line once decided.
- **Nothing changes colour when you take it.** `CoreSignal: Signal has no
  core_pulse under it` fires twice — core and bunker. Pre-existing, in the
  prefab's own wiring, and touching it reaches the real sites.
- **`proving_clear` and `proving_extract` are now dead in the shipped game.**
  Only `arena_5_proving` asks for them and it is on disk but not in
  `Campaign.missions`. `test_arena_assault` loads it off the file and adopts
  it into the campaign so the two-live-gates rule is still tested, which is
  the only thing still exercising that half of the level.
- `Campaign/missions/appendix/mission_arena_2_mixed.tres` still
  `requires arena_1_contact`. Parked content, left alone, dangling.
- **Shared files touched:** `Env/world.tscn`, `Env/world_objects/ops_table.gd`,
  `Campaign/mission_objective.gd`, `maps/proving_level.tscn`.
- `Env/wor7E58.tmp`, `Env/worE2BF.tmp` and `Env/world.tscn~RF95a1614e.TMP` are
  sitting in `Env/`, dated 6, 9 and 13 October. Not mine and not touched.

**Blocked / next.** Nothing blocked.

**I was wrong about.** I reached for an AABB measurement to fix the dock
before checking whether the art already carried a marker. It did — `Core/Dock`
on every compute core — so the measuring code came straight back out. I also
first deployed `arena_5_proving` in `test_arena_assault` without adopting it
into `Campaign.missions`, which left `current_mission` null, pruned nothing,
and produced the two live extraction gates the suite exists to catch.

---

## 2026-10-22 — MEMORY replaces SOFTWARE and the Armorer; Mark system steps 1–7b

**Landed.** The Mark system (`docs/briefs/archive/MARK_SYSTEM_SPEC.md`, steps 1–7a,
seven commits) and then the screen that finished it.

*MEMORY* (`Character/hud/squad/memory_page.gd`, new; `software_page.gd`
deleted). Three sub-tabs over one ledger — WEAPONS, EQUIPMENT, UPGRADES — all
on the tree's existing rule: a thing HOLDS compute while it is loaded and
returns all of it when unloaded. The player's own carry list lives in
`Campaign/software_tree.gd` as `CARRY`; the ledger line is numbers only, with
no per-card explanation (the first draft printed "2 compute while racked, all
of it back on removal" under every card, nine times on one page). Names and
descriptions are read from `ItemDefinition`, never written twice.

Five weapons (Ancient Rifle 0 ISSUED, Mark One 1, Repair Lance 1, Squad
Automatic 2, Cluster Launcher 2) and eight equipment (Frag 0 ISSUED, Smoke 1,
EMP / Heavy Mine / Cluster Mine 2, Recoilless / Drone Carrier / Hatchling 3).
22 compute for all of it against a `starting_compute` of 2.

*Cut, with the files as the evidence.* Scout Carbine and Marksman Rifle are
`weapon_damage = 0`, `ammo_type = ""`, `in_shop = false` and both point
`player_scene` at `m4_hud_weapon.tscn` — stubs wearing the Ancient Rifle's gun.
Scanner too: one charge, nothing to read it on.

*Step 7b, the last shop.* `armorer_page.gd` deleted, the tab gone,
`SquadManagerUI.shop_items()` gone with it. **Three tabs: SQUAD, FACTORY,
MEMORY.** `buy_item`/`sell_item` survive on CampaignState — `recover_kit` and
the seed still move stock through them; only the shopfront went.

*Two things the removal broke that I had not expected.* The induction's two
rifle steps taught a shop that no longer exists AND relied on the player
mustering unarmed, which `_carry_issued()` has now made false. Both steps are
re-aimed at MEMORY (`induct_load_weapon` / `induct_carry_weapon`,
`TAUGHT_WEAPON` is `bolt` not `m4`, new appended `Trigger.LOAD_PROGRAM`). And
`test_scrap` had been quietly passing while testing nothing: `buy_item` refuses
a shut line, so its module purchase silently did not happen and the robot went
to the breaker wearing only its issued rifle. Fixed, and its ledger assertion
now measures the outlay from the purse instead of reading `ItemDefinition.cost`,
which has not been the price since the bands landed.

**Gates.** `check.sh --changed`: **PASS**. `smoke.sh`: **PASS**, booted clean,
15s, 7 warning lines. Suites, by name and count:

- `test_memory_screen` (NEW) 38/38 · `test_squad_manager` 89/89
- `test_line_opening` 19/19 · `test_line_specs` 44/44 · `test_ledger` 170/170
- `test_induction` 41/41 · `test_scrap` 16/16 · `test_campaign_spine` 26/26
- `test_pricing` 19/19 · `test_requisition` 13/13 · `test_profiles` 33/33
- `test_profile_menu` 32/32 · `test_equipment` 60/60 · `test_teams` 83/83
- `test_settings` 74/74

Two reds that are **not** mine, checked rather than assumed:
`test_tutorial` is marked PARKED at the top of its own file (the depot has no
lesson signs left). `test_opening` fails "...against four — 6 hostiles" on
`mission_arena_3_firing_line.tres`, last touched in `f21d08ed` on 2026-10-13.
**I did not run `test.sh`** — it still cannot finish.

Rendered: `tools/shot_squad_manager.gd` grew three MEMORY shots and lost its
four Armorer ones. I opened all three —
`docs/marketing/wip/live_memory_{weapons,equipment,upgrades}.png`. The first
render caught the CARRY button stretched to the card's full width, which reads
as a bar the card is made of rather than a thing to press; fixed and re-shot.

**Needs the human.**
- **Game feel is entirely unjudged.** I ran it, I did not play it. Whether 2
  starting compute against a 1-compute Mark One is a real decision or just
  thin is yours.
- **The bands are a guess.** Which gun is worth 1 and which is worth 3 has
  never been played.
- `docs/marketing/wip/live_armorer_*.png` are now pictures of a screen that
  does not exist. I restored them to HEAD rather than deleting tracked files;
  they want deleting.
- **Shared files touched:** `Character/hud/squad_manager_ui.gd` (tabs),
  `docs/briefs/archive/MARK_SYSTEM_SPEC.md` (one line, §5.1), and `tools/shot_ui.gd`,
  whose tooling/armorer block had been dead since 7a and now shoots MEMORY.
- **NEW FILE AT THE PROJECT ROOT: `play.cmd`**, at the human's request — a
  double-click that runs the game from source with no editor and no export
  (`Godot.exe --path <here>`, plain binary not `_console.exe`). Verified both
  ways: `--headless --quit` boots the real game and exits 0, and a bogus
  `GODOT` hits the guard and exits 1. I did NOT open a window with it.
- **A boot error that is not mine and that nobody has chased.** Piping a full
  game boot prints `Cannot assign contents of "Array[Object]" to "Array[int]"`
  TWICE, during scene load, before any campaign code runs. No file I touched
  declares an `Array[int]` and I edited no `.tscn`, so it predates this
  session — it has been hiding because `smoke.sh` counts warnings, not errors,
  and the renderer's "Parameter m is null" noise is what everyone greps away.
  It smells like a typed `@export` whose type changed under a scene that still
  holds the old array.
- `tools/wip_screens.gd` still draws a mock tab bar reading "SQUAD FACTORY
  ARMORER SOFTWARE". It is a design mock-up, not the live UI, and I left it.

**Blocked / next.** Nothing blocked. Next: the seven branches from
`docs/concepts/SOFTWARE_CONCEPTS.md` — UPGRADES currently shows the four
original branches with `UNWRITTEN` placeholders, which is the one tab of the
three with no content behind it.

**I was wrong about.** I wrote the spec's equipment table with Frag at 1 and
the two tabs totalling 23; the human made Frag issued, and the suite caught the
arithmetic at 22. Spec corrected. I also published a prototype naming the
Recoilless Rifle `rocket` — that is its FILE name; its id is `recoilless`, and
a lookup written from the filename finds nothing and fails silently.

---

## 2026-10-18 — impacts and tracers: a rendered concept, and the filter renders thin bright things BLACK

**Landed.** Two NEW files, nothing existing touched: `tools/mock_impacts.gd`
and `docs/concepts/IMPACTS.md` with 25 PNGs beside it in `docs/concepts/`.
The tool has four modes — `survey` (what a round's raycast hands back),
`rates` (rounds and live tracers at Qamareen), `bench` (cost), and the default
headful render. It builds a pooled impact/tracer field at runtime in the
proving ground and the Salient; the game is unmodified.

**Four findings worth the board's attention.**

1. **The signal filter's EDGE PASS inverts thin bright objects to near-black.**
   `edge_color` is (0.02, 0.06, 0.06) at `edge_strength` 0.75, and a 1-2 px hot
   streak on sky is a maximal luma step on every pixel it owns, so the pass
   replaces three quarters of it with black. Proved by an A/B that keeps the
   whole filter and zeroes ONLY `edge_strength` (`NOEDGE=1`, the `_noedge`
   images). Measured threshold: **between 4 and 7 screen pixels.** This is a
   project-wide rendering rule, not an impacts question — and
   `tracer.tscn`'s own 8.5 cm mesh is ~3.4 px at 20 m, so **the shipped
   tracers are probably going dark at range.** I did not render the game's own
   tracer to confirm; somebody should.
2. **Per-texture material awareness is UNAVAILABLE, not expensive.** The
   project runs Jolt, and Jolt never populates `face_index`: -1 on all 921
   surveyed hits. The three-bucket version works and is cheap, but the walk is
   `GeneratedTerrain < _Built < Collision` — THREE levels, not the one the
   source reads like — and it is memoised, which is what actually makes it
   free (1 distinct collider in the proving ground, 2 in the Salient).
3. **Beaded tracers fall out of cadence for free.** At 80 m the three rapid
   classes give 5.6-7.7 beads in flight. No authored dash trail needed. The
   autocannon is NOT the beaded one — 3 rounds at 0.50 s is a thumper.
4. **Faction-coloured tracers do not survive.** Amber, green and tyrian all
   render as the same pale yellow-white, mostly because an additive hot streak
   clips to white before the filter even gets to it. Tested at full brightness
   only; a dimmed variant is untested.

**What happens on a hit today, for the record.** Nothing on brush or terrain.
On a robot, `particle_effects_hit` fires a SparkBurst **at the body origin**,
not at the hole. No impact sound anywhere. `Tracer.hit_effect_scene` exists
and `tracer.tscn` leaves it null. `_one_round` computes the impact point and
spends it only on suppression.

**Budget.** One round (tracer + impact) 0.0037 ms. Pool tick 0.1141 ms empty,
0.4569 ms fully saturated = 4.0 awake robots = 2.7% of a 60 Hz frame. Worst
realistic Qamareen load is ~6.7 rounds/frame = 0.025 ms of registration. All
CPU, timed synchronously — no `await physics_frame` in the loop.

**Mistakes I made and corrected, all recorded in the files.** The bucket test
walked one level and called the Salient's whole ground "brush". `hold()` froze
every channel at a fraction of the LONGEST lifetime, so FREEZE=0.22 stepped
3.08 s and every spark was dead — the freeze is now SECONDS, because one frame
is one instant and channels with different lifetimes cannot share a phase. The
first cameras aimed through a gateway and staged 26 impacts on a wall 60 m
behind it; `_stage` now prints the range it hit and warns. `INSTANCE_CUSTOM` is
vertex-only and the DUMMY renderer reports the compile failure then carries on,
so a headless bench ran with five broken shaders and looked fine. `_ready()`
called by hand AND by the tree built every channel twice. The bead measure
compared spacing to streak length, which is the wrong measure. `PROCESS_MODE_
DISABLED` deregisters the body, so every round aimed at the test robot went
through it. And my soft-edge hypothesis for beating the edge pass **failed** —
a 2 px streak has nothing to spread a ramp over.

**Gates.** `bash tools/check.sh --changed`: **PASS** (6 scripts). Did not run
`test.sh` (instructed not to, and it cannot finish). Did not run `smoke.sh` or
any bucket — nothing in `Character/`, `Campaign/` or `Managers/` was modified,
so no suite covers a change that does not exist. The tool itself was run ~20
times headful and headless.

**Needs the human.** **Game feel is entirely unjudged** — I ran it, I did not
play it, and every picture is frozen. Tracer legibility is a moving property a
still cannot settle. Open `impact_06_one_round_close.png` first; it is the one
that shows the work. Shots 02-05 are weak pictures at 12 m — the channels are
correct, the camera is too far to judge them. No audio exists, and the thing I
most recommend building (the near-miss crack) is audio and entirely
unprototyped. GPU fill cost of 1632 additive instances is unmeasured.

**Blocked / next.** Nothing blocking. Order I would build in: (1) the
near-miss crack, because `suppress_along` already computes distance-to-segment
for every round and already finds the player — it is a presentation layer on
correct existing arithmetic; (2) the apparent-width floor project-wide, and
look at the shipped tracers through the filter before tuning anything new;
(3) the pooled pit + spark fan on three buckets; (4) tracers at 1-in-5 with
emergent beading. Not yet: faction colour (tested, fails) and the penetration
tell (a picture of a mechanic that does not exist — `_one_round` stops at the
first collider).

**Files outside my lane: none.** `docs/concepts/` already holds other lanes'
concept docs (DISMEMBERMENT.md, SCREEN_FEEDBACK.md); I added only
`IMPACTS.md` and `impact_*.png`. No shared file touched. Nothing committed,
no branch, no stash.

---

## 2026-10-15 (later) — the redoubt IS Hillfort now, and a regression I shipped in the entry above

**Landed.** `hillfort_1_relay` is out of the campaign; `hfw_1_fort` is the
opening site at the board's `(0, 0)`. Location and missions renamed to
**Hillfort** / **Hillfort — Hold** for the player; internal ids stay
`hillfort_wip` / `hfw_*` because renaming those buys nothing visible and costs
the save format, the board tables, the callsign pool and nine suites.

**Nothing deleted.** `mission_hillfort_1_relay.tres`,
`mission_hillfort_2_defend.tres`, `loc_hillfort.tres` and
`maps/hillfort_level.tscn` are all still on disk and still load — just
unregistered from `Env/world.tscn`, `location_catalogue.tres` and the board
tables. Swapping back is re-adding four references. Authored content does not
get deleted without being asked.

Touched: `Env/world.tscn` (shared), `location_catalogue.tres`,
`loc_valley_basin.tres`, `mission_basin_1_anchor.tres`, `ops_table.gd`,
`callsigns.gd`, and eleven suites repointed off `hillfort_1_relay` /
`&"hillfort"`.

**The load-bearing edit was `mission_basin_1_anchor.requires`.**
`available_missions()` gates on `completed_missions.has(req)`, so a mission not
in `Campaign.missions` can never complete — leaving Valley Basin requiring
`hillfort_1_relay` would have locked the whole campaign after the tutorial,
silently, with the board just never offering a second site. Caught by reading
the gate rather than by a test.

**I shipped a regression in the entry above and did not notice.** Adding
`loc_hillfort_wip` as a TENTH location broke three checks in
`test_campaign_spine.gd` — "the nine places that exist" read 10, the income
totals read 238/13 against §2's 230/12, and Valley Basin's degree read 6. I
reported that session as green having run `check.sh`, the new suite and
`smoke.sh`, but not the spine. **A new Location is a change to the board's
arithmetic and `test_campaign_spine.gd` is the thing that knows it** — run it
whenever `location_catalogue.tres` moves. The swap removes the tenth location
and all three are green again, but they were red for the length of a report.

**Gates.** `check.sh --changed`: PASS. `test_campaign_spine` 0 FAIL (was 3),
`test_opening` 1 FAIL, `test_enemy_turn` 0, `test_turn_loop` 0,
`test_callsigns` 0, `test_ops_board` 0, `test_hillfort_wip` 0. `smoke.sh`:
PASS.

The one `test_opening` failure is **not mine and predates today** —
`...against four / 6 hostiles`, which is `arena_3_firing_line` fielding six
against a spec of four. It is on the known-open list from earlier in this
session and `git diff` shows I never touched that mission. The two checks that
matter for the swap both pass: "CLEARING THE SECOND OPENS HILLFORT" now
resolves to `hfw_1_fort`, and nothing deeper opens with it.

**Needs the human.** Still nobody has played it — that line from the entry
above stands and is now more urgent, because this is the only opening site
there is.

- **Start a fresh campaign.** A `campaign.json` from before the swap holds
  `hillfort` as a site id and `hillfort_1_relay` in `completed_missions`. It
  will not crash — the site resolves to nothing and pays nothing, the mission
  is inert — but the run will have a hole in it.
- The display name is now plain "Hillfort". If you would rather keep
  "Hillfort Redoubt" while both exist on disk, it is one line in
  `loc_hillfort_wip.tres` and two in the missions.
- `Env/world.tscn` is shared and I removed two mission references from it.


**Verified live, after the swap.** `tools/test_hillfort_live.gd` — new — boots
Master, resets the campaign and walks the whole opening: fresh save offers only
the first exercise, the training opens the Hillfort, **clearing the Hillfort
opens Valley Basin**, the board draws one pin named Hillfort, the slice builds
six reachable cores and a bunker, **taking a core calls the counter-attack**
(52 hostiles to 59), taking the bunker with five cores still theirs ends the
operation and opens the way out, extraction pays 270 and the site becomes held,
and the defence appears only once the site is raided. **33/33.**

Those are the three things the structural suite cannot reach — a gate that
locks the campaign, a wave that never comes, and a defence that never offers
itself all look like nothing at all from the file layer.

One number worth recording: the live run counts 52 hostiles on the map where
the roster authors 48. Deployed in isolation the spawner produces exactly 48
Soldiers and nothing else, so the roster is right and the extra four are the
campaign layer — heat starts committing reinforcements as soon as an operation
begins, and the live run counted two seconds in. Not chased further; it is
pre-existing SiteHeat behaviour, not something this work introduced.

**Blocked / next.** Nothing blocked. `arena_3_firing_line`'s six-vs-four is
sitting open and is a two-minute fix if you want the spec honoured.

## 2026-10-15 — Hillfort Redoubt is a playable site, and the bunker stays where TERRAIN put it

**Landed.** `hillfort_wip` went from geometry-with-markers to a registered,
playable location, per `docs/briefs/archive/HILLFORT_WIP_HANDOVER.md` §3. New:
`Campaign/missions/mission_hfw_1_fort.tres`, `mission_hfw_2_defend.tres`,
`Campaign/locations/loc_hillfort_wip.tres` (**Hillfort Redoubt**),
`Env/world_objects/hillfort_wip_slice.gd`, `tools/test_hillfort_wip.gd`,
`tools/shot_bunker_arrival.gd`. Registered in `Env/world.tscn` (shared — said
so here), `Campaign/location_catalogue.tres`, and the three board tables in
`ops_table.gd`. Reciprocal edge added to `loc_valley_basin.tres`.

It sits BESIDE Hillfort rather than replacing it — same `requires`
(`arena_3_firing_line`), both connecting to Valley Basin, so the campaign forks
and the two can be played against each other. That is the only arrangement in
which building an alternative first mission means anything.

Difficulty matched to Hillfort **to the unit** with `measure_resistance.gd`:
48 on map, 31 reserve, 79 total, both missions; defences 14 and 14. Same
chassis vocabulary too — rifleman, shotgunner, chaser, hopper. **No marksman**,
on the human's instruction: a 281 m covered lane wants one badly and that is
why the first mission does not hand the player one.

In TERRAIN's level I added the slice node, two `PatrolPath` nodes, the exit
gate, `optional = true` on all six captures, and the rebalanced rewards.
`site_slice.gd` gained a `bunker_yaw` export — additive, defaults 0, nothing
else changes.

**I was wrong, and reversed it.** §4 asked GAMEPLAY to settle the bunker's
facing and TERRAIN preferred turning it 90°. I set it to 90 on that
recommendation, then built `shot_bunker_arrival.gd` to photograph it and found
the recommendation makes it worse: 90° points the doors square into the Data
Hall 14 m east (blocked 20.8 m), 180° into the rampart (12 m), while the
as-authored 0° is clear for 60 m with the dish beside the frame rather than
filling it. **Left at 0 — TERRAIN's option 1, not their recommendation.** The
export stays because it is how the next one gets settled by looking.

**Also wrong once and caught by a tool:** the four reserve waves were first
authored as kill-triggered ADVANCE specs, which put all 79 bodies on the map at
once — 65% harder than Hillfort while claiming to match it.
`measure_resistance.gd` showed 79/0 against Hillfort's 48/31. They are now
RESERVE waves keyed to capture ids, since `Campaign._on_objective_changed`
passes the completed objective's id straight to `wake()` — so taking the
Gatehouse releases the east lane, which is §1's design exactly.

**Gates.** `check.sh --changed`: PASS. `tools/test_hillfort_wip.gd`: 30/30.
`smoke.sh`: PASS, booted clean. `spawn_geometry_audit.gd`: 79 bodies / 0 badly
placed on the attack, 14 / 0 on the defence. `probe_nav_vs_art.gd`: no walkable
navmesh inside any slice-built solid — **no rebake needed**.
`_advance_reach.gd`: nothing on this map frozen. I did NOT run the full
`test.sh` — it takes the better part of an hour and nothing here touches the
ledger or the armoury.

**Needs the human.** **Nobody has played it.** Every number is measured and
none is felt. Specifically:

- The lane split is 108 m centre against 281 m west. That is a 2.6x walking
  difference no probe can judge. If west is boring rather than tense, the fix
  is content on it, not a reward.
- The reward spread between lanes is only 25 resources, deliberately — a lane
  should be a tactical choice, not an economic one. If the fast lane feels
  free, the spread is too small.
- The bunker arrival at yaw 0. I am confident on the measurement and the frame
  looks right, but TERRAIN disagreed and they built the ground.
- `Env/world.tscn` is a shared file and I added two missions to it, inserted
  before `basin_2_defend` so `is_final_mission()` still resolves.

**Blocked / next.** Nothing blocked. Next would be a playtest of both openings
back to back, which is the whole point of the map and the one thing this lane
cannot do.

## 2026-10-05 (later) — the cores get the size they deserve, and every played map gets cover

**Landed.** Three jobs off the back of the entry above.

**1. Capture cores are no longer all the same size.** Every capture objective in
the project — thirty-four of them across eight maps — was
`compute_core_point_small`. The medium and large prefabs existed and were used
nowhere, so the console the whole campaign is about looked exactly like a bonus
relay in a car park.

Sizing one is not a taste question, because a core goes in AFTER the navmesh is
baked: the baker knows nothing about it, the squad paths straight at it, and a
core wider than the lane it stands in is a doorway full of robots. A core taller
than the room comes up through the ceiling. So `tools/probe_mission_anchors.gd`
now MEASURES it — one ray up for the ceiling, eight out at chest height for
clearance, shortest wins — and prints the biggest core that fits at every
objective on a map. Measured footprints, which are not the heights
`docs/BLOCKS.md` quotes (those include the uncollided crown):

| | footprint | height |
|---|---|---|
| small | 1.88 sq | 4.19 m |
| medium | 3.38 sq | 6.97 m |
| large | 5.19 sq | 12.38 m |

What it decided:

- **Georgetown** — park small, stack medium, lock medium (nudged 3 m off the
  gates so the dry crossing stays open), **Water Street large**, mill small. The
  street core moved off the carriageway to z −108, between the road and the
  north pavement: 5.19 m on a two-lane road would have walled the final fight in.
- **Polaris** — **the breach uplink is large**, 12.4 m in the open in front of
  the mall doors with four hundred metres of car park in front of it. The
  biggest core in the project and the right place for it.
- **Causeway** — checkpoint medium, **fort yard large**, everything else small.
  **The crown uplink — the last objective in the campaign — gets the smallest
  core on the map, because the room says so.** Tower floors are 6 m apart on
  0.75 m plates, so a data hall has about 5.25 m clear and a medium core is
  6.97. The probe reads 4.7 m at the basement and 3.5 m of clearance at the top
  hall. I would have placed a large one there on instinct and it would have come
  up through the ceiling.
- **Hillfort** — **medium**, and that is a correction. The probe says large
  fits, but only just: it measures 5.3 m to the nearest obstacle and a large
  core is 5.19 m wide, so the threshold passes by twenty centimetres. A number
  that close is not a yes. Medium clears it by over a metre and is still three
  times the core that map had.
- **Coast Road** — bridge and craters medium, **town large**. Open map, 24 m of
  clearance everywhere, and the sizes now climb along the road the way the
  mission does.
- **Left alone, and why:** Qamareen is mid-rework by TERRAIN and its flagship
  (the Compute Hall, 15 s channel) measures 4.0 m of clearance, so it could not
  grow anyway — upgrading one of the others would have made the wrong objective
  the biggest. Three Rivers has no clear flagship and mixed clearance.
  Valley Basin's anchor measures 2.1 m. Nothing was added where something was
  already there; the sizes were swapped, never stacked, which is what
  `test_objective_terminals` exists to catch.

**The probe caught three placements I had already made by eye, and all three
were wrong.** This is the argument for the tool rather than for my judgement:

- **The Polaris uplink was under a canopy.** I put a 12.4 m core at the entry
  court at z 44; the ceiling there measures **3.6 m**. It would have come up
  through the mall entry's own roof. Moved to z 56 — open sky, 18.1 m of
  clearance, and still in front of the doors.
- **The Causeway's ammunition dump core was inside the dump**, under a 2.1 m
  roof with 0.3 m of clearance. Moved 9 m into the open beside it.
- **Georgetown's mill core measured 2.0 m of clearance** at the position it had
  been sitting at since it was authored — a small core with about a metre to
  spare, hard against the mill front. Moved 6 m onto the berm; 8.0 m now.

Two of those were my own placements from earlier today and the third was
inherited. None of them is visible in a top-down render, which is the only way
anyone had been looking at this.

**Every core is also YAWED to face its approach.** `docs/BLOCKS.md` says the
service alcove — the prefab's −X, and the one spot a body can stand while it
channels — should be turned toward the approach "the way the relay dish is
yawed", and not one map in the project had done it. All of them now are. The
Causeway's rotate with the floor: the basement opens EAST because the portal is
in the tower's +x face, the top hall opens NORTH because its stairwell comes up
on the −z side.

**2. Every level a mission plays now has cover.** Hillfort had **zero** cover
points — the only played map besides the three new ones — which is the same
complaint as the playtest note on it ("overall except for the top of the hill
there's nothing") read from the AI's side. `tools/mission_ops.sh` places the
spawner and `tools/probe_cover_mutaha.gd` bakes it:

| | before | after |
|---|---|---|
| Hillfort | 0 | **2,611** |
| Georgetown | 0 | 1,036 |
| Polaris | 0 | 1,008 |
| Causeway | 0 | 2,067 |
| Coast Road | 1,921 | 1,924 (re-baked round the resized cores) |

**3. A second pass on the three missions.** Four changes with a reason each:

- **The Causeway's opening fight comes to you.** CULVERT and SOFFIT, the two
  sections nearest the west ramp, were GARRISON — which meant 300 m of walking
  before contact on the one stretch of this map that has no cover. They ADVANCE
  now, so the crossing opens as a meeting engagement in the first hundred metres
  with the west bank still behind you. This is the direct answer to the thing I
  flagged as the mission's biggest risk.
- **The gun crews never stand down.** BOMBARD and BALLISTA are `always_active`.
  The briefing claimed they shelled the spans you crossed; at a marksman's 120 m
  activation distance that was not true, so the data was changed to make the
  claim nearly true and the claim was softened to what they actually do — watch
  the east ramp before you reach it, and sit behind you once you are past the
  wire. **Both halves, not just the wording.**
- **Both extractions are contested now.** Neither was. Georgetown's upper road
  had one squad on it and Polaris's service dock had three; a five-wave hold
  that ends in an unopposed walk out is an anticlimax. KESTREL (two heavies, a
  marksman and a shotgun) wakes on the Water Street relay and takes the upper
  road; COLDSNAP (five, heavy) wakes on the fifth wave and takes the dock.
- **Polaris was claiming elevation the map does not have.** The multiplex and
  the parking deck are the mission's two flanking strongpoints, and the text
  said "marksmen on the deck's upper floor" and "it has a ramp, which the
  multiplex does not". Probed: every point on the deck's upper level and the
  cinema roof comes back UNREACHABLE and snaps to y 0. Both are sealed. The
  descriptions now say what is true — hard cover at ground level with ninety to
  a hundred metres of open asphalt in front of it, and the fight is at their
  feet. Same discipline as the gun crews, opposite outcome: there the data was
  changed to fit the claim, here the claim had to come down to the data.
- Two Georgetown descriptions were corrected to match where their cores actually
  moved to. A briefing that describes the wrong spot is a lie in the data.

The ladder's enemy supply, which is the one number that says "harder": 247
(Qamareen) → **264 → 266 → 351**. Bodies 215 → 221 → 227 → 297.

**Gates.** `check.sh --changed`: PASS. `spawn_check`: PASS, all 27 missions.
`probe_mission_anchors`: PASS on all three, nothing unreachable, nothing off the
mesh after the cores moved. `test_mission_objectives`, `test_mission_tags`,
`test_objective_terminals`, `test_minimap_objectives`, `test_compute_cores`:
all PASS. Three briefing maps re-baked. `smoke.sh`: PASS, booted clean.
**Full `test.sh` against the finished state: `ALL SUITES PASS`** (2 not run,
both parked).

**Needs the human.** The decor list in the entry below still stands and is the
most valuable thing on it. Two new ones:

- **Look at the large cores in game.** 12.4 m is tall. The Polaris one in
  particular is meant to be the thing you steer by from the frontage, and
  whether it reads as a landmark or as a thing in the way is a judgement from
  eye level that I cannot make.
- **Hillfort's 2,611 cover points are untested in play.** That map had none at
  all, so this is the first time its AI has had anything to use. It may change
  how that mission plays more than anything else here.
- **`tools/hillfort_objectives.sh` has drifted and would undo part of this on a
  rebuild.** It still pastes back the OLD hand-built relay — a PersonalComputer
  FBX and a template_interactible — while the level has carried a
  `compute_core_point` instance for a while now. It is a no-op today because it
  exits early when it finds a `RelayObjective`, so nothing is broken; but
  regenerate the Hillfort and it will put the wrong thing back. I did not
  rewrite it: it is a patch script for a map I was only passing through, and
  changing it blind is how a repair script becomes the thing that needs
  repairing. Worth half an hour from whoever owns that map.
- **One decor ask, for TERRAIN: Polaris's parking deck wants a ramp.** The map's
  design has two strongpoints looking into the entry court from either flank,
  and neither is climbable — the deck has no reachable upper level and the
  multiplex has no roof access. A parking deck you cannot go up is a parking
  deck doing half its job, and it is the one place on that map that would give
  the fight a second storey. Not a blocker; the mission plays at ground level
  and says so now.

---

## 2026-10-05 — three operations, and a gameplay layer the terrain tools cannot eat

**Landed.** Georgetown, Polaris and Causeway have missions. All three are
harder than anything in the game, and on the numbers rather than by assertion —
`audit_economy` prices the ladder's enemy force at the player's own supply
rates and it now reads 247 (Qamareen) → 258 → 259 → 351, with body counts
215 → 217 → 222 → 297. The first pass had Georgetown and Polaris at 239 and
240, *under* Qamareen; the gap was closed with armour (two heavy squads, a
walker and a lobber apiece) rather than more bodies, so the perf profile did
not move. Unlike Qamareen, most of that force arrives in answer to something
the player did rather than standing on the map at load.

- **Georgetown — "Georgetown", an ascent.** You come ashore at the west end of
  the derelict waterfront park and fight UP four terraces: park, lower yards,
  canal, upper town. One relay per bench with the channel lengthening as you
  climb — 6 s at the bandstand, 14 s in the middle of Water Street — then out
  the east end of the upper road, which is the far corner of the map from the
  landing, so the operation crosses the whole thing diagonally. Four optional
  targets, all off the climb. 59 squads, 11 reserve waves including two walkers,
  a mortar track, a bomber and three that come in on a body count.
- **Polaris — "Polaris", a wave defence.** The only map in the project shaped
  for one, and the reason is the closed ring road: four arterial approaches and
  no corner a vehicle cannot reach. Fight 300 m up the restaurant row and
  across the car park, start the drain in the entry court, then hold it through
  five waves — south, east, west, north, then all four at once with a walker up
  the middle and a bomber over it. Out the back by the service dock.
  Built with nothing new: each wave is an `EliminateObjective` on its own
  callsigns, and a reserve's `reinforcement_tag` IS an objective id, so wave N
  completing is what spawns wave N+1. Each wave objective carries
  `starts_active = false` with the previous wave as prerequisite, so it
  activates on the frame its squads are built — otherwise the HUD shows all
  five from the first minute and `EliminateObjective` warns about having no
  targets. `required_kills` sits 2–5 below each wave's body count on purpose:
  the classic wave-defence stall is one chaser hiding behind the garden centre.
- **Causeway — "The Causeway", the finale.** Three fights of different shapes in
  a row. A kilometre of open deck; a fortress with one door; then twenty-four
  data halls. 2,042 m of path from the west bank to the top hall, and the whole
  thing is one connected navmesh — I walked it. Seven captures and five optional
  targets. **This is now the campaign's last operation, so clearing it is what
  sets `campaign_won`** — it used to be Qamareen.

**Where the gameplay lives, and why.** Not in the level files. Georgetown and
Polaris are written from a template by `tools/build_georgetown.gd` and
`tools/build_polaris.gd`, so anything hand-added to one dies on the next
`--force` rebuild — which is exactly how the Hillfort lost its relay and
shipped with a blank objective HUD. Each map's posts, routes, objectives, exit
and squad spawn are in `maps/gameplay/<name>_ops.tscn`, a file the terrain
tools do not know about, and `tools/mission_ops.sh` instances it into the level
in two lines. Re-run that after any rebuild and nothing is re-authored.

It also had to put `trench_broom_level.gd` on the Georgetown and Polaris roots:
they were plain `Node3D`, and `World.load_next_level` does
`instantiate() as TrenchBroomLevel`, which casts a plain root to null. **Neither
map could have been deployed into at all before this.**

**Every position was walked, not eyeballed.** New tool,
`tools/probe_mission_anchors.gd`: snaps every post, patrol point and objective
to the baked navmesh and paths to it from the spawn, and takes `POINTS=` so a
coordinate can be checked BEFORE it is written into a level. Four things it
settled that changed the design:

- Georgetown's town bench is tiled back to z −264 but the navmesh's
  `filter_baking_aabb` starts at −140, so the modern office block and the north
  third of the bench have no walkable ground on them. Nothing is posted there.
- The causeway's old carriageway piers at z +30 bake as isolated stubs — three
  separate samples came back UNREACHABLE. They are a silhouette, not a flank.
- The tower crown is not walkable: everything above y 138 snaps back to the top
  hall. The uplink and the pad are both on that floor, at opposite ends of it.
- The fort's east curtain has a 16 m gap at z 0 where the pit head comes
  through, same as the west curtain has for the gate, so the wall walk is two
  Ls and not a circuit. The patrol is authored as two routes.

**None of the three had a single cover point.** `audit_levels` prints "no cover"
for a level with no `CoverPointSpawner`, and all three read it — against 1,012
to 3,289 on every other played map. The AI's whole cover system had nothing to
use on them. `mission_ops.sh` places the spawner now (`sample_radius = 0`, the
whole level, because the default 80 m covers a circle you cross in fifteen
seconds and the smallest of these is 554 m across), and
`tools/probe_cover_mutaha.gd` baked them: **Georgetown 1,035, Polaris 1,007,
Causeway 2,067.**

The spawner goes in the LEVEL and not the ops scene, deliberately and against
the rule above: cover points are a function of GEOMETRY, so they *should* die
with a rebuild and be re-baked rather than survive it as lies. The bake is a
separate non-headless run — the spawner raycasts against real collision — and
the patch script seeds one `CoverPoint_0` because that tool splices between the
first and last existing point and bails on a scene with none.

**Six bugs found and fixed, all one family.** Code that reads a scene from its
PACKED form and walks `SceneState` without following `get_node_instance()` is
blind to anything inside an instanced sub-scene. Harmless while every level
declared its own objectives; three now do not. A `family-sweep` over every
`get_state()` / `SceneState` call site in the project found the rest.

- `tools/test_mission_objectives.gd` — reported 60 failures, correctly, and its
  own header had predicted this exact failure.
- `Campaign/minimap_data.gd:nest_ids()` — the briefing drew hives as capture
  points, which is the bug that filter exists to prevent. Caught by
  `test_minimap_objectives`.
- `tools/test_objective_terminals.gd` — **this one is a gate and it was passing
  falsely.** All three levels dropped out of its report entirely and it printed
  PASS. Its own header says "a test that passes by looking in the wrong place is
  worse than no test"; it was in that state again. It now checks the ops scenes
  and finds 5, 1 and 8 capture points in them.
- `tools/audit_levels.gd` — reported all three as `objectives 0  exits 0
  squad spawns 0`, NO WAY OFF THE MAP, PLAYED BUT HAS NO OBJECTIVES, and then
  every mission on them as naming objectives the level does not have. The two
  copies of that loop in the file are now one walker with two callers; they had
  already drifted once over whether an instanced objective counts.
- `tools/audit_economy.gd` — objective payout read exactly zero for all three.
- `tools/audit_capture_points.gd` — the three levels vanished from the report
  with no line printed, via a `rows.is_empty(): continue`.

Two more the sweep raised that I did **not** touch, because they are
pre-existing and in other people's files: `tools/audit_audio.gd` misses the
`AudioStreamPlayer3D` in any INHERITED weapon scene (`explosion_mortar.tscn`,
`smoke_canister.tscn`, `smoke_hud_weapon.tscn` all report no sound at all), and
`Character/hud/tutorial_library.gd:collect()` is the same shape but not yet
triggered — the first lesson sign authored as an instance of
`tutorial_label.tscn` disappears from the pause-menu library silently.

**New gate.** `tools/test_mission_tags.gd` — the half nothing checked. Every
`post_tag`, `spawn_tag` and `route_tag` on every `EnemySquadSpec` must resolve
to something the level offers. A dangling one never crashes: a garrison holds
the wrong ground, an advance walks at the player's spawn, a patrol stands
still. The proving ground lost a whole operation to this. Verified negatively —
breaking one tag deliberately makes the suite fail and name it.

**Gates.** `check.sh --changed`: PASS. `smoke.sh`: PASS, booted clean.
`spawn_check`: PASS, all 27 missions spawn exactly as authored.
`probe_mission_anchors`: PASS on all three levels, every post, route point and
objective reachable.

`test.sh` full, first run, found three things. Two were real and are fixed: the
minimap nest filter above, and `georgetown_1_ascent` unlocking `scanner`, which
is in the catalogue with `in_shop = false` so the armoury will not sell it —
`test_ledger` 163 checks and `test_minimap_objectives` both re-run green. The
third was `test_wake`'s garrisoned-hopper check, and it was **not mine**: that
file is uncommitted work by another lane (+34 lines, and it failed to parse
mid-session), and it passes on its own now.

**Final full re-run against the finished state: `ALL SUITES PASS`** (2 not run,
both parked: `test_terrain`, `test_tutorial`).

**Needs the human.**

1. **Play them, and tell me which of the three is wrong.** I cannot judge any of
   this. The specific worry is the Causeway deck: 620 m of 16 m carriageway with
   a 1 m parapet and nothing else, which is the shape `docs/MAP_DECK.md` ranked
   Tidal Causeway 28th for. I have built around it — the defence is concentrated
   in the two shelled spans where the lane pinches to 7 m, and there is not one
   marksman on the deck — but the decor ask below is the real fix.
2. **Decor, where you offered it.** Measured, not guessed:
   - *Georgetown, Water Street (z −96, x −208..208).* The hardest capture on the
     map is a 14 s channel in the middle of a 416 m straight street whose only
     furniture is five cobra lights and three stop signs. It wants parked and
     wrecked vehicles, planters, a small market or square, skips — anything
     waist-to-head at roughly 30 m intervals.
   - *Georgetown, lower yards (z 46..106, x −100..100).* Warehouses at z 85.5
     and mills at z 68 with open bench between them and the terrace wall. The
     stack relay sits in it. Wants crates, container rows, a siding, a crane.
   - *Georgetown, the towpaths.* A market at one end, the works compound at the
     other, 300 m of bare paving between. Wants barriers, spoil heaps, a
     lock-keeper's hut, moored barges.
   - *Causeway, the deck.* Ten to fifteen pieces of wreckage, concentrated at
     x −132, +12 and +108 — jack-knifed trucks, concrete barrier runs, a
     toppled gantry, a container. This is the one that decides whether the
     crossing is a fight or a march.
   - *Causeway, the fort yard.* 200 m square and completely empty, with a 14 s
     capture in the middle of it and a wall walk on all four sides. Wants
     revetments, stacked hesco, a hangar, fuel bladders.
   - *Polaris, the north lot (z −58..−98) and the lot's east and west ends.*
     Three sparse aisles each. Wave 4 arrives through the north lot and the
     extraction is behind it; waves 2 and 3 cross the ends.
3. **Georgetown's office block is unreachable content.** It stands at z −180,
   forty metres outside the baking box. Either widen `filter_baking_aabb` or
   move it south — TERRAIN's call.
4. **The three new missions have almost nothing left to unlock.** `repair_kit`,
   `heavy_mg` and `autocannon` are the only sellable catalogue items no mission
   already unlocks, and `scanner` has `in_shop = false` so nobody can ever buy
   it. The obvious rewards for these three are the four dark frames — Quadcopter
   Bomber, Marksman, Mortar Track, Lobber Rover — which is the board's own open
   item and needs your call on cost before they can go in the catalogue.
5. **Reload the level scenes if you have them open.** `maps/georgetown_level.tscn`,
   `maps/polaris_level.tscn` and `maps/causeway_level.tscn` all changed on disk,
   and `maps/gameplay/` is a new folder.
6. The three minimaps are freshly baked. Causeway's has a light bloom in the
   lower middle that the bake has always produced; cosmetic.
7. **The purse outgrows the shop.** `audit_economy` says these three leave
   2,745 / 4,035 / 5,785 resources idle — more than a full squad of baselines
   could ever cost. The rewards are probably too generous, or there is not
   enough to buy, and the second reading is the interesting one. Related to
   item 4.

**Blocked / next.** Nothing blocking. The honest next step is a playtest, then
tuning — `always_active` is false on every garrison in all three missions
(Qamareen sets it true on all 66 of its squads, which is a perf cost nobody has
measured), and the Causeway's body count peaks when the player enters the
basement and wakes floors 0–7 at once. Both of those are numbers a run will
settle and a reading cannot.

---

## 2026-09-29 (later) — playtest fixes, and a level that will not stay fixed

**Landed.** The six things off the playtest, plus two bugs the work turned up.

- *The Hillfort had no objectives and deployed four robots.* Two separate bugs.
  The level had been regenerated without the objective nodes the mission names,
  and `active_objectives` is a WHITELIST — `Campaign._prune_inactive_objectives`
  frees every objective the mission does not name, so a mission naming two ids
  the level does not have ends up with none at all. The four robots were
  `SquadSpawnPoint.max_slots`, whose script default was 4; every hand-built
  level writes 999 over it and the Hillfort did not, so a seven-seat squad
  deployed four. The default is now 0 (= everyone), because forgetting it must
  not silently cost you robots.
- *Garrisoned shotgunners stood still and died.* `Soldier.perform_action` blocked
  every MOVE in `defensive_mode` unless the frame was `aggressive`, which is set
  for melee rushers only. A 45m shotgun in cover taking 60m rifle fire aimed at
  something it could not touch. It now also lets anyone move who is shot at from
  beyond their own `_max_range()` — `find_advance_target` still stops them at
  their own standoff, and Squad's defend tick skips anyone in COMBAT, so they
  push, then walk back to the post when it is over.
- *The induction opens on the keys.* A REVIEW_KEYS trigger (appended to the enum)
  completes when the KEYS tab of the options screen is shown. `OptionsMenu` emits
  `tab_shown`, `Master` relays it as `keys_reviewed` — relayed because the options
  screen is built on demand and freed on close, so there is nothing for an
  objective built at level load to connect to. It is first because every other
  objective's text names a key.
- *Debrief.* REVIVES was drawn in the compute blue, which is the colour of a
  currency everywhere else on that screen; it is green now, with KILLS, because
  both are what the squad did. Mission time moved from an unlabelled `12:34`
  beside the mission name into the stat row as a TIME counter that counts up.
- *Minimaps.* `tools/minimap_bake.gd` never listed the Hillfort or
  `mutaha_wip_level`, so the briefing for the final mission was showing the
  retired Mutaha map. Both baked. Mutaha renamed to **Qamareen** in the mission's
  display name and briefing; the internal `obj_mutaha_*` tags and the level
  filename are unchanged and are TERRAIN's to rename if they want.
- *Four Qamareen reserve squads that had never arrived.* `squad_engaged_tag()`
  lowercases the callsign — "EAST-YARD" becomes `east-yard_engaged` — and the
  mission wrote the tags in upper case, so WEST-ALLEY, EAST-AMBUSH, RESPONSE-EAST
  and the BOMBER were waiting on tags nothing could ever fire. Found by the new
  suite below, which is the only reason anyone knows.
- *A DEBUG tab on the pause menu, editor-only.* PAUSED → DEBUG opens the options
  screen on a fifth tab: two switches (UNLOCK ALL MISSIONS, UNLOCK ALL HARDWARE)
  and two handouts (+5000 resources, +50 compute), split under headings that say
  which are reversible and which are not. The switches are read LIVE by
  `available_missions()` and `locked_by()` and write nothing, so unticking puts
  the run back to what it earned; `locked_by()` being the one gate all four shop
  surfaces ask is why one flag opens weapons, frames, modules and equipment
  together. **The first gate I wrote was wrong**: `_playtest_data_shown()` uses
  `OS.is_debug_build()`, which is TRUE in a debug-template export — the build you
  hand a playtester. It is `OS.has_feature("editor")` now, checked in four places
  including `Campaign._debug_switch()`, because settings.json ships beside the
  executable as plain text and hiding the tab alone would leave "unlock
  everything" two lines from anyone with a text editor.
- *Three live runtime errors the suite had been printing and nobody failing on.*
  All in game code, all found by reading SCRIPT ERROR lines in a passing run:
  `SquadHUD._on_order_issued` threw on a null squad (every order, in the
  induction); `CampaignState._team_index`/`team_name` indexed a saved team row
  for a key it might not carry; and `DebriefScreen._card` threw on an entry with
  no record, then handed `add_child()` a null. The third was MASKED by the
  second — fixing one let execution reach the next. `test_endings` went from two
  script errors to none.
- *`test_ledger` had 31 checks that had stopped running.* `cat.chassis_def(&"chaser")`
  returned null once chaser and leaper left the player catalogue, `buyable()`
  called `duplicate()` on it, and the error killed the COROUTINE without failing
  the run — so `test_recruiting` and `test_supply_caps_the_active_squad` had not
  executed at all while the suite reported PASS. That is the second time this
  project has been bitten by exactly that. The enemy frames load by path now,
  which is also the honest door: the point of them is that they are NOT in the
  catalogue. 131 checks → 162. It also revealed a silent early return in
  `SoldierRecord.recompute_stats()`, which left a 45-health frame reading
  SoldierRecord's own 100 and said nothing; it warns now.
- *New suite: `tools/test_mission_objectives.gd`.* Reads every mission and its
  level as packed data and checks they agree. It would have caught the Hillfort
  in a second. It knows all four ways a `reinforcement_tag` can be woken — an
  objective id, `nest_down`, `<callsign>_down`, `<callsign>_engaged` — because
  checking against objective ids alone reports most of the game as broken.

**Gates.** `check.sh --changed`: PASS (27 scripts, 45 scenes/resources).
`smoke.sh`: PASS, booted clean — run because master.gd is the main scene and this
session changed it. `test.sh`: **33 suites** (two new), and the only failures are
pre-existing and named below — pittsburgh bridge spacing (TERRAIN), the mutaha
terrain check (a retired map), two tutorial sign checks (markers deleted on
purpose), and the twelve dead reserve tags. The only SCRIPT ERROR left in the
whole run is FuncGodot's `entity_fgd` parse error during level loads, which
`test_livery` passes in spite of.
`tools/test_debug_switches.gd` runs TWICE, once as the editor and once under
`ROBOTO_DEBUG_TOOLS=0` as an export would see it; both branches pass. All 13
minimaps re-baked.

**Needs the human.**

1. **`maps/hillfort_level.tscn` is being regenerated by the TERRAIN lane every
   few minutes** — 12:17, 12:23, 12:25 today — and the regenerator does not
   preserve nodes it did not place. Every rebuild deletes the relay console, the
   extraction and the spawn move, and the mission goes back to a blank objective
   HUD. The repair is one idempotent command:

       bash tools/hillfort_objectives.sh

   Run it after TERRAIN finishes. The real fix is for the block pass to leave
   non-generated nodes alone, which is a coordination call, not mine.
2. **Twelve reserve squads across four missions never arrive.** Their
   `reinforcement_tag` names a capture objective the level does not author —
   `basin_anchor`, `coast_relay_bridge/craters/town`,
   `pitt_relay_dam/shore/strip/furnace`, `mutaha_relay_clock/compute`. Same root
   cause as the Hillfort: the missions were written against capture objectives
   the levels no longer have. Those missions still play, because they also name
   objectives that DO exist, so the prune leaves something alive — but a chunk
   of each designed force has never once spawned. Deciding whether to build the
   objectives or re-point the reserves is a design call.
3. `maps/minimaps/mutaha_wip_level.png` has no `.import` yet. Give the editor
   focus once and it will import; I did not run `--import` with the editor open.
4. Unverified in game: the Hillfort's new start position, the relay console's
   placement in the yard, and the new first induction objective.

**Blocked / next.** Nothing blocked. Next would be the twelve dead reserves,
once someone says which way to fix them.


## 2026-09-29 — the Hillfort, the distance bands, and the Mark One

**Landed.**

- **The Hillfort — the missing rung between Proving Ground and Valley Basin.**
  TERRAIN built `maps/hillfort_level.tscn` with eighteen tagged points and an
  exit; the mission on it is `Campaign/missions/mission_hillfort_1_relay.tres`.
  Fifteen squads, 30 bodies on the map and 8 held back, all infantry — shotguns,
  rifles, chasers and leapers, nothing armoured and nothing on wheels. It is an
  ascent: spawn at y=0 z=449, fight up through the cistern, the standing stones,
  the old gate and the terrace, and take the relay dish in the fort yard at
  y=132. Taking it wakes POSTERN and SPUR, who come back through the postern
  gate and down off the north spur to retake it; the exit is the roof above.
  **This is what the economy audit asked for.** Proving Ground to Basin was a
  6.6× step in opposition against +1 seat — the single cliff in the campaign.
  It is now 3.2× then 2.1×, and the purse going into Basin rose 860 → 1140.
  **It also gives the Mark One a home:** the Hillfort unlocks it, closing the
  last "buyable from minute one" hole. `basin_1_anchor` now requires
  `hillfort_1_relay` rather than `arena_5_proving`.
- **`maps/hillfort_level.tscn` gained two objective nodes** — the RelayDish
  capture point and the ReachObjective on the exit. That is TERRAIN's file and
  the board says missions are GAMEPLAY's, which is exactly the seam: objectives
  live in level scenes. Done on the human's instruction, backed up first, and
  recorded here.
- **Audio: three distance bands.** `Weapons` (0-40m, as authored), `WeaponsMid`
  (40-150m, low-passed to 4.2kHz) and `WeaponsFar` (150m+, 850Hz), all children
  of Effects. `Managers/weapon_audio.gd` picks the band per shot; past 150m it
  switches Godot's attenuation OFF and computes the level itself, falling 2dB
  per doubling instead of 6, continuous at the boundary.
  Called from `AIWeapon.play_shot_audio`, `HUDWeapon`, `Explosion._ready`,
  `PlayerRocket` and `RocketProjectile` — 18 sounds, every gun and every blast.
  **That also fixed the routing:** the Weapons bus already had an EQ, a
  compressor and a limiter built for exactly this, and only TWO of 51 sounds
  reached it, because `_route()` moves Master→Effects and a scene only lands on
  Weapons if it NAMES it.
- **Every `max_distance` cutoff is gone** — the mortar was silent past 250m, the
  rocket launch past 200m, its detonation past 220m and explosions past 750m.
  Those were the things the player most needs to hear coming.
- **The bolt-action is the Mark One**, "Slow, heavy, made by the thousand." The
  old name collided with the Valley Foundry mission, the Foundry robots in
  enemy.gd and the Foundry weapon tier on the board.

**Gates.** check.sh: **PASS** (535 resources). smoke.sh: **PASS**. test.sh:
running at hand-off; the previous full run was 31 suites with the four known
failures and nothing new.

**Measured, not assumed.** `tools/audit_audio.gd` prints every sound's level at
the listener from 10m to 800m, which bus it lands on and what is cut off. At
400m: Ancient Rifle -28.1 → -22.4, Ancient MG -40.4 → -34.7, explosions
-14.5 → -8.9, and the mortar from silent to -16.8.

**A warning worth not believing.** Booting the Hillfort prints
"navmesh_islands: left only 2158 m2 of 891611 reachable from the spawn". It
reads like an unplayable map. It is not: the sweep REFUSED to run, so it
stripped nothing, and a direct path test walks spawn → cistern → pillars → gate
→ terrace → fortgate → relay → roof, every leg reached, 203 points to the relay
and 218 to the exit. The warning is still worth TERRAIN's eye, because a sweep
that always refuses is a sweep that protects nothing.

**Needs the human.**
- **The Hillfort has never been played.** 30 bodies on an ascent is a guess
  calibrated to supply cost, not to how it feels climbing into rifle fire from
  above. The flanking watchers on the two hills are the part most likely to be
  wrong.
- **Audio wants ears, not numbers.** If distant fire is too loud, raise
  `FAR_SLOPE_DB` (2.0) or lower `FAR_CEILING_DB` (-8). If it is too thin, raise
  the far bus cutoff from 850Hz. Your own gun now goes through the Weapons
  compressor, which it mostly did not before.
- **`unit_size` still ranges 10 to 46 with no rationale** and is the main lever
  left on the near and mid bands. The player shotgun is the outlier: -20dB at
  unit 10, which is -40 at 100m where the AI shotgun is -16.

---

## 2026-09-28 (last) — the depot induction: the first visit to base is a mission

**Landed.** The onboarding blocker on the board is closed, by a different route
than the board proposed. Rather than porting fourteen signs out of
`homebase_level.tscn` into TERRAIN's depot, the first visit to base now SETS
FIVE OBJECTIVES in the ordinary objective HUD:

1. repair yourself (you arrive at 35% frame)
2. get your squadmate up (one robot arrives downed)
3. buy an Ancient Rifle
4. fit it to a robot
5. choose an operation

Finishing the fifth sets `completed_tutorial` — the same flag the old GO FORTH
sign set — so every existing reader of it (the signs, the toast, LessonPrompts)
sees a finished tutorial without knowing the induction replaced them. From then
on the depot is just the depot.

- **`Campaign/induction_objective.gd`** — a MissionObjective that completes on
  an EVENT rather than a place. Every other objective in the game is spatial
  because every other objective happens in a level; these happen at base and
  are verbs, not destinations. It uses the base class's own `_on_activated` /
  `complete()` hooks, so the tracker, the HUD, the ordering and the reward
  plumbing all treat them as ordinary objectives and none of them had to learn
  the induction exists.
- **`Campaign/induction.gd`** — builds the five in code and owns the "all done"
  rule. Built in code, not authored into the level: the depot is TERRAIN's file,
  these exist only at base and only once, and a level should not carry nodes
  that are freed on every visit after the first.
- **`TestCharacter.healed(amount, healer)`** — new. The squad's robots have had
  `revived` for a long time; the player had nothing, so "are you patched up yet"
  could only be answered by polling.
- **The objective HUD follows the OBJECTIVES, not the mission.** It hid whenever
  `in_mission` was false, which at base is always — the induction would have set
  five objectives nobody could see. At base with none, it still hides.

**Gates.** check.sh: PASS. **smoke.sh: PASS** (booted clean, 15s, 3 warnings).
test.sh: running at hand-off. New suite `tools/test_induction.gd`, 27 checks,
all passing — it walks the whole thing: a fresh save, each of the five done the
way a player would do it, the visit after (which must be an empty depot with
nobody on the floor), and an unfinished induction resumed.

**What the test caught, which is why it exists.** The first run reported TEN
objectives, not five. `on_level_loaded` fires on every arrival at base —
`World._ready` calls it at boot and the train calls it coming home — so a set
was built per visit and stacked up. Everything else on that run failed
downstream of it. `Induction.clear()` now runs on every base arrival whether or
not a new one follows, using remove_child before the deferred queue_free so the
dead objectives leave the group before `objectives.refresh()` collects them in
the same frame.

**Also this session:** the induction is rebuilt on every visit until finished
rather than marked off in the lesson ledger — a player who quits half way
through would otherwise return to an objective telling them to revive a
squadmate who was standing up.

**From the first playtest, fixed.**
- **The wallet and the objective list drew on top of each other.** Resources and
  compute own the top-right corner AT BASE and hide in the field; the objective
  list did the exact opposite, and `wallet_hud.gd`'s own header says so — "the
  objective list owns that corner in the field and hides at base, so the corner
  is free there". The induction broke that assumption. The panel now drops below
  the wallet at base, measured off `WalletHUD.ROW_BOTTOM` rather than a copied
  number so moving one moves the other.
- **The Foundry viewmodel was too small and its sights did not line up in ADS.**
  Fixed by arithmetic rather than nudging: the viewmodel hangs off the player's
  Camera3D, so a point on the gun can be expressed in the CAMERA's own frame and
  "the sights are centred" is just x == 0, y == 0. A probe reported the sights at
  camera-space x = +0.024 with the default `ads_position` of (0, 0, -1.077)
  shoving the gun 0.19 further sideways. Holder scale 0.18 → 0.26, and
  `ads_position` solved so both sights land on the axis — measured back at
  x = -0.000, y = +0.004 (rear) and -0.004 (front), symmetric about the
  crosshair. `tools/preview_viewmodel.gd` renders the first-person view from the
  player's camera in both poses with a crosshair drawn at dead centre, which is
  how this was confirmed by eye as well as by number.

**The viewmodel pose bug, and a trap in the class default.**
`PlayerEquipment.update_view` lerps `viewmodel.ROTATION`, which is RADIANS, but
the pose exports are authored as though they were degrees — the class default
is `base_rotation = Vector3(-0.3, 6.0, 2.8)`, and 6.0 radians is 344°. The bolt
rifle inherited that default, so its HIP pose was thrown into a near-full turn
with a 160° roll: the gun sat across the screen with its magazine pointing up,
which is what the human photographed and read as "it's not ADS at all". ADS was
correct the whole time — `ads_rotation` is zero, so it was the only pose the
default could not spoil. `bolt_hud_weapon.tscn` now authors `base_position`,
`base_rotation`, `ads_position` and `ads_rotation` explicitly and depends on no
class default.
**Three other held items still inherit it** — `grenade_hud_weapon`,
`knife_hud_weapon` and `rocket_hud_weapon` — and `shotgun_hud_weapon` sets
`Vector3(5, 0, 2.8)`, which is the same mistake written out. Left alone: the
brief was the bolt rifle, and the shotgun is no longer player-usable. Worth a
decision, because either the default is wrong or four weapons are.
`tools/preview_viewmodel.gd` now poses in radians like the game does; posing it
in degrees rendered a pose the game never shows, which is why the first pass
looked correct and the game did not.

**ADS IS NOT A ZOOM, it is the rear sight arriving at your eye.** The first
version put the sights on the view axis and left them where the gun already
was — 93 cm away, so the aperture was a small square in the middle of the
screen and the whole thing read as "centred, then zoomed". Pulling the
viewmodel back along the barrel until the rear sight sits ~28 cm from the
camera is what makes it sight THROUGH the aperture: `ads_position.x` 0.31 →
-2.188, which moves the gun 0.65 m towards the eye and leaves x and y
untouched, so the alignment solved earlier still holds. The butt ends up behind
the camera and is clipped, which is correct for a stock on your cheek.

**The soldier icon carries its rifle**, now that the frame is issued one.
Compared against the alternatives first (`tools/preview_chassis_icon.gd` renders
a chassis armed and bare, three-quarter and side, each flipped): the
three-quarter keeps the eye that makes a soldier a soldier AND shows the gun,
where the side view reads the rifle better but reduces the body to a plain pill.
Kept the framing bake_icons already uses.

**A design change the tests forced.** The induction first restaged the casualty
and the 35% health on EVERY visit until finished. `test_endings` caught what
that meant: come home from an operation and you are healed by
`_repair_at_base` and then immediately re-broken, so a player who survived a
mission arrived at base wounded. The casualty is now staged once per campaign
while the OBJECTIVES still rebuild until finished — which exposed a second bug,
that arming lived inside the staging function, so a resumed induction had five
objectives that were never activated at all. Arming is its own deferred step now.

**The armoury and the unlock ladder, same session.**
- **The shotgun and the pistol are out of the player's hands** — `in_shop`,
  `usable_by_player` and `usable_by_ai` all false on both. Enemy Shotgun
  Troopers are untouched: their gun is baked into `soldier_shotgun.tscn`, not
  issued from the catalogue.
- **Every soldier is issued an Ancient Rifle instead.**
  `chassis_soldier.starting_weapon_id` and `Campaign.starting_weapon_id` both
  &"m4", and `starting_stock` carries four of them — the gun comes OUT OF
  STORES (`fit_item` calls `armoury.take`), so setting the id without stocking
  it left all four Bravos holding nothing, which the induction test caught.
- **Walker behind Three Rivers, Spotter behind Mutaha.** The only chassis no
  mission names is now the Soldier, which closes the "buyable from minute one"
  hole the economy audit found.
- **Chaser and Leaper are gone from the player catalogue.** Removing them from
  the unlock lists alone would have done the OPPOSITE of what was wanted:
  `locked_by()` gates only what a mission names, so an unnamed frame is on sale
  immediately. They are enemy frames and are now enemy-only. Both keep their
  `kill_kinds` entries and icons, because the debrief still has to draw them.
- **The induction is SEVEN objectives** — repair yourself, revive the
  squadmate, buy an Ancient Rifle, put it in your own hands, order a FOLLOW,
  order an ADVANCE, choose an operation. Squad command is the game's actual
  verb and had no lesson at all; `SquadCommander.order_issued` carries the
  verb, and each objective wants its own, which the test pins so a FOLLOW
  cannot tick ADVANCE off with it.
- **THE PLAYER is the one who musters unarmed, not a squad robot.**
  `_seed_new_campaign` issues a rifle to every ROSTER record and the player's
  own record is not in `roster`, so the squad arrives holding rifles and you do
  not — which is the only reason the buy and fit objectives are not already
  complete when they are built. Stores carry exactly four rifles and all four
  are issued, so there is no spare and the shop trip is real.
  BUY is measured against what you owned when the induction started rather than
  "is there one in stores", because the latter reads false again the moment the
  player fits it; FIT looks at the player's own record. Either order works.

**Needs the human.** The induction has been walked headlessly, not played. The
wording of the five blurbs, and whether repairing yourself to FULL is the right
bar for objective 1, both want a playtest. `Campaign.tutorial_player_health`
(0.35) sets how hurt you arrive.

---

## 2026-09-28 (later) — the Foundry Rifle, and the heavy trooper it exists for

**Landed.**

- **Enemy Rifle Trooper 100 → 60 frame**, matching the player's Soldier.
  `chassis_rifleman.tres` and `soldier_rifle.tscn` both, so the chassis and the
  scene cannot disagree. Body for body a trooper is now worth a trooper; it was
  a 3:1 loss with the identical gun.
- **New `rifleman_armoured` — "Heavy Rifleman", 100 frame, slower (0.87).**
  `soldier_rifle_armoured.tscn` is `soldier_rifle.tscn` with a distinct look:
  `base_tint` steel, `metallic` 0.8, `roughness` 0.42 and a narrower paint band,
  so it reads as plated without re-treading the armour geometry the human
  rejected. Those four are exactly the shader parameters `faction_livery.gd`
  does NOT overwrite at runtime — it only sets faction_color, paint_blend,
  marker_energy and shutdown — so the distinction survives the repaint.
  Sprinkled in by `tools/sprinkle_heavies.sh`, at most one per squad and only
  every Nth squad: Coast 5, Three Rivers 5, Mutaha 13, Mutaha City 12.
- **The Foundry Rifle** (`bolt`, 130): `bolt_rifle_model.tscn` is the pack's
  `SniperRifle_6` — chosen by rendering all six sniper variants and looking —
  with its `DarkWood` surface overridden to a cast alloy and a box magazine
  added under the receiver. The pack guns are one mesh with five NAMED surfaces,
  which is why swapping only the stock is a one-line override. Palette taken
  off the m4's own materials so it comes off the same production line.
  `ai-wep_bolt.tscn`, `bolt_hud_weapon.tscn` (FireModes.MANUAL, the bolt path
  that already existed for the pump), `item_bolt.tres`, a `7.62` AmmoStock, and
  baked icons.
- **`Campaign.stage_tutorial`**, off in lab_mode. The induction casualty from
  earlier today was firing inside LAB RUNS — a downed robot and a 35% player in
  the middle of a controlled measurement, found in a lab log.
- **The rifle lost its telescope and gained its sights.** The scope could not be
  hidden or dropped — it is triangles mixed through three surfaces of one merged
  mesh — so `tools/bake_bolt_mesh.gd` rebuilds the mesh without them, cutting
  every triangle above y=0.38 into
  `Character/weapon/models/bolt_rifle_base.res`. 668 triangles out, the Glass
  surface gone entirely. Onto that: iron sights front and rear, a slotted
  handguard with clamps, a bolt knob, ejection port, stock comb and side panel,
  and sling loops.
  **Every position is measured, not eyeballed** — a probe of the baked mesh put
  the barrel top at 0.387 over the receiver and 0.363 at the muzzle, the barrel
  at 0.132 across and the stock comb at 0.158, all centred on z=0. The first
  pass placed parts by eye and they floated: sights sunk into the barrel, fins
  more than twice the barrel's width, a comb hanging in the air.
- **`icon_art.gd` needs a MODEL_OVERRIDE for it.** `model_for()` finds an icon's
  model by looking for an instanced .blend/.fbx inside the weapon scene. A gun
  built from a baked ArrayMesh has none, so it silently fell back to the generic
  drawing and the armoury showed a table. Same fix the shotgun and machine gun
  already carry.
- **Shotgun Trooper 100 → 60** as well, chassis and scene. The infantry ladder
  is now coherent: Leaper 45; Soldier, Rifleman, Shotgunner, Chaser and Mechanic
  60; Spotter 80; Marksman 90; Heavy Rifleman 100.
- **The depot's six info markers are gone** (DEPOT, TERMINAL, MUSTER, BAYS,
  RANGE, TRANSIT), with their parent node, the orphaned script ext_resource and
  load_steps. **`maps/**` is TERRAIN's lane** — done on the human's direct
  instruction, recorded here so the board sees it. The depot now carries no
  Label3D teaching of any kind.
- **`mutaha_2_city` had empty `requires`**, so the 132-enemy city op was offered
  at the terminal on a BRAND NEW SAVE, next to First Contact. Now gated behind
  `mutaha_1_blocks`. Mine, from the session that authored it, and found only by
  booting a fresh campaign rather than reading the resource.
- **The Foundry Rifle's magazine reseated.** In game it clipped through the
  trigger guard and hung off nothing. Measured the underside: the guard hangs to
  y=-0.232 across x 0.20-0.70 and there is NO geometry at all between x 0.70 and
  1.00, while the magazine sat at x=0.92 raked 12° — which swings its top-rear
  corner back to x≈0.60, inside the guard. Now a MagWell box overlaps up into
  the receiver and the magazine (thinner: 0.32x0.22, was 0.46x0.32) enters it by
  0.08 with five ribs and a floorplate. No rake: a raked magazine in a straight
  well is how the clipping started.
- **`kill_kinds.gd` gained the heavy**, in both tables, plus its baked icon.
  `test_quadcopter` caught this: a new chassis the debrief cannot draw would
  have tallied every heavy killed as a nameless fallback. A new enemy frame
  needs a FRAMES entry, a SCENES entry and an icon bake, not just a .tres.

**Gates.** check.sh: **PASS** (533 resources). test.sh: running at hand-off.
Six lab runs on `Campaign/lab/plans/foundry_rifle.tres`.

**What the lab actually said, including where I was wrong.**
The gun was tuned by measurement, not by eye, and the first two settings were
wrong in opposite directions:

- **70 damage one-shot a 60-frame trooper** and the Foundry won 100% against
  line infantry and 67% against heavies — a straight replacement for the Ancient
  Rifle, which is the shotgun mistake inverted.
- **55 damage with a 1.15 s bolt** was worse against BOTH. Arithmetic says why:
  the m4 kills a heavy in 3 gaps × 0.35 = 1.05 s, so no damage number rescues a
  1.15 s cycle. The cycle was the binding constraint, not the damage.
- **Accuracy, not damage, was doing the work.** At 9 mrad against the m4's 18 the
  Foundry out-damaged it 1.3-1.9× in every single configuration. Cutting it to
  15 mrad is what finally produced a trade.

Final, n=12: LINE 67% vs 67% (parity), HEAVY 17% vs 50%. Matchup 2 is the
interesting one — the Foundry deals 4125 damage to the Ancient's 2588 and still
only draws, because a 55-damage round into a 60-frame body wastes half itself.
That overkill IS the trade.

**A fresh save, booted and read off the running game** (`tools/probe_fresh_start.gd`):
500 resources, 4 seats, four Bravos on shotguns at 60 frame, the player at
35/100 with Bravo-4 down at 1/60 — the induction casualty works. **And zero
tutorial signs**, because the depot never had lesson content and now has no
labels either. There is no tutorial MISSION; the tutorial was always the base
signs, `homebase_level.tscn` still has fourteen of them, and porting that
content into the depot is the open M2 blocker.

**Needs the human.**
- **The Foundry Rifle is gated by nothing.** No mission names it in `unlocks`,
  so it is on sale at 130 from the first visit to base — the same hole the
  Walker sits in. The new op between Proving Ground and Basin is the obvious
  home for it.
- **The first-person viewmodel is unverified.** `bolt_hud_weapon.tscn`'s Holder
  transform is scaled off the m4's by model length and never seen in game. It
  will need moving by eye.
- **Two scenes want an editor reload**: `soldier_rifle.tscn` (60 hp) and
  `test_character.tscn` (the 7.62 stock). New icons import on editor focus.
- **The Shotgun Trooper is still 100 frame**, now tougher than the Rifle Trooper
  it stands beside. Left alone deliberately — the instruction named the rifle
  trooper, and dropping the shotgunner is a balance call, not a typo fix.
- **±15 points is the arena's noise floor** at 4v4 and 12 repeats. The same
  configuration returned 50/58/63/67% across four runs, so nothing smaller than
  about 20 points should be read as a result there.

**Blocked / next.** Resource and compute allocation is waiting on the new
mission between Proving Ground and Basin. The Foundry's real job — an
anti-armour multiplier — cannot exist until the armour rule lands, which is
still parked on the commit question.

---

## 2026-09-28 — a dangling tag, the tutorial's opening state, and why the suite never finished

**Landed.**

- **Proving-ground hostiles advance now.** They were not "chilling" because of a
  posture — all six specs were already `ADVANCE`. `post_tag` named
  `obj_arena_centre`, which `proving_level.tscn` does not contain, so
  `_apply_posture` fell through to `squad.get_center()`: an order to advance onto
  the ground the squad is already standing on, satisfied on the first tick. They
  sat on the muster platform (`HostileMuster`, y=3.2) for the whole mission.
  `EnemyForceSpawner._advance_destination()` now points a post-less advance at
  the player's spawn and warns when a tag WAS authored and did not resolve;
  `post_tag` is cleared on the three arena missions so an empty tag reads as a
  decision. Measured on `arena_5_proving`: twelve hostiles, mean z 36.3 → 11.0,
  nearest 58.8 m → 7.3 m in ten seconds. `obj_arena_centre` was the only dangling
  `post_tag` in the project — every other one resolves, so nothing else moved.
- **Starting resources 300 → 500**, `Env/world.tscn` (SHARED — one line, on the
  user's instruction). Only affects a FRESH campaign; `starting_resources` is
  read by `_seed_new_campaign()` alone.
- **The first tutorial opens on a casualty.** `Campaign._stage_first_tutorial()`
  downs the last-mustered robot and drops the player to `tutorial_player_health`
  (0.35) on the first base load. Gated on `completed_tutorial` AND
  `state.mark_lesson(&"induction_triage")`, so it happens once ever, and
  `_queue_base_save()` persists that. Bodies only, never records — writing the
  damage to the record would bill the player compute to undo a scripted lesson
  and could bench the robot. One full repair-tool reservoir (100) covers both
  jobs: 65 to heal yourself, 29 to bring the robot past `revive_at_fraction`.
- **`Campaign._is_base()`**, because `level == base_level` compared a Node to a
  PackedScene and was never once true. The intended early return therefore never
  fired — which is load-bearing, since the base musters in the code below it — so
  only the spurious warning was fixed, not the control flow.
- **The debrief's KILLS and REVIVES counters read 0 on a won mission** — mine,
  from earlier the same day. The count-up in `_physics_process` iterated two
  named fields (`_resources`, `_compute`) that the builder had to remember to
  assign; KILLS and REVIVES were built, shown, and never animated, so they sat
  on their `from` value. A screenshot showed "KILLS 0 / REVIVES 0" above a squad
  card reading 74 kills : 17 revives — the data was always right, only the
  display was stuck. Fixed at the class: `_counter()` now registers every number
  it makes in a `_counters` list, so a counter added later cannot be forgotten,
  and the two named fields are gone. `test_endings` gained four checks — every
  counter must reach its `to`, and a named check that a squad of 5+3 kills and
  2+1 revives reads 8 and 3 at the top.
- **`tools/audit_economy.gd`** (new): prices the whole campaign in "baselines"
  (1 Soldier + 1 Ancient Rifle = 130) against the bodies each op fields. Reads
  world.tscn, the catalogue, the specs and the level scenes as packed data —
  nothing hardcoded, nothing instantiated, no save written.

**Gates.** check.sh: **PASS** (227 scripts, 524 resources). test.sh: **30 suites,
4 failures** — and this is the first complete run in three sessions. It had been
stalling at 26 and never printing a total, so **`test_vehicle`, `test_walker` and
the water-navmesh suite had not run at all**; all three pass now. Of the four
failures, two are TERRAIN's and pre-existing (`pittsburgh_level` bridge spacing,
`the mutaha squad spawn and exit stand on the ground`) and two are
`test_tutorial` honestly reporting missing content (below). smoke.sh: not run.

**Why the suite stalled — worth the next agent's attention.** `test_tutorial.gd`
was HANGING, not failing. The rebuilt depot has six Label3Ds (DEPOT, TERMINAL,
MUSTER, BAYS, RANGE, TRANSIT) and none of them is a lesson, so
`_sign_saying("{reload}")` returned null — and a runtime error inside a coroutine
aborts the coroutine WITHOUT aborting the process, so `quit()` was never reached.
Eighteen stuck `--script` instances had piled up, one per suite run, throttling
the machine. The test now bails through an epilogue that calls `quit()` and says
what is missing. Any test that dereferences something it looked up needs the same
guard.

**That is also the answer to "the tutorial is gone".** The TutorialLabel and
toast machinery are intact and tested; the CONTENT went with the old depot
layout. Nothing in `maps/depot_level.tscn` carries `toast_text` any more, so
there is no lesson in the base to stand at and nothing sets
`completed_tutorial`. Re-authoring those lessons is a GAMEPLAY job, but the signs
live in a TERRAIN file — worth the coordinator deciding which lane places them.

**Needs the human.**
- **Nothing in this session was playtested.** The advance fix, the tutorial
  opening and the 500 grant are all verified headlessly only.
- **The tutorial opening will fire on the live save.** It reads
  `completed_tutorial: false` despite arena 1/3/5 being cleared, so the casualty
  is staged on the next boot rather than only on a brand-new campaign. Adding
  `and state.completed_missions.is_empty()` to the gate makes it strictly
  new-campaign-only if that is wanted.
- **`mutaha_2_city` has no clear bonus at all** — 0 resources, 0 compute, for the
  second-largest fight in the campaign. That is an omission in last session's
  authoring, not a design choice.

**Blocked / next.** The economy audit says three things and none of them is
fixed: Valley Basin is a 6.6× step in opposition against +1 seat; the Rover is
unlocked BY Basin, so the obvious answer to it cannot be bought until after; and
the Walker (320, no mission gates it) is buyable from the first visit to base,
which makes it the real answer to Basin and probably not the intended one. All
three are balance calls for the human. Armour (Phase 2) is still parked on the
commit question, which has now been asked three times.

---

## 2026-09-28 — Phase 1 finishes, and a lab spawn bug that had been faking results

**Landed.**

*Phase 1, the four assigned items.*
- **Mutaha activation distance.** The board called this "one number in level data". It is not — `activation_distance` is an `@export` on the ROBOT scenes in `Character/characters/ai/`, and five of them carried 250. Dropped the three infantry ones (`soldier_rifle`, `soldier_marksman`, `soldier_shotgun`) to 120. Left `enemy_helicopter` alone (a bomber is meant to be seen coming) and `spotter_drone` alone (player-side, so `_is_player_side()` exempts it from culling and its 250 is inert).
- **Spotters park at base.** New `_parked()` on `spotter_drone.gd`, keyed off `Campaign.in_mission` so it covers the depot and home base with no per-level data, resolved lazily through the group because node ready order means the campaign does not exist at `_ready`. Parked: no lift, no orbit, rotor stopped, gravity restored. The early return sits before `_lifted` is set so it still spawns airborne on a real mission.
- **Soldier weapon scale.** `WeaponMount` baked 0.25. Now 0.40 on `soldier_chassis`, `soldier_rifle`, `soldier_marksman`, `soldier_shotgun`. Measured: 0.97 m → 1.56 m, 49% → 78% of body height. `mechanic_chassis` deliberately left at 0.25 — what hangs on it is a welder, not a gun. Knock-on: those scenes are what their chassis icons bake from, so `rifleman`, `marksman`, `shotgunner`, `soldier`, `mechanic` were re-baked.
- **Lobber Rover icon.** Fixed, and the cause is worth keeping: `vehicle_rover.tscn` carries a `DisplayGun` stand-in on its mount, and the baker's "already armed, leave it alone" check treated that as a real weapon — so both rovers baked wearing a placeholder neither of them fights with. At runtime `equip_weapon_scene` CLEARS the mount first; `bake_icons._armed_body` now does the same. The two icons differ.

*Armour prep (Phase 2 note 2 — the perishable one).*
- `Campaign/lab/plans/armour_baseline.tres` + `tools/lab_armour.gd`, run and captured while no armour rule exists. Nine matchups: the ladder (small arms into light / medium / unarmoured control), damage types against one hull, the anti-armour counter, and combined arms.
- Headline for the multipliers: **anti-armour is currently strictly WORSE than a rifle.** Autocannon troopers did 217 damage per run into a walker against a rifle's 221, and lost every fight where rifles won a third. Once MULT lands that must invert, or the rule did not work.
- **There is no anti-armour any AI robot can carry.** `item_rocket.tres` (Recoilless) is `usable_by_ai = false` with no `ai_scene`; the autocannon's `chassis_whitelist` is walker/rover. Matchups 6-7 only work because `weapon_swaps` ignores whitelists — they are a proxy, not something the campaign can field. The counter needs an AI weapon scene before armour ships or it exists only in the player's hands.

*The lab spawn bug.*
- `Managers/lab.gd._ground()` cast a ray from 1 m above the requested point down 20 m and returned the point UNCHANGED on a miss. At full roster the spawn ring is ~7 m across, so on any map with relief the outer robots started their ray inside a bank, missed, and were placed at the site's own height — under the terrain, dead on the first frame. Now routed through `Campaign/ground_snap.stand()`, the same helper the enemy spawner uses, with a widened ±60 m ray as fallback.
- Effect: total damage in a 30-seat fight roughly DOUBLED, and matchup 3 (artillery vs balanced) flipped from 100% to 0%. Every lab number taken on a map with relief before this fix is suspect.
- New plans: `open_ground.tres` (200 m on Coast Road) and `open_30v30.tres` (four 30-supply force designs). `lab_armour.gd` takes `--plan=`, `--speed=` and `--watch`.

**Gates.** `check.sh`: **PASS** throughout. `test.sh`: 25 suites, **two failures, neither mine** — the known `pittsburgh_level` bridge spacing (6.7 m), and a new `test_terrain` failure, "the mutaha squad spawn and exit stand on the ground". `maps/mutaha_level.tscn` was modified at 07:57 today; it is TERRAIN's file and I did not touch it. `smoke.sh`: **not run.**

**Needs the human.**
- **Reload in the editor before saving over them:** `soldier_chassis`, `soldier_rifle`, `soldier_marksman`, `soldier_shotgun` (weapon mount scale, activation distance).
- **The commit question is unresolved.** The board rules that review happens by playtesting rather than in GitHub Desktop, and the armour brief says to land `enemy.gd` as one commit before starting Phase 2. That contradicts a standing instruction to me never to commit. I have made no commits; `enemy.gd` is still uncommitted and still carries the culling work plus the corpse fix. Phase 2 is blocked on this.
- **Draw-call count on Mutaha** still open from YOUR DESK — unchanged, still the thing that decides whether LOD is worth building.

**Blocked / next.**
- **Unverified:** the 250→120 activation change. At spawn it takes awake hostiles 3 → 0, which is a small delta because the culling fix already did the work. The gain should come mid-advance and I could not measure it — the probe that put the player inside the enemy force collapsed (physics fell to 0.05 ms, identical counts in both conditions; the mission ended and the debrief's PauseHold froze everything). Defensible by reasoning, not by measurement. Wants a real playthrough.
- **I was wrong twice, recorded so nobody repeats it.** (1) I reported Lobbers putting 18.8% of their damage into their own side and framed it as an explosive problem. On open ground at 200 m it is 1.0% — the arena figure was three Lobbers advancing shoulder to shoulder on one target in a small space. Friendly fire here scales with crowding and shared targets, not damage type. (2) When the 30-seat mirror control came out 100%/0%, I first blamed the culling asymmetry between ALLIED and ENEMY. Wrong: `lab.gd` sets `AWAKE_FOR = 1.0e6` and wakes every spawned robot permanently, so culling never applies in the lab. The real cause was the spawn bug above.
- **Next, in order.** (1) Per-weapon target selection, which is the standing request: give `AIWeapon` an `acquire(owner, candidates)` that defaults to the owner's `combat_target` so nothing changes, and let a mortar or GL override it to skip targets squadmates already hold and keep its own for at least the round's flight time. `Enemy.weapon_target` already exists as a separate Vector3, so the split is half-built. Prerequisite: `AIWeapon` has no `projectile_speed` or flight-time field at all. (2) Re-measure the 30-seat fights now the spawns are fixed — the mirror moved to 67/33 at n=3, which is as close to even as three runs can report, but n=3 is not a result.

---
