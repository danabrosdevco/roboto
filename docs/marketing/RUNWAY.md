# Runway — when to market, and where

Written 2026-09-28 by MARKETING, against `docs/BOARD.md` (M1 2026-10-01,
M2 2026-10-08) and `docs/GDD.md`.

Four questions were asked. The answers are below in order. Where I checked
something in the build rather than taking a document's word for it, I say so.

> **Note added 2026-09-28.** The human markets professionally and does not need
> the mechanics of marketing explained. Several passages below do explain them —
> the wishlist argument, why TikTok rewards a fast hook, how store-page review
> works. Those are kept for the next agent who reads this lane cold, not for the
> human. **The specifics are in `docs/marketing/PLAN.md`:** the Next Fest
> calendar with real dates, Steam tag order, named creators and outlets, budget
> ranges and draft posts. Read that file first; this one for the gate argument,
> which is unchanged and which the reframe below only strengthened.

---

## 1. When should marketing start at all?

**Not yet. Zero marketing between now and 2026-10-08.** The triggers are below,
and they are gates, not dates.

### Why not yet

Four things on the board make marketing premature, and all four are already
someone's problem:

1. **The export has never been proven** — board risk #1. You cannot market a
   game that has never run on another machine. itch, Steam, a demo, Next Fest —
   every one of them is downstream of this single unretired unknown.
2. **Nobody has said whether any mission is fun** — board risk #4, and item #1
   on YOUR DESK. Marketing a game whose designer has not yet judged it fun is
   marketing a hypothesis.
3. **Three of four squad orders lose 100% of the time** (GDD §8). This is the
   one that should stop this lane cold. The pillar is *you are not the gun, you
   are the commander*. Every line of copy I would write rests on that sentence.
   If three of the four verbs the pillar is made of lose every fight, the copy
   is a claim a playtester disproves in ten minutes.
4. **The three record blockers** — toy-sized guns, droning spotters, duplicate
   icons. The board already reframed these correctly: they are *things a camera
   sees*. They gate video, and video gates everything else.

Opening a marketing workstream this week takes hours away from risks #1 and #2,
which are the two things that can actually cost the milestone.

### The gates

**Gate A — "it exists elsewhere."** A build runs on a machine that is not this
one, from an export, with no editor and no source.
→ *Unlocks:* a private itch page as the delivery mechanism for the M2 playtest.
That is logistics, not marketing, and it is the only page-shaped thing worth
doing in the next two weeks.

**Gate B — "it is fun, and commanding works."** You have played coast road,
basin and Mutaha and named one of them fun. The squad-order win rates are not
100/0/0/0.
→ *Unlocks:* public capture. Screenshots, the first clip, the first devlog.
**This is where marketing genuinely starts.**

**Gate C — "there is a ladder."** Three or four missions in an order that
teaches, and a clean first run on an empty `user://` profile.
→ *Unlocks:* the Steam page. Not before. A Steam page with nothing behind it
spends the one launch you get.

### Calendar, if the board's dates hold

| When | Marketing does |
|---|---|
| now → 2026-10-08 | **nothing.** Both build lanes are on Mutaha and the export. |
| mid-Oct, after M2 feedback | Gate B is plausible. **Start the devlog.** |
| Nov–Dec 2026 | itch page public, free. Five screenshots (one per locale), one GIF. Steamworks onboarding begun — it is waiting-time, not work. |
| **early Feb 2027** | **Steam page public**, ~4.5 months of wishlist runway ahead of the Fest. |
| **14–21 June 2027** | **Steam Next Fest**, with a demo. Registration closes **25 April 2027**. |

Dated properly in `docs/marketing/PLAN.md` §1, which works backwards from the
Fest because the Fest is the only hard deadline in the whole plan. The short
version: **October 2026's Fest is already closed, February 2027 is possible and
too tight, June 2027 is the one to take** — Next Fest pays out against the
wishlists you arrive with, so entering it cold spends the one shot for nothing.

### The one thing to start now, because it decays

**Keep the footage.** Every session, every recording, even the broken ones. Not
for marketing — for the devlog and the trailer you cut in three months. Mutaha is
mid-rework; nobody can go back and shoot the old one. The before-and-after of a
map rebuild is the most reliable devlog post there is, and right now it is free,
and in a week it is gone.

### And one five-minute fix

`project.godot` line 13 is `config/name="Roboto"`. That string is the window
title, the export basename, and what the Steam overlay picks up. Any build handed
to a friend on 2026-10-08 says "Roboto" in the title bar and on the `.exe` while
the title screen says DATA CENTER WARS 2109. `project.godot` is shared, so this
is not mine to edit — the ask is drafted in `docs/marketing/DISPATCH.md`.

---

## 2. itch.io — when, and what

itch is the right first storefront for this game, and it is close to free to be
wrong on. It is also where the answer to "somewhere for the playtest build to
live" already is.

### When

- **Now, private.** itch pages can be *restricted* — the page exists, is not
  indexed, and opens only for people with the link or a download key. Set one up
  as the M2 delivery mechanism. It needs a title and a zip. Nothing else. That
  retires a board question for about twenty minutes of work.
- **Public after Gate B.** The bar: five screenshots you are not embarrassed by,
  and a build that runs elsewhere. Mid-to-late October if the dates hold.

### Assets, concretely

| Asset | Spec | Notes |
|---|---|---|
| **Cover image** | **630×500** | The only image in browse and search. Displayed at 315×250, so it must be legible at 315×250 — title lockup plus one silhouette. **Not a wide tactical screenshot;** it becomes mud. |
| **Animated GIF** | ~800 px wide, 6–8 s, loops | Goes in the screenshot gallery, where itch autoplays it. **The single biggest conversion lever on the platform.** One subject: a robot goes down, a Mechanic walks over, it stands back up. |
| **Screenshots** | 5 minimum, 1920×1080 | Shot list in `docs/marketing/DISPATCH.md`. |
| Banner / background | ~960×400 | Optional, low priority. |
| Trailer | — | Not needed here. A YouTube embed is fine and the GIF does more work. |

### Page structure

itch pages are one long scroll, and the order *is* the design:

1. **Cover, title, one-line pitch.** The tagline shows in browse and in every
   embed, so it is the most-reused sentence you will write.
2. **The GIF.** Before any prose. It answers "what is this" faster than a
   paragraph can.
3. **The paragraph** — from `docs/marketing/PITCH.md`.
4. **Four bullets**, in the game's own nouns: chassis, seats, salvage, compute,
   signal.
5. **Screenshots.**
6. **"What is in this build"** — how many missions, how long, what is absent.
   The highest-trust block on an itch page and the one devs skip.
7. **Known issues.** Yes, really. On itch this reads as competence.
8. **Devlog links.**

### Settings that matter

- Classification **Game**, kind **Downloadable**, release status **In
  development**, platform **Windows** only — that is what exists.
- **Pricing: free, or name-your-own-price with a $0 minimum. Do not charge for
  the playtest.** A price tag turns a feedback request into a purchase, and you
  get customer complaints instead of playtest notes.
- Revenue share: itch's default is 10% and you can set it to anything. Moot
  while free.
- Tags are the discovery surface. Relevant and under-supplied: `tactical`,
  `squad-based`, `real-time-tactics`, `fps`, `singleplayer`, `robots`,
  `post-apocalyptic`, `godot`.
- Payout and tax setup is only needed if you ever charge. Skip it now.

### The actual reason to be on itch: devlogs

They are indexed, they have their own feed, they cost nothing but writing, and —
this is the point — **they work before the game is good.** A devlog is about the
work, not the product, so it is the one channel that opens before Gate B.

This project has a surplus of the right material, and none of it needs the game
to be finished:

- The anatomical drone body that was built and rejected, next to the capsule that
  stayed.
- One `--force` over a folder destroying a hand-edited map, and the rule that
  came out of it.
- "Three of four squad orders lose 100% of the time" — a headless lab finding
  that the game's own commanding layer is broken. **That post travels.**
- Distance culling being silently undone every frame by squad orders: 141 → 22
  live robots, 25.0 → 7.4 ms.

Process honesty is the one marketing asset this project already holds in
surplus. It is also the only one that does not require Gate B.

---

## 3. TikTok — honest answer

**Partly. Not as a primary channel. And yes — what would perform there is in
direct tension with the tone.**

### Why it is a poor fit, specifically

- **This is a wide game and TikTok is a narrow window.** A squad spread across
  thirty metres, an objective two hundred out. What makes a squad-command shot
  legible is the spatial relationship between four robots, and that is precisely
  what a 9:16 crop destroys.
- **The HUD is the game's voice, and it dies vertical.** DS-Digital green
  phosphor, ASCII-only, segmented health. Beautiful at 1440p, mud on a phone at
  9:16.
- **First-person shooter footage is the most over-supplied category on the
  platform.** A rifle and some amber enemies reads as "generic indie shooter" in
  about a second and a half, and a second and a half is the whole budget.
- **Mournful does not survive the algorithm.** The format rewards something
  resolving inside three to eight seconds. Atmosphere is the opposite of a
  resolving beat. You cannot hook on sadness at speed — only on surprise.

### What would actually perform, best first

1. **"They're just capsules."** The most arresting visual fact about this game,
   and nobody else has it. A slow push onto a squad in formation, then the reveal
   that they are pill shapes carrying rifles. It works because it is a visual
   joke that is not a joke — it is unsettling, which is on-tone.
2. **The Mechanic standing a downed robot back up.** The most legible good thing
   in the build. A resurrection beat that resolves in four seconds and makes a
   stranger feel something about a capsule. **If you only ever make one clip,
   make this one.**
3. **Flanking the Walker.** Its turret traverses slowly; go round the side and
   both guns point the wrong way. A counter-play you can *see* — the clip that
   teaches that commanding is the game rather than aiming.
4. **The debrief card.** A robot with a callsign comes home, earns a rank, and is
   a different object next mission. Numbers going up is reliably watchable, and
   persistence is the hook underneath it.

### The conflict, stated plainly

1 and 2 are on-tone. 3 and 4 are neutral. **Everything that would perform
*better* than these is off-tone** — kill compilations, ragdoll failures, sped-up
chaos over a trending sound, "watch this robot eat it." The moment TikTok
performance drives the edit you have made a cynical game out of a sad one, and
the brief forbids being cynical about the robots.

### Recommendation

**Do not build a TikTok strategy. Build a clip strategy and post the clips where
they fit.** The same four clips work on YouTube Shorts, Reddit, Bluesky and an
itch devlog — and three of those four are *better* fits for a slow, serious
tactics game than TikTok is.

Reddit especially. `r/godot` will reward this project on craft alone; `r/IndieDev`
and the tactics-adjacent subs are places where "squad-command FPS" is a starved
niche rather than an over-supplied one. On TikTok you compete with every shooter
ever posted. On a tactics sub you compete with almost nobody.

If you do post to TikTok, one rule protects the tone: **no trending audio, no
text-overlay jokes, no sped-up footage.** Use the game's own drone and the game's
own silence. It will perform worse and it will still be the game.

---

## 4. Steam — what is required, and how you actually do it

Figures below are current to my knowledge and worth re-checking against Valve's
own documentation before you spend money. The *shape* of the process is stable;
individual numbers move.

### Money and paperwork

- **Steam Direct fee: $100 USD per app.** Recoupable against your first $1,000
  of adjusted gross revenue. Per app — a second game is another $100.
- Before you can pay it you complete **Steamworks onboarding**: identity (as an
  individual or a company), a bank account, and a **tax interview**. US filers do
  a W-9. Non-US individuals do a W-8BEN and need a foreign TIN or an ITIN —
  **this is the step that surprises people**, and without that number already in
  hand it can take weeks.
- **There is a 30-day hold.** After your bank and tax details are verified, Valve
  makes you wait thirty days before you can release your first product. It is not
  negotiable, and people find out about it in week three of a four-week plan.
- Revenue pays out roughly thirty days after the end of the month it was earned,
  above a minimum threshold.

### Store page gates

- **Valve reviews your page before it goes public.** Budget three to five
  business days, and budget two bounces — pages get kicked back for trivial asset
  problems and each one is another round trip.
- **A Coming Soon page must be live at least two weeks before your release
  date.** That is the floor, not the plan.
- **The real number is three months or more.** Wishlists only accumulate while
  the page is public, and launch visibility on Steam is substantially a function
  of wishlist count. Two weeks collects nothing. The universal regret of
  first-time Steam devs is the same one: *the page went up too late.*

### The assets — the part nobody budgets for

Steam wants a *set*, and every item is a different aspect ratio, so you cannot
crop your way out of it:

| Asset | Size | Appears |
|---|---|---|
| Header capsule | 920×430 | everywhere; the workhorse |
| Small capsule | 462×174 | search results and lists — **must read when tiny** |
| Main capsule | 1232×706 | front-page features |
| Vertical capsule | 748×896 | upcoming releases, features |
| Page background | 1438×810 | optional |
| Library capsule | 600×900 | the player's library |
| Library header | 920×430 | library |
| Library hero | 3840×1240 | library page banner |
| Library logo | 1280×720, transparent | overlays the hero |
| Client icon | 32×32 | taskbar, friends list |

Plus **five screenshots minimum** (1920×1080; Valve wants actual gameplay, not
key art with marketing text baked in), **at least one trailer** (1080p or better,
opening on gameplay rather than logos), a **short description capped at 300
characters** — the one piece of copy that follows the game everywhere — the long
"About This Game" in BBCode, **up to 20 tags** (the first few drive the
recommendation algorithm and matter more than the description does), genres,
system requirements, and a content survey.

### The parts found out about late, ranked by how much they hurt

1. **Capsule art is graphic design, not a screenshot, and this game has none.**
   Every capsule has to carry the title legibly at 462×174. Nothing in the repo
   does that job. What you *do* have is unusually good raw material — a dark
   title screen, line art rendered from the real models through
   `Character/hud/icons/icon_studio.gd`, and a disciplined four-colour faction
   palette. Somebody still has to draw a logo lockup and eight crops. If that is
   not you, it is the one thing on this list worth paying for, and it is a two-
   to four-week lead time with revisions.
2. **The AI content disclosure.** Valve requires you to declare AI-generated
   content — art, audio, code — in a survey whose answers then appear publicly on
   your store page. This game is built by four AI lanes. Whatever the right answer
   is, **decide it deliberately and early.** It is the item most likely to
   blindside you here, and correcting it after launch is a policy problem rather
   than a copy problem.
3. **Asset licensing, and I checked this one.** `textures/` carries two licence
   documents — `PSX_Textures/Game Asset License Agreement.pdf` and
   `Set4All/License.txt`. **All twelve folders under `sounds/sfx/` carry no
   licence or credit file at all**, including `free cinematic sfx` (freesound
   material, whose licences run from CC0 through CC-BY-with-mandatory-attribution
   to non-commercial), `psx ui sfx`, `Robot Droid Voices`, `superior soundfx`,
   and `darkdrone` — which is the title music. Free to download is not free to
   sell, and an uncredited CC-BY pack is a real claim. **Start a `CREDITS.md` now,
   while you still remember where things came from.** An hour today; a week in six
   months.
4. **The build is named "Roboto."** See §1. Separately: "Roboto" is Google's
   typeface and a crowded search term. "Data Center Wars 2109" is searchable and
   unclaimed — the nothingness you like is also good SEO.
5. **You need a demo, and demos have their own rules.** A Steam demo gets its own
   store page now. **Steam Next Fest** requires one, runs roughly three times a
   year, and **you may enter only once per game, pre-launch.** It is the largest
   free visibility event available to an unknown indie, and the registration
   deadline falls well before the Fest itself. Do not burn it on a weak demo, and
   do not miss it by not knowing it exists.
6. **Review keys and outreach.** Not urgent. Worth knowing that curator and
   streamer admin is weeks of work, landing exactly when you are fixing launch
   bugs.
7. **A build that ships.** Board risk #1 again, plus Steam's own layer — depots,
   launch options, upload through SteamPipe, and a Valve review of the actual
   build before launch.

### How you actually do it, in order

1. Prove the export. Already GAMEPLAY's, for M2.
2. Fix `config/name`. Five minutes.
3. Start `CREDITS.md`: every asset pack, its source, its licence.
4. Decide the AI disclosure answer. A conversation, not a task.
5. Do the tax and banking onboarding **before** you need it — the 30-day hold and
   the TIN problem are both waiting-time, not work. You do not have to pay the
   $100 until you want the page.
6. Commission or design the capsule set. Longest lead time on the list.
7. Pay the $100, build the page, submit for review, expect two bounces.
8. Page public **three months or more** before any date you would name.
9. Next Fest, with a demo you are proud of, timed on purpose. Once.

**Earliest defensible Steam page date on current evidence:** after a demo a
stranger finishes alone — `docs/GAMEPLAN.md` sizes that at 25–35 minutes. The
board does not have that milestone yet. Which is also the honest answer to
question 1.
