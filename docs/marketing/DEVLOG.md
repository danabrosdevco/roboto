# Devlogs — where to host, and what to make

Written 2026-10-13 by MARKETING, answering three things at once: where to host
devlogs, what is best with **no social reach of your own**, and what to do with
*"I like writing and could do VO over game clips."*

That last one changes the recommendation. It is read as a capability, not a
passing remark.

---

## 1. The reframe: with no reach, hosting is storage

This is the whole answer and everything else follows from it.

**A devlog on a platform where nobody follows you is a file on a shelf.** It is
not a channel. Your own site, your own newsletter, a fresh YouTube channel — all
of them are buckets with no tap. The writing is not the problem; the *room* is.

So the question is not "where do I host" but **"whose audience am I borrowing."**
Host wherever is free and permanent. Spend the effort on being read.

| | |
|---|---|
| **Hosting** (free, do not overthink) | itch devlogs for writing, YouTube for video |
| **Distribution** (where the effort goes) | **Reddit**, every time, plus TIGSource and Bluesky |

---

## 2. Hosting — decided, in one line each

**Writing: itch.io devlogs.** Zero setup, because it is part of the project page
you are already making. Posts appear on the game page, followers get notified,
there is a browsable `itch.io/devlogs` feed, and search engines index it. Nothing
else to build, nothing to pay for, no new account.

**Video: YouTube, unlisted or public.** Purely as a file host with a player that
embeds anywhere. **Do not expect a new channel to do anything on its own** — it
will not, for a long time. Its job is to hold the video so a Reddit post can
point at it.

**Later, free and worth having:** once the Steam page exists (Jan 2027 per
`docs/marketing/PLAN.md` §1), **Steam announcements** reach everyone who
wishlisted. That is the only owned channel on this list that will ever have real
reach, and it comes free with the page.

### What not to build, and why

| Option | Why not |
|---|---|
| Own site (GitHub/Cloudflare Pages) | Free and permanent, and nobody arrives at it. Infrastructure to maintain for zero reach. Revisit when there is an audience to send somewhere |
| Newsletter (Substack, Buttondown, Ghost) | Email is the best channel there is **once you have a list**. With no list it is an empty room you now have to furnish weekly |
| Medium / dev.to | Borrowed audience, but the wrong one — developers reading about development, not people who might play this |
| A Discord | Not before there are people to put in it. An empty server is worse than none |

---

## 3. Distribution — this is where the work goes

**Reddit is not a route to an audience. It is the audience.** A well-written
technical post on `r/godot` is read by thousands of people who have never heard
of you, costs nothing, and needs no following whatsoever. For someone starting
from zero it is the highest reach-per-hour available anywhere.

**Start with `r/godot`.** The craft in this project is genuinely good and that
community rewards craft over polish. Post *process*, never "check out my game".

Then `r/IndieDev` and `r/gamedev` for cadence, and **`r/DestroyMyGame`** once
there is a 30-second clip — brutal, specific, and free QA on whether a stranger
understands what they are looking at.

**TIGSource devlog thread** is the canonical long-form indie devlog home. Slow,
small, and it is where people who write about obscure games go looking. Start one
and post monthly, forever.

**Bluesky** for `#screenshotsaturday`. Low effort, compounds slowly, no reach
needed to start.

The audience-specific subs — `r/XCOM`, `r/BattleBrothers`, `r/RealTimeStrategy` —
stay parked until the trailer, and they want mod permission first. See
`docs/marketing/PLAN.md` §4.

---

## 4. The VO idea is the best card you have — with one rule

> *"i like writing and could do vo over gameclips"*

That is a better position than most solo devs are in, and it should be used.
Writing is the expensive part of a narrated devlog for most people; for you it is
the cheap part. The expensive part becomes editing, and editing can be crude.

### The rule that protects the tone

**The developer may narrate. The game never does.**

`docs/marketing/POSITIONING.md` has a hard rule — *no human voice, anywhere,
ever* — and it is about the game's voice, not yours. Process copy is allowed to
be plain and first-person in a way the game is not.

So: **VO over devlog clips, yes. VO on the trailer, never.** The trailer stays
wordless with the game's own drone, and its climax stays a repair rather than a
kill. That distinction erodes easily once a microphone is set up and you have
recorded six good takes, so it is written down here.

### The shape that costs least and works

**One piece of thinking, two formats.** Do not invent separate video ideas:

1. Write the post. ~500–800 words. This is the part you enjoy, and it is the
   artefact that works on its own.
2. Publish it: **itch devlog + `r/godot`**.
3. Read it over the footage. Three to five minutes, screen capture, no face, no
   b-roll, minimal cuts. **DaVinci Resolve is free** and you need about four of
   its features.
4. Put the video on YouTube and post *that* to Reddit a week later as a second
   bite — some subs take video posts, and the same idea reaches people who do not
   read.

One idea, two surfaces, no extra thinking. If step 3 ever feels like a chore,
drop it and keep writing — the post is the thing that works.

**Do not open with a video.** Write three posts first and see which one travels;
that tells you which one is worth narrating. Narrating the wrong one is four
hours spent on something nobody wanted to read either.

---

## 5. This reopens the go-dark decision

On 2026-09-28 the call was **go dark until a trailer**, and the stated reason was
that a devlog looked expensive — *"I'd need a website and YouTube and it's a
lot."*

Two things have changed. There is no website needed, and you like the writing.
So the cost that drove the decision is mostly not there.

**Naming the tension honestly:** a public devlog *is* visibility, so it is not
strictly compatible with going dark. But it does not spend the trailer moment —
a trailer is still a reveal to people who read a technical post about navmesh
baking six months earlier, and the two audiences barely overlap. What a devlog
buys is credibility and a small number of people who already know the name when
the trailer lands.

**My recommendation: run the devlog, keep the trailer dark.** Post about *how it
is made*, never about *what it will be*. No feature reveals, no "coming soon", no
roadmap. The trailer stays the first time anyone sees the game presented as a
game.

Your call, and it is a change to a decision you already made deliberately — so
worth making on purpose rather than drifting into.

---

## 6. The backlog — twelve posts already in your git history

You do not need ideas. You need to notice that the work already happened. Pulled
from `git log`, best first:

| # | Post | Why it travels |
|---|---|---|
| 1 | **"We measured the optimisation and it bought nothing"** — `a1192bc9`, `ee016e49`: the collision backfill, benchmarked and rejected, with the bench tool committed | **Almost nobody publishes the optimisation that failed.** A measured negative result is rare, honest and extremely shareable. Pull real numbers out of `tools/bench_block_collision.gd` before writing |
| 2 | **"Our distance culling worked fine. Squad orders were undoing it every frame."** | 141 → 22 active robots, 25.0 → 7.4 ms. Full draft in `docs/marketing/PLAN.md` §6 |
| 3 | **"What it actually takes to make a frame real"** — `82729253`, `099fd4dc`, `c3c77220`: eight chassis from model to playable | The title is already written and it is the question every solo dev wants answered |
| 4 | **"The Warden is cut"** — `c7178bf7` | Killing something you built. Pairs with the anatomical body. Devlogs about deletion always outperform devlogs about addition |
| 5 | **"One collision change, nine navmesh re-bakes"** — `45cadf7d` and the nine commits after it | A clean illustration of how a low-level change ripples. Very visual with before/after |
| 6 | **"Our test suite was failing silently"** — `0d71d345`: a suite that fails now says so in its exit code | Universally relatable and slightly alarming. Strong `r/gamedev` post |
| 7 | **"We built a human-shaped robot and threw it away"** | The capsule stayed. Visual, short, about taste rather than code |
| 8 | **"One `--force` destroyed a hand-edited map"** | A real disaster with a rule that came out of it. Honest-failure posts travel further than successes |
| 9 | **"Three of our four squad orders lose 100% of the time"** — GDD §8 | A headless harness finding the game's own commanding layer broken. **The most shareable single thing this project owns.** Needs the fix landed first, or it is a bug report rather than a story |
| 10 | **"A gait that answers for direction, not distance"** — the Walker's backpedal running the stride in reverse | Genuinely novel, and a gif sells it instantly |
| 11 | **"An operations table the projection can actually stand on"** — `c2400afc`, `0a5672af` | Design-constraint storytelling: the table is 7.0 × 3.0 because that is the widest the rail car allows |
| 12 | **"Rivers that the squad cannot wade"** | Making terrain refuse a route, and proving it with a path test rather than by looking at it |

### Which three to write first

**1, 6, 4** — in that order. All three are about something going wrong or being
thrown away, which is what performs; none needs a feature finished; and none
requires the game to be judged fun first. They are publishable the week the
export settles.

---

## 7. The whole answer, in five lines

1. Host the writing on **itch devlogs**. Free, already there, nothing to build.
2. Host video on **YouTube**, purely as a player. Expect nothing from the channel.
3. Spend all the effort on **Reddit, starting with `r/godot`**. That is the
   audience, not a route to one.
4. **Write first, narrate second** — and only the posts that already travelled.
5. **You narrate; the game never does.** The trailer stays wordless.
