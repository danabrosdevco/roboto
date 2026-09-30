# Dispatch — drafted asks, for the human to send

Written 2026-09-28 by MARKETING. **Draft only.** This lane cannot message the
other agents; these are written so they can be pasted and executed without me in
the room. Nothing here is urgent before 2026-10-08 unless marked otherwise.

Ordered by how much they unblock, not by size.

---

## 1 → COORDINATOR · a stale GDD row, and one open question

**Updated 2026-09-28.** The recruitment question is answered — the human
confirmed it live — so this is now a correction to file rather than a question to
answer.

> **Recruitment is LIVE and `docs/GDD.md` §7 says it is not.** The row reads
> "Recruitment — not built — the squad can only shrink." The human confirmed on
> 2026-09-28 that the factory works and it is in the squad manager, and the build
> agrees: `Campaign/campaign_state.gd:624` defines `recruit()`,
> `Character/hud/squad/factory_page.gd:240` calls it, FACTORY is one of the four
> tabs in `Character/hud/squad_manager_ui.gd`, and
> `Character/hud/lesson_prompts.gd:36` teaches the player about it. GDD §4
> already presumes it works. Please correct §7 — it is the row a future lane
> would trust.
>
> **Still open — salvage.** `Campaign/campaign.gd` has `salvage_this_mission`,
> `add_salvage()` and `state.award(salvage)` at debrief, so salvage is real
> money. But §7 also says there is one undifferentiated `earned` pool and
> `restock_roster()` is free. Is "salvage and repair are the economy" — the
> fourth claim in `docs/briefs/MARKETING.md` — true on screen, or is the honest
> version just "salvage is where money comes from"? Marketing has written the
> narrow one.
>
> **Also worth a GDD note.** The pillar line *you are not the gun, you are the
> commander* is a good design pillar and a false marketing claim — the human's
> read on 2026-09-28 is that the player is an agent-AI taking compute from other
> AIs and is therefore "just a gun" too. Marketing has retired it from all
> outward copy and replaced it with two lines that split the job
> (`docs/marketing/POSITIONING.md`). No GDD change requested; flagging so the two
> documents are known to differ on purpose.

---

## 2 → the HUMAN · five minutes, before 2026-10-08

**The build is called Roboto and the title screen is not.**

> `project.godot` line 13 is `config/name="Roboto"`. That string becomes the
> window title, the exported `.exe` basename, and what the Steam overlay reads.
> The build your friends get on 2026-10-08 will say "Roboto" in the title bar
> while the title screen says DATA CENTER WARS 2109.
>
> `project.godot` is on the board's shared list, so MARKETING has not touched it.
> Whoever takes it, say so on the board first. Two lines:
> `config/name="Data Center Wars 2109"`, and set `config/description` while the
> file is open, because the export reads that too.
>
> Worth knowing either way: "Roboto" is Google's typeface and a crowded search
> term. "Data Center Wars 2109" is searchable and unclaimed.

---

## 3 → the HUMAN · a decision, not a task

**Two things only you can answer, both cheap now and expensive in six months.**

> **Asset licences. Upgraded to a hard blocker 2026-09-28**, when you chose a
> free demo into a paid 1.0 — a paid release is exactly the case these licences
> distinguish.
>
> `textures/` carries two licence documents
> (`PSX_Textures/Game Asset License Agreement.pdf`, `Set4All/License.txt`).
> **None of the twelve folders under `sounds/sfx/` carries a licence or credit
> file** — including `free cinematic sfx` (freesound material, licences ranging
> from CC0 to CC-BY-with-attribution to non-commercial), `psx ui sfx`,
> `Robot Droid Voices`, `superior soundfx`, and `darkdrone`, which is the title
> music. Free to download is not free to sell. A `CREDITS.md` naming every pack,
> its source and its licence is an hour now and a week later.
>
> **And the one I missed first time round: the HUD font.** DS-Digital is the
> game's entire visual voice — HUD, capsules, screenshots, trailer, everything —
> and fonts of that kind are commonly distributed free for *personal* use with
> separate commercial terms. **Check it early.** If it does not clear for
> commercial use, a substitute has to be chosen before any capsule or trailer is
> built on it, not after.
>
> **The AI content disclosure.** Valve requires a declaration of AI-generated
> content — art, audio, code — and the answers appear publicly on the store page.
> This game is built by four AI lanes. Decide the answer deliberately, in
> writing, well before there is a page. Getting it wrong after launch is a policy
> problem rather than a copy problem.

---

## 4 → GAMEPLAY · not before M2; the enabler for everything visual

**Generalise the screenshot tool that already exists.**

> `tools/mockup_shots.gd` already does the hard part: it loads a real level for
> its lighting, stages subjects, parks a camera and writes the viewport to PNG,
> headless, via
> `godot --audio-driver Dummy --path . --script res://tools/mockup_shots.gd -- <out dir>`.
> It is hard-wired to the depot and to kit mock-ups (`LEVEL`, `STAGE`, `SOLDIER`).
>
> What marketing needs is the same script taking its shot from arguments or a
> small resource: level, camera position, camera target, resolution, HUD on/off,
> and which squad to place. Five parameters and the existing body. Please do not
> write a new capture tool — most of this one is done, and a second one will
> drift from the first.
>
> The HUD toggle matters more than it sounds: a store page wants clean frames and
> a devlog wants the green phosphor, and re-staging a shot to get both is the
> thing that makes capture expensive.

---

## 5 → TERRAIN and GAMEPLAY · a question about the tone, for the board

**There is no rain in the game.**

> `docs/briefs/MARKETING.md` describes the tonal centre as "rain falls on a
> planet bereft of the people that constructed it." I grepped `Env/`,
> `Character/`, `Managers/` and `Campaign/` for rain, precipitation, weather and
> fog: **nothing.** The only matches are the letters inside "terrain".
>
> This is not a marketing question and MARKETING is not asking for it as a
> feature. But if rain is the tonal centre of the game, it is a board item rather
> than a line in a brief, and marketing cannot show it, film it, or put it in key
> art until it exists. Flagging it so it is a decision rather than an assumption.
>
> Cheapest honest substitute in the meantime, if one is wanted: the tone is
> already carried by the dark title screen and the drone in
> `sounds/sfx/darkdrone`, which is genuinely good and genuinely shippable. A
> trailer can be built on that alone. See `docs/marketing/POSITIONING.md`.

---

## 6 → the HUMAN · the itch screenshot set, for Gate B

**Not the 2026-10-01 recording.** You said those clips are yours and your
friends do not need marketing, and I have not written a shot list for them. This
is the separate set of five stills an itch page needs once Gate B clears
(`docs/marketing/RUNWAY.md` §1) — mid-to-late October at the earliest, and only
after §4 above makes capture cheap.

Written as executable shots so whoever takes them does not need me:

**Revised 2026-09-28: one shot per locale.** The human's correction — *"there's
not one dead city you're in a ton of different locals"* — is an operational fact
as well as a creative one. Five screenshots from five places read as a big game;
five from one map read as a demo. So every shot below is pinned to a *different*
level, and the subject is chosen to suit the place rather than the other way
round.

| # | Level | Shot | Why it is on the list |
|---|---|---|---|
| 1 | **coast road** | **Squad in formation, mid-distance, no contact.** Camera at squad height, eight to twelve metres behind, four frames legible and separated against open ground. No HUD, plus a second pass with HUD. | The cover shot. It has to say "these are capsules and there are four of them" in one glance. Nothing else does that job. Open coastal ground gives the cleanest separation. |
| 2 | **Mutaha** | **An order being given.** First-person, HUD on, the order legible in green phosphor, squad visibly moving to it in the same frame. | The only shot that shows commanding. Town geometry makes the movement read as a decision rather than a walk. |
| 3 | **valley basin** | **A Mechanic standing a downed frame back up.** Side-on, both robots in frame, close enough that the welder reads. HUD on. | The emotional claim and the one mechanic nobody else has. **Also the source frame for the itch GIF.** Open basin keeps the two figures uncluttered. |
| 4 | **Pittsburgh / three rivers** | **A Walker being flanked.** Wide enough that its turret facing and the flanking frame are both visible — the point is that the guns point the wrong way. | The counter-play shot. Bridges force the flank to read as geometry. |
| 5 | **depot (home base)** | **The squad manager, FACTORY or ARMORER tab, a real roster with ranks showing.** Full-screen UI, no world behind it. | The persistence shot. Tactics buyers look for this image specifically and its absence reads as "no meta layer". Recruitment is live, so the FACTORY tab is now legal to show. |

Resolution 2560×1440 or 1920×1080, consistent across all five. **Pick one time
of day and keep it across every level** — a mixed set reads as a work in progress
even when each individual frame is good. Variety should come from the *places*,
not from the lighting.

**Do not shoot:** anything DARK (marksman, mortar, quadcopter bomber as an ally,
lobber rover, mortar track), anything with the three record blockers visible
(quarter-size soldier weapons, the duplicate Lobber Rover icon), or the
laboratory. See `docs/marketing/CLAIMS.md`.
