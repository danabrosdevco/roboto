# MARKETING — session reports

**Only the MARKETING agent writes this file.** The coordinator reads it and folds
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
  from repeating it. A claim made about the game that turned out not to be in
  the build is exactly that kind of thing.

---

## 2026-09-28 (third pass) — four decisions taken, and the plan refitted to them

**Landed.** The human answered the four open questions. `docs/marketing/PLAN.md`
rewritten around them; `DISPATCH.md` updated.

**The decisions, recorded so no future session re-asks:**

1. **Free demo on Steam *and* itch, then a paid 1.0.** Puts Next Fest in play and
   turns the licence audits from housekeeping into blockers.
2. **Go dark until a trailer.** Reason given: a devlog looks expensive — "I'd need
   a website and YouTube and it's a lot."
3. **Lean in on the AI premise.**
4. **As close to free as possible.** Would spend on a score if the friend
   reception after M2 is good.

**Landed against those:**

- **Calendar rebuilt.** June 2027 Next Fest (14–21 June, registration closes
  **25 April 2027**). Steam page public January 2027, trailer April 2027 as the
  reveal, demo by the April deadline. October 2026's Fest has closed; February
  2027 needs a demo by 10 January and I do not believe in it.
- **One carve-out argued on decision 2, and one correction to it.** *Dark does not
  mean no page* — a store page collects wishlists passively from Steam's own
  discovery, tag pages and themed fests, with no posting and no cadence, and
  arriving at Next Fest with a cold list is the failure mode that makes the Fest
  worthless. So: page in January, trailer in April, Fest in June. Separately, the
  devlog was priced as a website plus a YouTube channel plus edited video, which
  is the expensive version and **my fault for not making the cheap one explicit**
  — the version meant is ~300 words and a GIF on the itch page you are building
  anyway, monthly, drafted by me from the commit history, about twenty minutes of
  your time per post. Offered, not pushed; the plan works without it.
- **Budget plan is now near-free.** Only unavoidable cost is the $100 Steam fee.
  Added a **DIY capsule brief** — wordmark, one line-art silhouette from
  `icon_studio.gd`, one amber accent, designed at 462×174 first and crop upward.
  This game can carry DIY capsules better than most because the identity is
  already strict and already generated. Spend trigger recorded: **first money
  goes to the score, not the art** — the trailer is wordless so audio carries it
  alone, and `darkdrone` already proves the register.
- **AI premise leaned into.** `Artificial Intelligence` added at tag #6. Added §7,
  prepared answers — because a game about agentic AI built with AI agents is a
  story someone writes whether or not you raise it, Valve requires a disclosure
  anyway, and the honest split here is favourable: art and audio are licensed
  packs, AI is in code and docs. **That split needs the human's confirmation — I
  cannot verify every asset's provenance by reading the repo.**

**Gates.** `bash tools/check.sh --changed`: **PASS**. Markdown only, so it means
nothing broke rather than anything was verified. `test.sh` / `smoke.sh` not run —
nothing touched that they cover.

**Where I was wrong.** I proposed a devlog without ever saying what it cost, and
the human reasonably priced the most expensive interpretation and declined it.
That is a failure of the proposal, not the decision. Corrected in `PLAN.md` §2
with an actual time estimate and an offer to draft the posts.

**Needs the human.**

1. **Confirm the asset provenance split** — that no art or audio in the repo is
   AI-generated. The prepared answer in `PLAN.md` §7 rests on it and it goes on a
   public store page.
2. **Check the DS-Digital licence.** New this pass and it is the one I missed
   first time. It is the game's entire visual voice — HUD, capsules, screenshots,
   trailer — and that class of font is commonly free for personal use only. If it
   does not clear commercially, the substitute has to be chosen *before* anything
   is built on it.
3. **The sound-pack licences**, now a hard blocker rather than a nicety.
4. Still open from earlier passes: the salvage question, `config/name="Roboto"`,
   whether rain is wanted, and the GDD §7 recruitment row.

**Blocked / next.** Unchanged and deliberate: nothing public until Gate B, and
now nothing public until April 2027 by choice. The next thing marketing actually
produces is the **DIY capsule set and the screenshot pass**, both of which wait on
Gate B and on the capture tool (ask #4). If the human takes the devlog offer, four
drafts from the commit history is the cheapest useful thing I can do next.

## 2026-09-28 (second pass) — the frame was wrong; refit on "you are a gun too"

**Landed.** The human corrected three things and one of them was structural.

- **`POSITIONING.md` — rewritten, not patched.** The GDD pillar *you are not the
  gun, you are the commander* is retired from all outward copy. The human's read:
  the player is an agent-AI taking compute from other AIs and is therefore a
  weapon itself. The replacement is two lines splitting one failed job — **"Something
  points you. You point them."** for theme, and "the rifle in your hands is not the
  point" for expectation-setting. The bigger win is that **compute is the spine**:
  compute buys seats, seats are how many robots you can field, so taking compute
  makes you *larger*. That is a motivation with no story attached, it is topical
  for free in 2026, and it makes the attachment thematic — the squad is the only
  thing in the chain the player ever chose. Old draft's errors listed at the
  bottom of the file rather than deleted.
- **`PITCH.md` — rewritten at all three lengths.** New lead: "A first-person
  squad-command shooter: you are an agent taking compute from other AIs, and
  compute is how many robots you can be at once." Steam short description redrafted
  to 296 characters. The recruitment fallback is deleted — see below.
- **`PLAN.md` — new, and the main deliverable this pass.** The human markets for a
  living and asked for specifics, not fundamentals. Next Fest calendar with real
  dates and a recommendation; Steam tag order as a strategic choice; named
  creators and outlets with fit and risk; budget ranges; dependency-ordered asset
  build; three draft posts.
- **`CLAIMS.md`** — ASK #1 resolved, three new SAY IT rows, ASK #3 expanded (see
  below), and a fifth distinctive claim the brief did not have.
- **`DISPATCH.md`** — ask #1 rewritten from a question into a GDD correction; the
  screenshot list rebuilt one-shot-per-locale.
- **`RUNWAY.md`** — note at the top pointing at PLAN.md, and the calendar anchored
  to the June 2027 Fest.

**Gates.** `bash tools/check.sh --changed`: **PASS**. Markdown only again, so it
means nothing was broken rather than anything was verified. `test.sh` / `smoke.sh`
not run — nothing touched that they cover.

**Where I was wrong.** Four things, all from the first pass this same day:

1. **"You are not the gun" as the headline.** Thematically false and the human
   caught it. You are an agent handed objectives; you are a weapon too. The line
   was trying to be a theme and an expectations-setter at once and was failing
   at the first.
2. **"A dead city", singular.** The campaign spans unlike places — arena, basin,
   coast road, three bridges, Mutaha, causeway. The plural is both correct and the
   better idea, and it is operational too: five screenshots from five places read
   as a big game, five from one map read as a demo.
3. **Under-read compute.** I filed it as an economy row. It is the spine of the
   whole positioning and it was in the build and in the tutorial the entire time.
4. **Recruitment.** I was right that GDD §7 is stale — the human confirmed the
   factory works — but I should note the cost: I spent a document's worth of
   hedging on a question one line of chat settled. Ask sooner.

**Also found, and it is worse than I first reported.** The pillar is untrue in
**two** independent directions, not one. Three of four squad orders lose 100% of
the time (GDD §8) **and** the board names a *"long-range-god problem"* — the
player can currently out-range the whole thing alone. So the honest description of
today's build is closer to "an FPS with a squad you get attached to" than to "a
command game". That is why the copy says "the rifle is not the point" rather than
"aiming is not how you win": the second is the sentence you want and it becomes
true when those two close. It is the strongest argument yet for the runway being
gated rather than dated.

**Needs the human.** Four questions asked in chat this session — launch model,
audience priority, build-in-public vs go-dark, and budget. The plan in `PLAN.md`
assumes: free demo into a paid Steam release, tactics audience first,
build-in-public, ~$1,000. **Every one of those is a guess and three of them change
the plan materially.** Carried over and still open: the salvage question (ASK #2),
`config/name="Roboto"`, the sound-pack licences, the AI content disclosure, and
whether rain is wanted.

**Blocked / next.** Unchanged and deliberate: nothing until Gate B. The single
dated item now on the calendar is **Steam Next Fest registration, 25 April 2027**,
for the 14–21 June 2027 Fest — October 2026's has closed and February 2027's needs
a demo by 10 January, which I do not believe in. Everything else works backwards
from that. Sourced in `PLAN.md` §1 and worth re-checking against Valve directly
before anything is planned around it.

## 2026-09-28 — the runway: when to market, itch, TikTok, Steam

**Landed.** Five new files, all under `docs/marketing/`. Nothing else touched.

- `RUNWAY.md` — the four answers. **Recommendation: zero marketing before
  2026-10-08**, with three named gates rather than dates. Gate A a build that
  runs elsewhere → a *private* itch page as the M2 delivery mechanism. Gate B
  one mission judged fun and squad orders not losing 0/0/0 → public capture and
  the devlog, where marketing actually starts. Gate C a ladder plus a clean
  first run → the Steam page, not before. Then itch assets and page structure
  concretely (630×500 cover, the autoplaying GIF as the real conversion lever,
  eight-section scroll, free not paid); an honest no on TikTok as a primary
  channel with the four clips that *would* work and the tone conflict stated;
  and Steam in full — $100 Direct fee, the tax interview and the ITIN trap, the
  30-day hold, page review with two bounces budgeted, the ten-asset capsule set
  with sizes, and seven things found out late ranked by damage.
- `CLAIMS.md` — the ledger every future session should read before writing a
  word. SAY IT / HOLD / ASK.
- `PITCH.md` — one line, one paragraph, one page, plus a 277-character Steam
  short description. Built only on SAY IT mechanics; no Argus, no Algie, no plot.
- `POSITIONING.md` — the argument that the vagueness is a strength, its costs,
  six discipline rules, and worked samples: store blurb, a wordless 90-second
  trailer beat sheet, briefing copy, the memorised answer to "what's the story?".
- `DISPATCH.md` — six drafted asks, draft-only as required.

**Gates.** `bash tools/check.sh --changed`: **PASS** (see the run note below —
only Markdown changed, so this is a weak signal, and I am saying so rather than
presenting it as coverage). `test.sh` and `smoke.sh`: **not run.** I touched no
script, resource, scene or anything that loads at startup, so neither has
anything to say about this session. Not skipped for convenience.

**Needs the human.** Six items, all drafted in `docs/marketing/DISPATCH.md`.
Ranked:

1. **Can the player buy a new robot?** GDD §7 says recruitment is "not built".
   The build disagrees: `campaign_state.gd:624` defines `recruit()`,
   `factory_page.gd:240` calls it, FACTORY is a real tab, and
   `lesson_prompts.gd:36` teaches it. **This gates the pitch at all three
   lengths** — a fallback wording is written if the answer is no.
2. **The pillar may not be true yet.** Three of four squad orders lose 100% of
   the time (GDD §8). Every line of copy rests on "you are not the gun, you are
   the commander," and one of the four commands works. Already on YOUR DESK;
   flagged here because it does not look like a marketing problem from the board
   and it is marketing's single largest exposure.
3. **`config/name="Roboto"`.** Window title, `.exe` basename, and what the Steam
   overlay reads. The 2026-10-08 build says Roboto while the title screen says
   DATA CENTER WARS 2109. Shared file, so not mine — five-minute fix.
4. **No sound pack in the repo has a licence.** All twelve folders under
   `sounds/sfx/` carry no licence or credit file, `darkdrone` (the title music)
   included. `textures/` has two. A `CREDITS.md` is an hour now and a week in six
   months, and it is a hard gate on any paid release.
5. **The AI content disclosure.** Valve requires it, it appears publicly on the
   store page, and this game has four AI lanes. A decision to make in writing
   long before there is a page.
6. **Is salvage the economy, or just where money comes from?** One
   undifferentiated `earned` pool, free resupply. I wrote the narrow claim.

**Two things I should say out loud.**

- **There is no rain in the game.** The most evocative line in my own brief —
  "rain falls on a planet bereft of the people that constructed it" — describes
  something that does not exist. I grepped `Env/`, `Character/`, `Managers/` and
  `Campaign/` for rain, precipitation, weather and fog; the only matches are the
  letters inside "terrain". Not a criticism, but it means no rain in any capture
  or key art, and if it is the tonal centre it is a board item rather than a
  brief line. Drafted as ask #5.
- **`check.sh` cannot verify anything in this session.** It parses scripts and
  loads resources. I changed five Markdown files. PASS here means "I broke
  nothing", not "this is right". Everything in `RUNWAY.md` §4 about Steam is
  recalled knowledge, not fetched — the shape of the process is stable but the
  individual figures should be re-checked against Valve's documentation before
  money moves. Said in the file too.

**Blocked / next.** Not blocked; deliberately idle. The recommendation is that
this lane does nothing until Gate B, and I would rather hold to that than
generate work. Three things I did not do, on purpose:

- **No shot list for the 2026-10-01 recording missions**, though the brief lists
  it as deliverable #2. You said those clips are yours and your friends do not
  need marketing. The board's MARKETING NOW line still reads "pitch + shot lists
  for the three recording missions" and the pitch half is done; the coordinator
  may want to retire the other half.
- **No devlog drafts.** They want Gate B footage and a real capture tool
  (ask #4), and writing them now would date them.
- **No capsule or cover art.** Needs a logo lockup that does not exist. It is the
  longest lead time on the Steam list — two to four weeks with revisions — and
  the one thing on it worth paying a person for.

When Gate B clears, the first move is the devlog, not the page.
