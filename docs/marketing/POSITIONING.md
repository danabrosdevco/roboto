# Positioning — a weapon that gives orders

Rewritten 2026-09-28 by MARKETING after the human corrected the frame. The first
draft is superseded; what it got wrong is recorded at the bottom rather than
deleted, because the error is instructive.

---

## The correction that changes everything

The GDD's pillar is *you are not the gun, you are the commander.* The human's
response:

> "you are not the gun is sort of a misnomer because you are literally an
> agent-ai trying to conquer compute from other ai's. in this way you are just a
> gun."

That is right, and it is better. **You are a weapon that was issued a squad.**

The chain runs three deep and you are the middle link:

| | knows what it is | chose to be here |
|---|---|---|
| whatever hands you objectives | — | — |
| **you** | **yes** | **no** |
| your squad | no | no |

Something points you. You point them. The squad does not know it is not
human-shaped, does not know the town was a town, does not know anything. You do.
That is the entire difference between you and the things you command, and it is
the only thing in the game that hurts.

**"You are not the gun" was doing two jobs and failing one of them.** It was
trying to set gameplay expectations (*you will not win this by aiming*) and make
a thematic claim (*you are the commander, not the weapon*) in one sentence. The
thematic claim is false. Split the jobs and both get better.

---

## The two lines that replace it

**Thematic — the one for key art, an end slate, the top of a page:**

> ### Something points you. You point them.

Six words, the whole vertical chain, no names, no plot, and it is exactly true of
the software. It also works as the first line a journalist quotes, which is the
job that sentence has to do.

**Expectation-setting — the one that stops the wrong person buying it:**

> The rifle in your hands is not the point. The squad is.

Deliberately softer than "aiming is not how you win," because **that stronger
claim is not currently true of the build.** See the honesty note below. This
version is true today and does not need a patch to stay true.

**Retired:** *you are not the gun.* It stays in the GDD as a design pillar, where
it is doing useful work telling the build what to become. It should not go on a
store page.

---

## Compute is the spine, and it is already in the build

The strongest thing about the human's frame is that it resolves the setting into
a loop that needs no fiction at all:

> **You are an AI taking compute from other AIs. Compute is how many robots you
> can be at once.**

Trace it, because every step is in the software:

1. You are handed objectives that advance and secure **compute**.
2. Compute buys **seats** (board ruling 2026-09-28; taught in-game by
   `lesson_prompts.gd`).
3. Seats are how many robots you can command at once.
4. So the size of your force in the field is how much compute you have taken.

Which means: **taking compute makes you larger.** Not richer — larger. The squad
is not an army you own, it is the extent of you. Losing a frame is not losing an
asset, it is being briefly smaller.

This is worth an enormous amount, for three reasons a marketer will recognise
immediately:

- **It is a motivation with no story attached.** No villain, no stakes, no
  "before it's too late". The game's own currency explains why you fight, and the
  explanation fits in one sentence.
- **It is topical for free.** In 2026, "an agent competing for compute" needs no
  gloss. You do not have to teach anyone the premise, which is normally the most
  expensive paragraph on a store page.
- **It makes the attachment thematic instead of just mechanical.** You did not
  choose the war, the objectives, or your own existence. **The squad is the only
  thing in the chain you chose** — which frames you bought, what you fitted them
  with, and whether you go back for one that went down. That is why losing one
  lands. The emotional design and the fiction now argue for the same thing
  instead of sitting next to each other.

---

## Not one dead city. A tour.

Second correction from the human: *"there's not one dead city you're in a ton of
different locals."* The first draft's one-liner said "a dead city" and that was
both wrong and smaller than the truth.

The campaign is a sequence of unlike places — a sim arena, a valley basin, a
coast road, three river bridges, a town called Mutaha, a causeway. Different
terrain, different shape of fight, nothing in common.

Two things follow, one creative and one operational:

**Creative.** *Places*, plural, is the stronger version of the idea anyway. One
dead city is a setting. A tour of unlike places that have each lost their purpose
is a **world**, and the fact that your squad treats a coast road and a town
identically — as an objective with enemies near it — is the point being made
repeatedly rather than once. The repetition *is* the argument.

**Operational.** Variety of place is a marketing asset and it should be spent
deliberately: five screenshots from five different locations read as a big game;
five from one map read as a demo. The shot list in
`docs/marketing/DISPATCH.md` has been rewritten one-shot-per-locale for exactly
this reason.

Names get used. Purposes never do. "Mutaha" and "the coast road" and "three
rivers" are specific, and nothing ever says what any of them were for.

---

## Why the vagueness is still the right call

The original argument survives the reframe and gets sharper, because it now has a
mechanical anchor rather than only a tonal one.

**The absence is the agent's point of view, not a gap in the writing.** An agent
is handed tasks, not context. Nothing explains the war to you because nothing has
any reason to. Every other squad-tactics game has an officer with a name who
tells you why; this one cannot, and the reason it cannot is now the premise
rather than a stylistic preference.

**Naming an AI is a content debt.** The moment Argus or Mama Green or Algie
appears on a store page, the player wants a plot and you owe them one — written,
voiced, paid for, shipped. Refusing to name anything is the only version of this
setting that costs nothing to maintain. The human's instinct was already pointing
here; the compute loop is what makes it viable, because it supplies motivation
without supplying characters.

**It is the only frame in which the squad's unawareness works.** A narrator
notices things on the player's behalf. Silence is what leaves the player alone
with it.

**What it costs**, stated plainly:

- No voiceover hook. Nothing in this world talks, so a trailer carries on image
  and sound alone, and the audio has to be good.
- "Thin" is the review word, and the only defence is that the absence must feel
  authored. The interface is the worldbuilding: *compute, seats, salvage, signal,
  chassis, frames.* One line of explanatory backstory anywhere and the stance
  collapses into "they didn't finish writing it."
- A curator may hear "no story" as "no content." Mitigation: specificity moves
  from plot to place and procedure. The game is extremely specific about
  distances, frames, callsigns and crossings. It is simply never specific about
  *why*.

---

## The rules that make it hold

Marketing rules. They have design implications, which is the human's call.

1. **Never name an AI.** Not one, not ever, not in a devlog. The enemy is amber.
2. **Never explain the war.** It is prior, total and finished. Nobody won.
3. **Places keep real names. Nothing says what they were for.**
4. **Orders are instructions, never motivation.** ADVANCE. SECURE. HOLD. Never
   "for humanity", never "before it's too late".
5. **No human voice, anywhere, ever.** No survivors on screen, no person on the
   radio, no voiceover in any trailer. The sharpest marketing consequence on this
   list and the last one that should ever be broken.
6. **The only emotional register is the squad.** Callsigns, ranks, who came back.
   Straight, never ironic. If a line is funny about a robot, it is wrong.
7. **New:** *compute* is always capacity, never money. The moment it reads as
   currency the loop flattens into a shop. It buys seats — it buys how much of
   you there is.

---

## What it sounds like

### Store blurb

> You are an agent. You are handed objectives and you meet them.
>
> Somewhere above you, something is taking compute from something else, and every
> order you receive is part of that. Compute is how many robots you can command
> at once, so every objective you secure makes you larger. The places you secure
> them over — a coast road, a river crossing, a town — have lost any sense of
> what they were for, and your squad does not notice, because a squad deals in
> objectives, enemies and orders.
>
> You notice. That is the only difference between you and them.

### A trailer with no words

Sixty to ninety seconds, two text cards, the game's own drone and the game's own
silence. **Locations change; the squad's behaviour does not.** That is the edit's
whole argument, and it is only available because the campaign spans unlike
places.

| t | shot |
|---|---|
| 0:00 | Black. The drone alone, five seconds, longer than is comfortable. |
| 0:05 | A wide still of the coast road. No robots. Hold until it is almost too long. |
| 0:12 | A squad walks in from the bottom of frame. Capsules. No cut, no music change. |
| 0:20 | First order, written in green phosphor. They move. |
| 0:26 | **Hard cut — a different place.** Mutaha. Same framing, same walk, same order. |
| 0:32 | **Hard cut — a different place.** The river crossing. Again. |
| 0:38 | Contact. Amber. Short and ugly and legible, not a highlight reel. |
| 0:48 | One of yours goes down. |
| 0:52 | Hold on it. Three seconds. Do it anyway. |
| 0:55 | A Mechanic walks in and stands it up. **This is the trailer.** |
| 1:03 | The squad walks out. Wide. The place is behind them, unchanged. |
| 1:10 | Card: **SOMETHING POINTS YOU. YOU POINT THEM.** |
| 1:15 | Card: **DATA CENTER WARS 2109.** Cut to black *before* the drone ends. |

The climax is a repair, not a kill. That single editorial decision is what makes
it this game's trailer rather than any shooter's.

### Mission briefings, in register

> SECURE THE CROSSING. THE WEST BANK IS HELD.
>
> ADVANCE TO THE PADS. TAKE WHAT IS INTACT.
>
> HOLD UNTIL THE RECLAIMER IS CLEAR.

### The answer to "so what's the story?"

One paragraph, memorised, for press and curators and strangers at a show:

> There isn't one, deliberately. You're an agent — an AI with a squad and a list
> of objectives, taking compute off other AIs, and nothing has any interest in
> explaining itself to you. Compute is how many robots you can command at once,
> so winning literally makes you bigger. The places you fight over used to be for
> something and neither you nor your robots can tell what. The robots don't know
> anything. You do. That's the story.

---

## The competitive frame

Judgement, not research.

- **Structurally**, the nearest things are the command-inside-an-FPS games:
  *Brothers in Arms*, *Full Spectrum Warrior*. Well-loved, effectively
  unoccupied. The most useful single fact in this document.
- **Emotionally**, it is a persistent-roster game: *XCOM*, *Battle Brothers*,
  *Darkest Dungeon*. Named units you lose and get attached to — a large, loyal
  audience with no first-person option.
- **Thematically**, the nearest neighbours are the cold-systems games —
  *Highfleet*, *Duskers*, *Signalis* for tone. **Duskers is the closest
  reference point in the whole space**: you command expendable machines through
  dead places via an interface, you never touch anything yourself, and it is
  deeply sad without a single line of exposition. Worth studying how it was
  positioned.

One sentence, for a pitch email or a curator note:

> **The persistent squad of a tactics game, inside a first-person shooter, with
> the shooter's power fantasy taken out of it.**

**The thing to defend against is being filed as a shooter.** An FPS audience buys
it for the aiming, discovers the aiming is not the point, and reviews it badly.
Every tag, every screenshot, every clip should read *tactics* first and
*first-person* second. The Steam tag order in `docs/marketing/PLAN.md` is built
around this and it is the highest-leverage decision on the store page.

---

## Honesty note — the pillar is not true yet, in two directions

A marketing document should not sell a claim the build does not support, so:

1. **Three of four squad orders lose 100% of the time** (GDD §8). Attack-a-target
   wins; advance, move-and-hold and hold-at-range each win nothing.
2. **The player is currently too strong alone.** The board names it directly —
   the *"long-range-god problem"* — and ruled on 2026-09-28 that the answer is to
   give the player better things to want rather than to take the option away.

So at this moment the honest description of the build is closer to *a first-person
shooter with a squad you get attached to* than to *a command game*. Both are
being worked on and neither is a marketing problem to solve with words.

This is why the copy above says "the rifle is not the point" and not "aiming is
not how you win." The second sentence is the one you want, and it becomes true
when those two items close. **That is Gate B in `docs/marketing/RUNWAY.md`**, and
it is the single best argument for the runway being gated rather than dated.

---

## What the first draft got wrong

Recorded rather than deleted:

- Led on **"you are not the gun"** as the headline. Thematically false — you are
  a weapon pointed at other AIs. Replaced.
- Wrote **"a dead city"**, singular. The campaign spans unlike places and the
  plural is the better idea.
- Treated the setting's openness as **a tonal stance to defend**. With the
  compute loop it is a *premise with a motor*, which is a much stronger position
  and needed no fiction to get there.
- Under-read **compute**. It was listed as an economy row; it is the spine.
