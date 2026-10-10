# Nine frames — index

Nine new chassis, designed to the point where someone could build them and no
further. **Nothing here is built.** Each doc carries the gap it fills, a stat
table, the new weapons it needs, a node plan with this project's silent build
traps called out by name, the tests that would prove it, and what is still
open.

**Ten were designed; the Sapper was cut on 2026-10-10 after review.** Its doc
is kept as [SAPPER](SAPPER.md), marked CUT, because the gap it was aimed at —
nothing in the roster is built around placing mines — is still open. "Nothing
here is built" is also out of date: all nine have models now, and nothing has
a ChassisDefinition.

The reasoning that produced the set — the gap analysis, the supply spread, the
new weapon classes, and the three research sweeps behind them — is in
`docs/briefs/NEW_FRAMES.md`.

## Read first if you are building an enemy

**`ENEMY_FACTIONS.md`.** It is the blocker for the three enemy frames and the
most dangerous thing in the batch. Appending SWARM, STRATCOM and ARGUS to
`Enums.Factions` is free; the function next to it is not. `are_hostile()` has
no default arm, so a robot carrying a new value is simultaneously invisible and
near-invulnerable across thirty-five call sites, **not one of which errors**.
Rewrite it as a table first.

## The player's six

| frame | supply | cost | role | concept |
|---|---|---|---|---|
| [LANCE](LANCE.md) | 1 | 90 | wheeled scout / harass | A — Trike |
| [PICKET](PICKET.md) | 2 | 210 | ground anti-air | C2 — Launcher-led |
| [WARDEN](WARDEN.md) | 2 | 230 | emitter platform | A — The Mast |
| [DRAYMAN](DRAYMAN.md) | 2 | 170 | wheeled logistics | A — The Flatbed |
| [KITE](KITE.md) | 2 | 240 | **aerial**, armed | D — Skyhook |
| [VESSEL](VESSEL.md) | 3 | 340 | carrier | A — Bay Doors |

## The enemy three

Each belongs to one of the new factions, none is purchasable, and all three are
gated on `ENEMY_FACTIONS.md`.

| frame | faction | supply | role | concept |
|---|---|---|---|---|
| [BROODCARRIER](BROODCARRIER.md) | Swarm | 2 | **aerial** spawner | A — The Bunch |
| [BASTION](BASTION.md) | StratCom | 3 | deployable hardpoint | B — The Pylon |
| [SEE-ENGINE](SEE_ENGINE.md) | Argus | 3 | command node | A — The Oculus |

## Concepts

`concepts/` holds one sheet per frame: four options plus the Walker for scale,
rendered through the game's own icon studio rather than sketched, so what is
being judged is this project's line art and not another style. Picket has two,
because its winner was revised rather than picked clean.

**The rejections are written down with their reasons**, in each doc's section
1. A rejected option whose reason nobody recorded gets re-proposed six weeks
later.

## Two selections overrule their own stat tables

Both say so in the table cell, not only in the prose.

- **Vessel** — the chosen hull is wheeled, so `drives` becomes true. That is a
  sharper version of "spend 3 is not always a mech" than a third set of legs,
  and it has a cost logged in that doc's section 8.
- **Warden** — the mast telescopes. 6.68 m as drawn would catch on every
  bridge deck in the game, and raising it is the cheapest way to make an
  invisible field visible.
