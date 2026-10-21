# TESTING — what each tool proves, and which to run

**Read this before reporting any work.** `CLAUDE.md` carries the
non-negotiable one-liner and the definition of done; this is the full account
of what exists and what each thing actually proves.


Measured 2026-10-16, not remembered. `tools/` holds **103 `test_*.gd`, 90
`probe_*.gd`, 19 `shot_*.gd`** and 148 builders and utilities. Three prefixes,
three different contracts:

| prefix | what it is | how it is run | how it reports |
|---|---|---|---|
| `test_*.gd` | an assertion suite | by `tools/test.sh`, and by hand | **exit code** — 0 passes |
| `probe_*.gd` | a diagnostic | by hand, always | prints measurements |
| `shot_*.gd` | a camera | by hand, **headful** | writes PNGs |

**The exit code is the contract for a suite, not the printing.** All 103 call
`quit()` with a code and `test.sh` reads only that; the `PASS`/`FAIL` line is a
house style 48 of them use. A new suite must `quit(0)` on success and non-zero
on failure, whatever else it prints.

**A probe answers "what is it", a suite answers "is it right".** Use a probe
when you are finding something out and a suite when you are pinning something
down. Fourteen probes currently print `PASS`/`FAIL` and are suites wearing the
wrong prefix — do not copy them.

**A `shot_` tool must refuse `--headless` and say so.** The dummy renderer
returns blank textures, so a headless render comes back flat and *looks like
proof*. Sixteen of the nineteen guard against it; three do not.

## The runners

```bash
bash tools/check.sh --changed     # parse + scenes, only what you touched
bash tools/check.sh               # the whole project, slow
bash tools/smoke.sh [seconds]     # boot the game, default 15
bash tools/bucket.sh --list       # what buckets exist, and their size
bash tools/bucket.sh campaign     # one named bucket, per-suite timeout
bash tools/bucket.sh terrain --quick   # ...skipping the ones that boot a world
bash tools/test.sh                # every test_*.gd — SEE THE WARNING BELOW
bash tools/test.sh --fast         # only suites that never boot world.tscn
bash tools/gate_terrain.sh        # retired — now a wrapper for `bucket.sh terrain`
```

## THE FIVE BUCKETS — run one of these, never a list you invented

Every suite carries a `# BUCKET: <name>` line near the top, and
`tools/bucket.sh` reads it **from the file**. There is no list in the runner,
because a list drifts the first time somebody adds a suite and forgets — and a
drifted list still reports a pass, which is worse than no list at all.

| bucket | what it covers |
|---|---|
| `campaign` | the board, the ledger, missions, sites, turns, saves, the arena |
| `frames` | chassis, squads, AI behaviour, barks, contact |
| `kit` | weapons, ammo, equipment, modules, targeting, the designator |
| `terrain` | blocks, navmesh, water, bridges, scatter, geometry |
| `shell` | boot, settings, pause, splash |

**There are no sizes in that table on purpose.** An earlier version printed
them and they were wrong inside a day — in a document whose whole argument is
that a hand-kept list drifts. **`bash tools/bucket.sh --list` is the only
honest source**, because it counts the files. If you want a number for your
report, run it.

**Name the bucket and the count it printed when you report** — "campaign, 40
suites, PASS". If you ran something narrower, say which suites and why. **Do not
assemble your own set and call it a pass**; that is unreviewable and different
every time, which is the whole reason buckets exist.

A suite in no bucket is a suite no instruction will ever tell anyone to run, so
`bucket.sh --list` names any it finds. **A new suite gets a `# BUCKET:` line.**

**`check.sh`** runs three phases: GDScript parse, scene/resource integrity
(`load_steps` included), and overlapping brushes. It proves code *parses*. It
cannot prove it *runs*.

**`smoke.sh`** boots the real game headless with `-- --no-save` and fails on
any runtime error in the window. This is the only thing that catches a null
node path, a bad cast or an unassigned export on frame one.

**`test.sh`** globs every `tools/test_*.gd`. `--fast` skips any suite whose
file mentions `world.tscn` — the tier marker is read from the file, so it never
drifts. Parked suites are skipped by reading `# PARKED:` **from the file**, the
same way buckets and `# REPORTS:` are read; there is no list in the runner.

**`test.sh` finishes, as of 2026-10-17 — it did not before.**
`test_designator_squad.gd` was believed to loop forever. It does not: it runs
97 assertions in 15 seconds and then a DIAGNOSTIC PRINT killed it, indexing
`_queued[-1]` on an array a failing check had just proved empty. `[-1]` on an
empty Array is an out-of-bounds ERROR in GDScript, the script died with a
worker thread unjoined, and the process never exited — indistinguishable from a
hang from outside. `test.sh` has no per-suite timeout, so it waited forever and
everything behind it stalled; twelve orphaned Godot process pairs were once
found from it, aged up to four days.

The print is guarded now and a full run takes **about 24 minutes** for 104
suites. **`bucket.sh` still has the per-suite timeout and `test.sh` still does
not**, so one new dead suite can stall the whole run again — prefer a bucket.

**Still say which suites you ran.** "The full suite" was untrue for months
without anyone noticing, which is the argument for naming what you ran rather
than for trusting that the phrase means something.

**A suite that asserts nothing is a failure here too.** An exit code cannot
tell "everything passed" from "nothing ran": both are 0, and a test that has
silently stopped testing looks exactly like one that passed. `bucket.sh` fails
any suite that exits 0 having printed nothing resembling a check. The three
that legitimately print a table and assert nothing carry a `# REPORTS:` line
in the file saying so — the same read-from-the-file rule as the buckets.

### Three tags, all read from the suite

| tag | means |
|---|---|
| `# BUCKET: <name>` | which bucket it belongs to. Every suite has one |
| `# REPORTS: <why>` | prints a table, asserts nothing, deliberately |
| `# PARKED: <why>` | known-failing on authored content; skipped and NAMED |

**None of them live in a runner.** `test.sh` kept its parked list internally
until 2026-10-16, and the result was exactly the failure this whole mechanism
exists to prevent: `bucket.sh terrain` reported FAIL on `test_terrain`, a suite
`test.sh` had been deliberately skipping for days. Two runners, two lists, two
different opinions about one suite. The tag travels with the file, so they
cannot disagree.

**A parked suite is a suite nobody is watching**, so both runners name them in
the summary rather than quietly omitting them. Un-parking is deleting a line.

## What to run, by what you touched

| you changed | run |
|---|---|
| anything at all | `check.sh --changed` — **non-negotiable, must print `PASS`** |
| something that loads at startup | `+ smoke.sh` |
| the ledger, store, missions, sites, turns | `+ bucket.sh campaign` |
| a chassis, squad behaviour, AI or barks | `+ bucket.sh frames` |
| a weapon, ammo, module or the designator | `+ bucket.sh kit` |
| a level, blocks, prefabs, navmesh or water | `+ bucket.sh terrain` |
| boot, settings, pause or splash | `+ bucket.sh shell` |
| `Campaign/locations/*` or `location_catalogue.tres` | `+ test_campaign_spine.gd` — a new Location moves §2's income totals and a degree count |
| a mission's enemy force | `+ measure_resistance.gd`, `+ spawn_geometry_audit.gd` |
| anything you cannot see | **render it** — a `shot_` tool, and look at the image |

If you cannot run something, say which one and why. A named gap is useful; a
silent one is how a red suite survives a report.

