# Video devlogs — the production workflow

Written 2026-10-13 by MARKETING, answering: how to structure devlog video, given
Ludeon as the reference, YouTube Shorts as the preferred medium, no prior video
experience, and a willingness to write and narrate.

---

## 1. First, the contradiction — because it decides everything else

**Ludeon and Shorts are opposite formats and you have named both.**

What is admired about Ludeon's devlogs — and this is the quality rather than any
specific claim about their archive, which is worth checking yourself — is that
they are **long, calm, unhurried and reasoning-led**. They explain *why* a system
is the way it is. They respect the reader's patience. Nothing is hyped. The
pleasure is watching someone think in public.

Shorts are the reverse: sixty seconds, hook in the first two, one idea, cut hard,
resolve fast. A Short cannot hold a design argument. It can hold exactly one
surprising fact.

**You do not have to choose. You have to not blend them.** Blended, you get a
written post that reads like an advert and a video that drags. Kept separate,
each does its job:

| Output | Format | Job |
|---|---|---|
| **The written post** | Long, calm, Ludeon-shaped | The real artefact. Reasoning, numbers, the argument. Lives on itch + `r/godot` |
| **The Short** | 45–60 s, vertical, one fact | **The trailer for the post.** Its only job is to make someone want the long version |
| *(optional, later)* | 5–10 min narrated | Only once you enjoy making them |

**The post is the thing. The Short is an advert for it.** If that stays true, you
never have to make a Short that oversells, and the tone survives.

---

## 2. Shorts do work here — but for devlog content, not gameplay

I argued against short-form for this game in `docs/marketing/RUNWAY.md` §3 and
that argument stands **for gameplay footage**: a wide tactical game crops badly,
the HUD dies at phone size, and first-person shooter footage is the most
over-supplied category there is.

**Devlog Shorts are a different thing entirely**, and the distinction is worth
holding onto:

- A gameplay Short says *"look how good this game is"*, competes with every
  shooter ever posted, and loses.
- A devlog Short says *"here is a surprising thing that happened while making
  something"*, competes with almost nothing, and wins on the fact rather than the
  fidelity.

"Our distance culling was being undone every frame by the squad orders" is
interesting whether or not the game looks good. That is the whole reason this
works.

### The layout that solves the wide-game problem

**Do not crop 16:9 gameplay to 9:16.** You lose the spatial relationships that
make a squad shot legible, which is exactly what this game is made of.

**Letterbox instead.** Put the 16:9 footage in a band across the middle of a
1080×1920 canvas, on the game's near-black (`#080C0A`), and use the space above
and below:

```
┌─────────────────┐
│  TITLE / HOOK   │  ← the claim, in text, legible at a glance
├─────────────────┤
│                 │
│  16:9 footage   │  ← uncropped, nothing lost
│                 │
├─────────────────┤
│   subtitles     │  ← burned in, large
└─────────────────┘
```

Standard, effective, and it means one capture serves both the Short and the long
version. It also gives the title somewhere to live, which matters because most
people watch muted first.

**Capture at 1920×1080 minimum.** The current screenshot set is 1152×648, which
would letterbox into a soft band. Same fix as the reshoot note in
`docs/marketing/SHOT_BRIEF.md`.

---

## 3. The toolchain — all free, all beginner-usable

| Job | Tool | Note |
|---|---|---|
| **Screen capture** | **OBS Studio** | Free, the standard. Set canvas 1920×1080, record MP4. One scene, one source, one hotkey |
| **Voice** | Any USB mic; a phone in a coat-filled wardrobe genuinely beats a bad desk mic | Record the VO **separately** from the footage, not over it |
| **Audio cleanup** | **Audacity** — free. Noise reduction, normalise. Two menu items | Takes five minutes once you have done it once |
| **Edit + captions** | **CapCut** (free, built for vertical, excellent auto-captions, easiest start) or **DaVinci Resolve** (free, far more capable, steeper) | **Start with CapCut.** Move to Resolve if and when it gets limiting. CapCut's terms and data handling are worth a look before you commit to it |
| **Script, captions, copy** | **Claude** | See below |

**One thing to know about captions:** because you will be *reading a written
script*, auto-captions come out near-perfect — speech recognition fails on
improvised speech, not on clear reading. So you do not need to type subtitles.
Generate them, skim for proper nouns (*Mutaha*, *Godot*, *navmesh*, *Reclaimer*),
fix those four, done.

---

## 4. Where Claude fits, honestly

**I can:** pull the material out of `git log`, draft the written post, convert it
into a timed two-column shooting script, write the exact VO lines, write the
on-screen text, write an `.srt` subtitle file from the script, and write the
YouTube title, description, tags and the Reddit post that points at the video.

**I cannot:** capture footage, record audio, edit video, or generate footage.
Everything in the middle of the pipeline is yours.

So the division is: **I write, you shoot and speak, the editor assembles.**

---

## 5. The loop

Once per post. Steps 2 and 8 are mine.

1. **Something happens in the repo** — a bug, a cut feature, a measurement. You
   do not look for these; they accumulate. Twelve are already queued in
   `docs/marketing/DEVLOG.md` §6.
2. **I draft the written post** from the commits, and then a **shooting script**:
   VO line in one column, what is on screen in the other, with a running clock.
3. **You capture** the footage the script's right-hand column names. Nothing
   else — the script exists so you are not fishing through recordings later.
4. **You record the VO**, reading the script. One take per section; stop and
   restart rather than pushing through a fluff.
5. **Assemble**: footage on the timeline, VO under it, auto-captions, title card.
6. **Export twice** — 1080×1920 for the Short, 1920×1080 for the long cut if you
   want one.
7. **Publish the post** (itch devlog + `r/godot`) and the Short (YouTube).
8. **I write** the title, description, tags and the Reddit post.

**Publish the written post first and the Short a few days later.** The Short
points at the post; the post should already exist when it does.

---

## 6. How to structure a Short — the template

Sixty seconds, five beats. No intro, no "hey guys", no outro, no asking for
subscribers.

| t | Beat | Rule |
|---|---|---|
| **0:00–0:03** | **The claim**, stated flat | The whole hook. Say the surprising thing immediately — do not build to it. On screen as text, because most people watch muted |
| 0:03–0:12 | **What we expected** | The setup. One sentence of context, no more |
| 0:12–0:35 | **What actually happened** | The turn. This is the content |
| 0:35–0:50 | **The number, or the fix** | Something concrete. A measurement lands harder than an adjective |
| 0:50–0:58 | **The line that sits** | One sentence. Often what you would do differently. Then stop |

**Tone rules**, consistent with `docs/marketing/POSITIONING.md`:

- **Flat and dry.** The facts are interesting; the delivery must not oversell
  them. Hype voice on a game this bleak reads as a lie.
- **You narrate, the game never does.** VO is allowed on devlogs and **never on
  the trailer**. That line erodes once a microphone is set up, so it is written
  in two places.
- **Never cynical about the robots.** Even in a bug post, they are not a joke.
- No trending audio. The game's own drone, or silence.

---

## 7. A worked script — the one you could shoot this week

Post #2 from the backlog. I have real numbers for this one, which is why it is
the worked example rather than #1 (that one needs figures pulled out of
`tools/bench_block_collision.gd`, which I have not opened).

**Title:** *Our optimisation worked. The game was undoing it every frame.*

| t | VO (read this) | On screen |
|---|---|---|
| 0:00 | "We wrote an optimisation. It worked. The game undid it every single frame." | Text card over a wide shot of Mutaha with the squad in it |
| 0:06 | "Robots far from any enemy drop to a cheap tick. On our biggest map that should take a hundred and forty-one active robots down to about twenty." | Mutaha from above, many robots visible |
| 0:16 | "It was taking it to a hundred and forty-one." | Debug overlay showing the count unchanged |
| 0:21 | "The culling was fine. The problem was somewhere else." | Code: the culling function |
| 0:26 | "Issuing a squad order wakes every member of the squad. And squad orders re-issue continuously." | The order being given in-game, squad moving |
| 0:34 | "So every robot we culled was being woken, on the very next frame, by the order it was already following." | Slow push on a single robot |
| 0:42 | "Five separate code paths could do it. We had guarded three." | Code: the five call sites |
| 0:48 | "A hundred and forty-one active robots down to twenty-two. Physics from twenty-five milliseconds to seven point four. From over budget to inside it — without touching the culling." | Before/after numbers, large |
| 0:56 | "There is still no regression test for this. A sixth path would undo it silently, and we would not notice." | Black, text only |

Nine lines, about sixty seconds read at a calm pace. **Footage needed:** four
clips and two code captures. That is one capture session.

Note the last line. Ending on the thing that is still wrong is the Ludeon move,
and it is what separates a devlog from an advert.

---

## 8. What this actually costs

Honestly, because the earlier estimate of "twenty minutes" was for a written post
and video is not that:

| | First one | Once practised |
|---|---|---|
| Script (mine) | — | — |
| Capture | 1 h | 20 min |
| VO recording | 1 h | 15 min |
| Edit, captions, export | 2–3 h | 30–45 min |
| **Total yours** | **4–5 h** | **~1.5 h** |

**The first one will be bad and will take all day. That is the correct outcome.**
Make three before judging whether the format is worth it.

**The written post stays worth it on its own.** If video turns out not to be
enjoyable, drop it and keep writing — the posts were always the artefact and the
Short was always the advert.

---

## 9. Where to start

1. **Watch three devlog Shorts you like** and write down the first five seconds of
   each. Nothing else teaches the hook as fast.
2. **Install OBS and CapCut.** Capture sixty seconds of anything and cut it. Throw
   it away. The point is removing the fear, not making something.
3. **Say the word and I will write the full post + shooting script for
   "The Warden is cut"** — it is the easiest first subject: short, visual, about
   taste rather than code, and nothing needs to be working for it to be true.
