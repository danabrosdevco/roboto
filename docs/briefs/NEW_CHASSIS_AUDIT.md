# The new chassis, audited — expected against observed

Run 2026-10-13 on the rebuilt proving ground (`maps/proving_level.tscn`, the
arena `tools/build_proving.gd` produced in `ec4cf69b`). Plan:
`Campaign/lab/plans/new_chassis_audit.tres`. 14 matchups, 3 repeats each,
4x speed, headless.

Owner: GAMEPLAY. Status: **measured once**. Three repeats is a look, not a
measurement, and every number below should be read as "this is the direction"
rather than "this is the value".

---

## 0. The instrument was broken until this run

Every table `lab_run.gd` has ever printed had blank damage, kill and accuracy
columns. Analytics switches itself off under a `--script` harness so test
suites do not write into the playtest folder (`analytics.gd:_should_record`),
and `lab_run.gd` **is** that harness. `tools/lab_walker.gd` and
`lab_armour.gd` already set `force_enable` and say why in a comment;
`lab_run.gd` and `lab_watch.gd` never did.

Fixed in `7fd05746`, one line. Verified against `walker_duel`: the Walker now
reports 460 damage, 3 kills and 58% accuracy where the same plan previously
reported zeros across the board.

**So every figure in this document is the first real one this harness has
produced.** Any earlier lab conclusion that rested on a damage or kill column
was resting on a zero.

---

## 1. The four questions, answered

### Does the Lance actually shoot? **Yes — and it is the most accurate frame in the run.**

| | Lance | Rover control |
|---|---|---|
| accuracy | **89%** | 45% |
| damage per body | 132 | 114 |
| kills per body | 1.33 | 1.75 |
| deaths / fielded | 2 / 6 | 0 / 12 |
| win rate | 67% | 100% |

It shoots, it hits nearly twice as often as the frame it is built on, and it
deals more damage per body. The hull-slew aiming is not a handicap — it looks
like an *advantage*, because a frame that can only fire when its whole body is
lined up does not take the marginal shots a turret takes.

What it is not is durable: 110 hull against the Rover's, two dead out of six,
and a 67% win rate against the Rover's 100%. **That is the frame working as
designed** — 90 compute and 1 supply against the Rover's 150 and 2.

### Does the Picket do anything? **Almost nothing, and the reason is in the accuracy column.**

| | Picket | Walker control |
|---|---|---|
| accuracy | **0%** | 67% |
| damage per body | 37 | 188 |
| kills per body | 0.33 | 2.00 |
| deaths / fielded | **4 / 6** | 0 / 9 |

**Zero per cent.** Across three fights and six bodies the Picket's rockets did
not land a single registered hit. Its 220 total damage is blast radius
catching people incidentally, not aimed fire — and it died four times out of
six doing it, while the Walker holding the same line at the same range died
none.

This is exactly the failure the design documents predicted and nobody had
measured: **nothing in this project leads a moving target**
(`AIWeapon.flight_time()` feeds `target_hold_seconds` and a grenade fuse and
nothing else; `AIWeaponRecoilless._aim` fires at the target's current
position). An arcing rocket with a five-second flight time lands where a
rifleman *was*.

The frame is not broken. The weapon cannot hit anything that moves.

### Is the Kite picked off? **No. It is the best frame in the run.**

| | Kite | Rover control |
|---|---|---|
| deaths / fielded | **0 / 6** | 0 / 6 |
| damage taken | **159** | 375 |
| enemy accuracy against it | **19%** | 42% |
| own accuracy | 66% | 50% |
| kills per body | 2.00 | 1.75 |
| win rate | 100% | 100% |

At 22 m cruise, riflemen hit it **less than half as often** as they hit a
Rover on the ground, and it took 159 damage to the Rover's 375 across the same
fight. It out-shot the Rover on accuracy and kills while being harder to hit.
Ninety hull turns out not to matter when almost nothing connects.

The worry was reasonable and the measurement says the opposite.

### Does the Broodcarrier fly too low? **Yes. This is the cleanest result in the run.**

| | Broodcarrier (12 m) | Spotter control (22 m) |
|---|---|---|
| deaths / fielded | **5 / 6** | **0 / 6** |
| damage taken | **1059** | **0** |
| enemy accuracy against it | **73%** | never engaged |
| survived | 17% | 100% |

Two unarmed flyers, same fight, same enemy, same orders. The one at 12 m was
hit 73% of the time and five of six died. The one at 22 m **was never shot at
once** — zero damage taken, across three fights.

Ten metres of altitude is the entire difference between a frame that works and
a frame that is target practice. The Broodcarrier's `cruise_height = 12.0`
(`brood.tscn`) is the single number to change, and the Spotter's 22.0 is the
proven value.

A caveat worth keeping: the Broodcarrier is *supposed* to be reachable — its
design argument is "the squad loses because it was slow", which requires that
a squad which is *not* slow can kill it. The question is whether 12 m makes it
reachable or merely free. 73% hit rate and 5/6 dead says free.

---

## 2. The rest

### Bastion — works, and is the hardest-hitting frame measured

225 damage per body, 11 kills from 3 fieldings, zero deaths, 100% win. The
highest damage-per-body figure in the entire run.

But the control says something quieter: a **Walker** in the same hold also won
100%, and finished with **88% hull against the Bastion's 75%**. The Bastion is
better at killing and worse at surviving than the frame it replaces, which is
not what a hardpoint is for. Its hardening is same-faction only, and in a lab
where allies share one faction it should have been working — so this is a real
comparison, not a wiring failure.

### See-Engine — the contact feed is working, and accuracy is the proof

| | with See-Engine | 4 rifles alone |
|---|---|---|
| ally accuracy | **41%** | 31% |
| ally damage | 787 | 347 |
| win rate | 67% | 0% |

**The control is confounded and I am saying so**: the See-Engine side fielded
five bodies against the control's four, and an extra body is an advantage even
when it never fires. Win rate and total damage are therefore not clean.

**Accuracy is clean**, because adding a body that never shoots cannot raise
the other four's hit rate. 31% to 41% is a ten-point swing on identically
equipped riflemen, and that is the frame's whole mechanism showing up as a
number. The See-Engine does what it claims.

### Vessel — dies, and its cargo outperforms it

Three fielded, three dead, zero damage dealt, 812 taken. Its hatchlings scored
**2 kills and 144 damage** — 144 damage per body, better than the Lance.

The carrier is a 340-compute body that cannot defend itself in a line. That is
arguably correct for a carrier, and this test put it in a line, which is the
wrong test for it. What the numbers do say is that **the hoppers work** and
the delivery vehicle is fragile.

### Drayman — dies, and this test could not measure it

Three fielded, three dead, zero damage, 571 taken. Expected: it has no weapon.

This matchup measures nothing about the Drayman, because what it is for —
restoring the player's ammunition and the squad's equipment charges — has no
expression in an AI-versus-AI lab with no player in it. **It should not be
fielded in a firing line and this row should not be read as a verdict.**

---

## 3. What to change, in order

1. **Broodcarrier `cruise_height` 12.0 to around 22.0.** One number. The
   Spotter proves the value and the comparison is unambiguous.
2. **The Picket needs a weapon that can hit a moving target, or a different
   job.** Target leading is roughly twenty lines on
   `AIWeaponGrenadeLauncher._lob_velocity`, which already has the target — but
   it changes every indirect weapon in the game and must not arrive inside one
   chassis. The alternative is accepting the Picket as a bombardment frame
   aimed at things that do not move.
3. **Nothing for the Lance or the Kite.** Both exceeded expectation.
4. **The Bastion wants a reason to be chosen over a Walker.** It kills better
   and survives worse; its hardening did not show up as survivability here.
5. **Re-run the See-Engine with a clean control** — four rifles plus an inert
   fifth body, against four rifles plus a See-Engine — so win rate becomes
   readable too.

## 4. What this run cannot tell you

- Three repeats. Every figure has wide error bars.
- The lab fights on one arena, in the open, with no cover doctrine and no
  player. The Drayman and the Vessel are both mis-measured by that.
- Squad equipment and player ammunition — the Drayman's actual job — cannot
  appear at all without a player in the loop.
- All allies share one faction in the lab, so the Bastion's same-faction
  hardening and the See-Engine's same-faction contact feed are both being
  measured in the most favourable possible configuration.
