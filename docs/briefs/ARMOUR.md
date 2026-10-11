# Brief — Armour

Ruled by the human 2026-09-28, verbatim below the line. This closes the
question that had blocked the armour model since 2026-09-23.

Owner: **GAMEPLAY**. Status: **not started**. See `docs/BOARD.md` for where it
sits in the queue.

---

## Coordinator notes — read before starting

Three things the brief does not say, that change how it has to be run.

**1. The `_collapse_pieces()` sequencing note is spent.** The brief asks for the
corpse fix to land first and separately. It has: `_collapse_pieces`,
`enter_passive_mode`, `squad_is_engaged` and `_on_revived` are all in HEAD.
Nothing about armour is blocked on it and there is no commit owed.
`Character/characters/ai/enemy.gd` *is* still modified in the working tree —
about a hundred lines — but that is later, live work belonging to whoever is in
it now. **Do not commit it to clear this note.** Read the live file, add the
armour helper to `apply_damage`, and leave the rest of the diff alone.

**2. Capture the Laboratory baseline BEFORE touching anything.** The brief asks
for "lab it before and after". The *before* is perishable: once the helper is in
`apply_damage` there is no way back to it except by reverting. Build a plan for
the two named matchups and run it first. Suggested shape, from the coordinator:
4 rifle troopers vs a rover and 4 vs a walker, both ADVANCE, 35 m, **six**
repeats not three (one rover killing four troopers is close to a coin flip at
low n, and a baseline is only worth having if it is trustworthy), no side
swapping — the question is not who wins, it is how much damage a rifle puts
into a hull. Keep damage dealt per run and average time; those are the two
numbers the multipliers will move.

**3. Nothing is HEAVY yet.** The decided classes use unarmoured, light and
medium only. The heavy row — FLAT 28, small arms 0.30 — is authored but
unreached, so it ships untested and its first real user will be whatever the
tier expansion adds. Worth knowing before trusting those numbers.

One observation, not an objection: **anti-armour is deliberately worse against
unarmoured (0.80)**, and the Walker's main mount is the autocannon. That makes
a player Walker weaker against infantry than its own coax is — which is what
the coax is for. It reads as intended; flagging it so it is not "fixed" later
by someone who reads it as a bug.

---

## The brief, as given

Build the armour rule and the feedback for it. Nothing exists today: no
`armour_class`, no `damage_type`, no `pierce` anywhere in the build.

**SEQUENCING:** send the `_collapse_pieces()` fix first and let it land on its
own. Both touch `enemy.gd` and untangling them afterwards is not worth it.

### The rule

```
applied = max( raw * 0.05, ( raw - max(0, FLAT - pierce) ) * MULT )
```

**FLAT:** unarmoured 0 · light 6 · medium 16 · heavy 28

**MULT**, in that class order:

| Damage type | unarmoured | light | medium | heavy |
|---|---|---|---|---|
| small arms | 1.00 | 0.80 | 0.50 | 0.30 |
| explosive | 1.00 | 0.90 | 0.70 | 0.50 |
| industrial | 1.00 | 0.95 | 0.80 | 0.65 |
| anti-armour | 0.80 | 1.00 | 1.00 | 1.00 |

**FLAT APPLIES AFTER RANGE FALLOFF.** Not a preference — it is the call shape
you have. `AIWeapon._one_round` computes `calculate_damage(hit_dist)` and hands
the result to `apply_damage`, so falloff has already happened by the time
armour sees it. Do not thread the pre-falloff number through the hit path.

### Where things live

- `armour_class` → **`ChassisDefinition` ONLY.** Not on `Enemy` as well. One
  source of truth; two catalogues is the failure this project keeps repeating.
- `damage_type` + `pierce` → `AIWeapon` and the player weapon classes.
- One helper, called from `Enemy.apply_damage`.

**Analytics is already waiting:** `enemy.gd` calls
`_Analytics.damage(self, damage, damage, source, health <= 0)`, passing the
same number twice for raw and applied. Fill the second one in with what armour
let through and absorption lands in the playtest log for free.

### Classes — decided

- **light** — rover, reclaimer
- **medium** — walker, and the Nest
- **unarmoured** — everything on legs, plus the spotter drone and the gunship

The Nest is MEDIUM, not heavy. At FLAT 28 a rifle does the 5% floor into a 500
hull — 333 hits — and nests currently die to rifles, with `nest_down` live as a
reinforcement trigger in three missions. Heavy would brick them.

### Damage types

- **small arms** — m4, pistol, shotgun, carbine, machine gun, heavy MG, marksman
- **explosive** — grenade launcher, turret GL, mortar, frag, hatchling
- **industrial** — reclaimer drum, melee
- **anti-armour** — 20 mm autocannon, Recoilless Rifle

### Ship the counter in the same pass

The Walker is a PLAYER frame and at Medium nothing the enemy carries can
meaningfully hurt it — every enemy small arm drops to 2–7 a hit and only
mortars and GLs get through. The autocannon is already whitelisted to `rover`
and enemies field rovers, so put an autocannon rover into the back-half
missions (three bridges, mutaha) as enemy force data. Without it the mid-game
has no answer to a walker.

### The feedback is not polish

A rifleman doing the 5% floor reads as a broken gun unless the game says so.
Phase 1 is not done without a ricochet spark and a dull hit when a shot is
floored, and the armour class on the scanner readout and the squad HUD.

**DO NOT touch signal.** Armour acts on the hull only. Riflemen who cannot
scratch a walker must still be able to suppress it — that is the whole reason
cheap robots stay relevant, and it is the counter-play the tier ladder rests on.

The player stays out of the class system; `damage_taken_scale` 0.5 already does
that job.

### Done means

- `docs/GDD.md` §3, §4 and §5 updated in the same commit.
- Gates per CLAUDE.md.
- Laboratory run before and after: 4 rifle troopers vs a rover, and vs a walker.
