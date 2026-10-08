# Brief — doctrines, as a chosen upgrade

Written 2026-10-08 by GAMEPLAY. Captured as a TO-DO from a design conversation,
not started and not scheduled.

Owner: **unassigned**. Status: **idea, logged deliberately**.

**The pitch:** you pick a doctrine. It changes how your robots behave — how they
approach, how they hold, what they do when they lose a target — and it carries
bonuses that suit that behaviour. It is a squad-wide, campaign-level choice, not
a per-robot fitting.

---

## Why it is worth doing

The AI already has the knobs. What it does not have is anybody turning them
together, on purpose, as an identity.

Scattered through `enemy.gd` and `squad.gd` there are already exported values
for advance distance, fallback distance, bound detour limit, aim settle time,
moving accuracy penalty, investigate radius and cooldown, reacquire sight scale,
aggressive pull interval, cover preference, and the `aggressive` flag that
decides whether a Soldier is a rusher. Each is tuned once and applies to
everybody forever.

A doctrine is a NAMED SET of those, chosen by the player, with a line of fiction
on it. That is most of the work already done — the value is in the curation and
the framing, not in new systems.

## The shape

Three or four, mutually exclusive, swappable at base between operations. Each
should change **how a fight looks**, not only what the numbers say.

Sketches, not decisions:

| Doctrine | Behaviour | Trades |
|---|---|---|
| **Bounding** | Short advances, heavy cover preference, never both halves moving at once. Slow, hard to dislodge. | Accuracy and survivability up; tempo down. Loses races for ground. |
| **Aggression** | Everyone is a rusher. Closes immediately, ignores being outranged, pulls on every contact. | Punishes a slow enemy; melts against anything that out-reaches it. |
| **Overwatch** | Holds at maximum effective range, settles before firing, refuses to advance into contact without an order. | Devastating with good sensors; helpless when flanked or rushed. |
| **Dispersal** | Wide spacing, independent movement, re-engages from multiple angles. | Beats artillery and AoE; loses mutual support and concentration. |

**The interesting bit is that these should counter each other**, and should
counter *enemy* postures — `EnemySquadSpec.Posture` already has PATROL, GARRISON,
ADVANCE and RESERVE. Overwatch should beat Advance and lose to a flank;
Aggression should beat Overwatch and break on a Garrison.

## Where it hooks

- **Behaviour**: the exported tuning values above, applied as a multiplier set
  when the squad is built. `SquadSpawner._build_soldier` already does per-record
  fitting, and `Squad.assign_roles()` already exists as a place where a squad
  decides what its members are for.
- **Bonuses**: the same shape as a MODULE — `ItemDefinition` already carries
  `accuracy_bonus`, `speed_multiplier`, `sensor_bonus`, `health_bonus`,
  `signal_resistance_bonus`. A doctrine could literally be a module applied to
  everybody, which would make it cheap and consistent.
- **Unlock**: the software tree (`Campaign/software_tree.gd`) is the obvious
  home — a doctrine is exactly the kind of thing that tree is for.

## What it touches that needs care

- **THE SAVE.** A chosen doctrine is campaign state and has to round-trip.
  Follow the additive pattern `cosmetic_id` used: write it, read it with a
  default, so a save made before doctrines existed loads clean.
- **Enums are append-only** in this project — their values are ints in `.tscn`
  files. If doctrines become an enum, it only ever grows.
- **It changes the feel of every fight.** This is the one on the list that
  cannot be judged from a headless test or a screenshot. It needs somebody
  playing it, which means it should be built behind the debug menu first and
  turned on for real only once it has been felt.

## Do this after contact freshness

`docs/briefs/CONTACT_FRESHNESS.md` is the prerequisite, and not for technical
reasons: **a doctrine about how your squad uses information is meaningless until
information means something.** Overwatch in particular is just "stand still" if
a fresh contact does not let you shoot at range.

## The open question

**Is a doctrine a choice you make once, or one you make per operation?** Per
operation makes it a tactical read of the briefing and rewards knowing the
enemy; once-per-campaign makes it an identity and rewards committing. The second
is a stronger fantasy for a rogue drone building a squad from salvage; the first
is better game. Worth deciding before any of it is built, because it changes
where the state lives.
