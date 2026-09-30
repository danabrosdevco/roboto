# Claims ledger — what marketing is allowed to say

Written 2026-09-28 by MARKETING. Derived from `docs/GDD.md`, plus spot checks
against the build where the GDD was silent or disagreed with itself.

**The rule this file exists to enforce:** market only what is tagged LIVE. This
is the working list, so that no piece of copy has to re-derive it. Every claim
below is one a stranger could read on a store page.

**Three columns of status, deliberately:**

- **SAY IT** — LIVE, verified, safe in a trailer or on a page.
- **HOLD** — real but not safe to sell. DARK, unplaytested, or a claim that
  outruns the build.
- **ASK** — the documents disagree, or the build disagrees with a document. Per
  the standing orders these go to the human rather than getting inferred.

---

## SAY IT

| Claim | Backing |
|---|---|
| First-person squad-command shooter. You command robots. | GDD §1 |
| Persistent squad across missions, from a home base | GDD §1; `depot_level` |
| **Downed robots are not gone — a Mechanic stands them back up** | GDD §3 on the Spotter going *down* rather than destroyed; `Character/characters/ai/reclaimer.gd`; the game's own tutorial sign |
| Robots earn ranks — REGULAR → VETERAN → CAPTAIN | GDD §7 marks veterancy **LIVE**: the debrief awards XP and promotes. GAMEPLAN's claim that `add_xp()` is never called is stale and the GDD says so |
| Eight buildable frames, and they do different jobs | GDD §3 — all eight tagged LIVE |
| A Rover is a turret on wheels; a Walker is a turret on legs that takes leg kit a Rover cannot | GDD §3, verified 2026-09-24 (Nanite Reboot true for walker, false for rover) |
| The Walker's turret traverses slowly — flank it and both guns point the wrong way | GDD §3; pinned by `tools/test_walker.gd` |
| A Reclaimer drags salvage home | `reclaimer.gd` extraction → `CampaignManager.add_salvage` |
| A Spotter Drone is unarmed and only sees further — and it flies | GDD §3 |
| Signal is a second bar: near-misses degrade sensors and accuracy, and it recovers on its own while hull damage needs a Mechanic | GDD §6 |
| Weapons fall off with range — 12 m on a pistol out to 70 m on a marksman | GDD §4 |
| You buy and fit weapons, modules and equipment between missions | ARMORER tab, `Character/hud/squad/armorer_page.gd` |
| Compute buys seats — squad size is a decision you made earlier | Board ruling 2026-09-28; `Character/hud/lesson_prompts.gd` teaches it in-game |
| **You buy new robots in the FACTORY tab** | **Confirmed by the human 2026-09-28.** `campaign_state.gd:624` + `factory_page.gd:240`. GDD §7's "not built" row is stale — see ASK #1 below |
| **Compute is capacity, not money — it buys how many robots you can field** | Board ruling 2026-09-28 + `lesson_prompts.gd`. This is the spine of the pitch; see `docs/marketing/POSITIONING.md` |
| **The campaign spans unlike places** — sim arena, valley basin, coast road, three river bridges, Mutaha, a causeway | GDD §2 ladder; confirmed by the human 2026-09-28 ("a ton of different locals"). Five of six stages are LIVE; **causeway has no mission** |
| Missions brief over a baked map of the level | `show_mission_briefing` default true, `Managers/master.tscn` does not override it |
| A dark title screen under a slow drone | Verified in build: `Managers/master.gd` — splash → DATA CENTER WARS / 2109 → menu, with `sounds/sfx/darkdrone` looping on the MUSIC bus at −6 dB, fading out over 1.5 s on START |

---

## HOLD — real, not sellable

| Thing | Why it is held |
|---|---|
| **Marksman weapon, Mortar** | GDD §4 tags both **DARK**. Do not film. |
| **Quadcopter Bomber as a buildable ally, Lobber Rover, Mortar Track** | Board NEXT #4 — exist, none purchasable. Icons exist for three, which makes them look shippable. They are not. |
| **Spotter Drone and Walker balance** | Both LIVE and safe to *show*. GDD says every number on both is a first guess and unplaytested — so no claim about how they play, only that they exist. |
| **Progressive unlocks / a shop that grows** | `state.unlocked` is written and **never read**. The shop shows everything from minute one. This is the most tempting false claim available; it is the standard indie-tactics beat and it is not in the build. |
| **Suppression as a mechanic** | `Soldier.enter_suppressed()` and `SoldierState.SUPPRESSED` exist and nothing calls them. Signal degradation raises weapon spread and that is deliberately the whole effect. Say "sensors degrade", never "suppression". |
| **Possession** | `possession.gd` is complete, is instantiated in no scene, and calls a `Soldier.drive()` that does not exist. GAMEPLAN calls it the demo's signature moment; it is not reachable. |
| **Armour and damage types** | GDD §5 — **PROPOSED**, not in the build. Fully briefed, and the board explicitly defers it past M2. |
| **Six-map campaign ladder** | Causeway is the largest map in the repo and **has no mission**. Five stages are LIVE, and stage 2 is one mission of an intended six. |
| **Third faction (scavengers)** | Backlog, proposed, not scoped. |
| **Visible fitted equipment, NCO ranks with hats** | Mocked up, not started. The shape language is settled and rendered; the runtime that shows kit per loadout is missing. |
| **Rain and weather** | **Checked: there is no rain, no weather and no fog system anywhere in `Env/`, `Character/`, `Managers/` or `Campaign/`.** See the note below — this one matters more than its row. |
| Ammunition and resupply as a cost | `restock_roster()` is free on return to base. |
| Three currencies — shards, neural bits, compute | One undifferentiated `earned` pool. GDD §7. |

### The rain note

The most evocative line in the brief — *rain falls on a planet bereft of the
people that constructed it* — describes something that **does not exist in the
build.** I grepped for it specifically; the only hits are the word "terrain".

That is not a criticism, it is a direction. But two things follow. First: no
rain in any capture, any GIF, any trailer, or any key art, until it exists.
Second: if it is the tonal centre — and reading the brief, it is — then it is a
**feature request**, not a copy decision, and it belongs on the board rather
than in a marketing document. Drafted as an ask in `docs/marketing/DISPATCH.md`.

---

## ASK — the documents disagree

### 1. Can the player buy a new robot? — **RESOLVED 2026-09-28: YES, LIVE**

The human confirmed it directly: *"recruitment is live — the factory works it's
all in the squad-manager things."* Moved to SAY IT above. **GDD §7's
"Recruitment — not built" row is stale and should be corrected** (ask #1 in
`docs/marketing/DISPATCH.md`).

Kept here because the trail is worth preserving: GDD §7 said not built, GDD §4
presumed it worked, and the build agreed with §4 —
`Campaign/campaign_state.gd:624` defines `recruit()`,
`Character/hud/squad/factory_page.gd:240` calls it, FACTORY is one of four tabs
in `squad_manager_ui.gd`, and `Character/hud/lesson_prompts.gd:36` teaches the
player about it. The lesson: when the GDD contradicts itself, the build settled
it and the human confirmed it in one line. Ask early.

### 2. Is salvage visible to the player as *the* economy?

Plumbed and real: `Campaign/campaign.gd` carries `salvage_this_mission`,
`add_salvage()`, and awards it at debrief through `state.award(salvage)`. A
Reclaimer dragging a wreck home is a genuine loop.

But GDD §7 says there is one undifferentiated `earned` pool, and resupply is
free. So the honest version of "salvage and repair are the economy" is narrower
than the brief's fourth bullet: **salvage is where money comes from**, rather
than salvage being an economy with pressure in it. I have written the narrow
version. Confirm whether the wider one is true on screen.

### 3. Is the pillar true right now? — **no, in two independent directions**

The largest item on this page, and it got larger on re-reading the board.

**Direction one — the orders lose.** GDD §8: attack-a-target wins 100%, and
*advance*, *move & hold* and *hold at range* each win 0%. **One of the four
commands works.**

**Direction two — the player does not need them.** The board names this outright
as the **"long-range-god problem"** and ruled on 2026-09-28 that the answer is to
give the player better things to want rather than to take the option away. So the
player can currently out-range the whole problem alone.

Together those mean the honest description of the build today is closer to *a
first-person shooter with a squad you get attached to* than to *a command game*.
Both are being worked; neither is a marketing problem to solve with words.

**What it costs marketing, concretely:** "aiming is not how you win" is not
sellable copy today, so `docs/marketing/PITCH.md` and
`docs/marketing/POSITIONING.md` use "the rifle in your hands is not the point"
instead — true now, and it does not need a patch to stay true. It also does not
block a devlog: this is a *good* devlog, and "my headless test harness told me
three of my four squad orders lose every fight" is the most shareable single
thing this project currently owns.

This is the best argument for the runway being gated rather than dated, and it is
**Gate B** in `docs/marketing/RUNWAY.md`.

---

## Where the brief's four claims land

The standing orders list four distinctive things. Audited, and updated after the
human's confirmations on 2026-09-28:

1. **Persistent and repairable squad** — SAY IT. Strongest claim in the game.
2. **You buy and fit the squad between missions** — **SAY IT in full.**
   Recruitment confirmed live, so fitting, seats *and* buying frames are all
   legal copy.
3. **The frames are genuinely different, not tiers** — SAY IT. No balance claims
   about Walker or Spotter; their numbers are unplaytested by the GDD's own
   admission.
4. **Salvage and repair are the economy** — narrow it. See **ASK #2**.

### And a fifth the brief did not have

**Compute is capacity.** It buys seats, seats are how many robots you can field,
so taking compute makes you larger. It is LIVE, it is in the tutorial, and it is
the only motivation the game needs — which is what lets the setting stay
nameless. The brief predates the human's reframe on 2026-09-28; this belongs at
the top of the list of distinctive things, not off it. Argued in
`docs/marketing/POSITIONING.md`.
