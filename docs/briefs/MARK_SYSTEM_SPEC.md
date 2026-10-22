# Mark system — implementation spec

Written 2026-10-21 by GAMEPLAY, off a design conversation with the human.
**Status: specced, not built. No code exists.** Nothing in this document has
been implemented; `grep mark_level` returns nothing and all five squad-manager
pages are untouched.

The design and the rationale are in the two artifacts the human holds (the
brief, and a clickable prototype of the Factory). **This file is the other
half: what to build, in what order, and what breaks on the way.**

---

## 1. The decision that makes this cheap instead of expensive

The obvious reading of "a robot's loadout belongs to its production line, not
to the robot" is that `SoldierRecord.weapon_ids` / `equipment_ids` /
`module_ids` stop being storage and become derived from the line. **Do not do
that.** It is the expensive version and it buys nothing.

Measured blast radius of making them derived:

- **11 production files** read those three arrays — `campaign.gd`,
  `campaign_state.gd`, `induction_objective.gd`, `item_definition.gd`,
  `soldier_record.gd`, `squad_spawner.gd`, `test_character.gd`,
  `equipment_loadout.gd`, `icon_art.gd`, `squad_page.gd`, `analytics.gd`.
- **12 suites** assert on them, and seven of those are the chassis suites —
  `test_drayman`, `test_kite`, `test_mortar`, `test_picket`, `test_vehicle`,
  `test_vessel`, `test_walker`. They build their fixtures by writing loadout
  ids directly, which is the right way to test a chassis and has nothing to do
  with the Mark system. Making the arrays derived breaks every one of them for
  no reason connected to what they test.
- The save stores all three as string arrays, so it changes too.

**Instead: the arrays stay the storage, and adopting a Mark is a bulk write.**

> Adopting Mk N on a line means: for every SoldierRecord whose `chassis_id`
> matches that line, overwrite `weapon_ids`, `equipment_ids` and `module_ids`
> from the Mark table, then `recompute_stats`.

That turns a refactor into an additive feature. Saves keep working, all 11
readers keep working, all 12 suites keep working, the Lab and every test rig
can still construct an arbitrary robot by hand. The only genuinely new
persistent state is two values per line.

---

## 2. New state

### 2.1 Per line, on `CampaignState`

```gdscript
## Mark level per chassis line, 0-2. Absent means Mk 0.
@export var line_marks: Dictionary = {}      # StringName chassis_id -> int
## The one module adopted per line. Absent means none.
@export var line_modules: Dictionary = {}    # StringName chassis_id -> StringName
```

Line *openness* already exists and must not be duplicated —
`CampaignState.is_unlocked(id)` reads `allocations[unlock_key(id)]`, and
`unlock_chassis()` is the thing that opens a line. Marks sit on top of that.

### 2.2 The Mark table, on `ChassisDefinition`

A new `ChassisMark` Resource, exported as an array on the chassis:

```gdscript
# Campaign/chassis_mark.gd
class_name ChassisMark extends Resource
@export var weapon_ids: Array[StringName] = []
@export var equipment_ids: Array[StringName] = []
@export var health_bonus: int = 0
@export var speed_multiplier: float = 1.0
@export var sensor_bonus: float = 0.0
@export var accuracy_bonus: float = 0.0
## Role tuning that is not one of the four above — repair rate, salvage rate,
## reload. Named rather than typed so a frame can tune what it actually has.
@export var tuning: Dictionary = {}
```

```gdscript
# ChassisDefinition gains:
## Mk 1 and Mk 2. Mk 0 is NOT authored here — it is the frame's own
## starting_weapon_id and coax_weapon_id, which already exist and already
## describe what the line builds today.
@export var marks: Array[ChassisMark] = []
```

**Mk 0 is synthesised, never authored.** Every chassis already carries
`starting_weapon_id` and `coax_weapon_id`; the Walker is a 20 mm Autocannon
with a coaxial Ancient MG and the Rover is an Ancient Machine Gun. Authoring
Mk 0 a second time creates two sources of truth for the same fact and they
will disagree within a month.

Twelve purchasable chassis × 2 authored marks = **24 `ChassisMark` sub-
resources**, living inside the existing `Campaign/chassis/*.tres` files.

**No new enums.** Mark level is an int and module is a StringName, so nothing
here touches the append-only enum rule.

---

## 3. Operations

All four live on `CampaignState` beside `unlock_chassis` / `buy_chassis`.

| op | cost | effect |
|---|---|---|
| `unlock_chassis(frame)` | 2× unit | **exists already** — opens the line |
| `adopt_mark(frame)` | 3× unit (Mk 1), 6× (Mk 2) | `line_marks[id] += 1`, then apply to every record on the line |
| `adopt_module(frame, item)` | 8× unit | `line_modules[id] = item.id`, then apply |
| `buy_chassis(frame)` | 1× unit | **exists already** — new record, then apply |

`apply_line_spec(chassis_id)` is the one function all three share:

```
for every SoldierRecord with this chassis_id, including benched and in reserve:
    weapon_ids    = mark.weapon_ids    (or Mk 0's starting/coax)
    equipment_ids = mark.equipment_ids
    module_ids    = [line_modules[id]] if set else []
    recompute_stats(catalogue)
```

### 3.1 What happens to kit that was fitted

**It evaporates — the Mark replaces it, nothing returns to stores.** Checked:
the ledger invariant is `available() == earned - sum(allocations)`, which is
about money and not about inventory, so overwriting a record's ids cannot
break it. A line revision is Home Command reissuing a spec, not a quartermaster
swapping parts.

### 3.2 Eligibility

Module eligibility is already enforced and must be reused rather than
reimplemented: `ChassisDefinition.takes(item)` refuses an item whose
`fits_vehicles` is false on a frame with `drives`. That is what makes Overclock
Servos and Nanite Reboot legs-only. `adopt_module` returns false for anything
`takes()` refuses, and the Factory greys it with the reason rather than hiding
it.

---

## 4. Save and migration

`SoldierRecord.to_dict()` is a plain Dictionary of string arrays and keeps its
shape exactly. The only save change is two new keys on `CampaignState`.

**DECIDED 2026-10-22: old saves are dropped. The change is big enough.**

No refund, no inference, no compatibility shim. This removes what was the
riskiest step in the whole plan.

The machinery is already there. `CampaignState.SAVE_VERSION` is `1`, and
`migrate(data)` exists as a hook that today only warns when a save is from a
newer build:

- Bump `SAVE_VERSION` to **2**.
- In `migrate()`, a save with `version < 2` is **refused** — return a state
  that reports itself as unloadable, so the profile list can say so.

**Refuse it; do not delete it.** Silently removing somebody's campaign file is
hard to forgive and trivial to avoid: leave `campaign.json` on disk, show the
profile as belonging to an older build, and let the player start a new one.
Deleting the file buys nothing and cannot be undone.

The profile UI needs one new state for this — `test_profiles` covers "more
than one campaign, and the old one survives", so it is the suite that should
gain a case for "a v1 profile is listed, named as old, and not loadable".

---

## 5. What the UI becomes

### 5.1 Deleted

- **`Character/hud/squad/armorer_page.gd`** — 340 lines, plus its detail pane,
  buy/fit/sell rows and kind shelves.
- **`Character/hud/squad/tooling_page.gd`** — 303 lines, folded into the
  Factory card as OPEN LINE.
- The `ARMORER` and `TOOLING` entries in `SquadManagerUI.TABS` and
  `TAB_TITLES`. **Five tabs become three**: SQUAD, FACTORY, SOFTWARE.

### 5.2 Rewritten

- **`factory_page.gd`** — each line card carries UPGRADE and MODULE in its
  top-right corner, and BUILD below. Clicking the card opens the line detail:
  the Mk 0/1/2 rail, the stat bars with the next Mark drawn as a ghost
  extension, and the module picker. The prototype is the reference.
- **`squad_page.gd`** — loses all fitting. Slot tiles, the stores list,
  `_store_row`, `_take_off`, `fit_item`/`unfit_item` wiring and the
  "FIT IT ON THE SQUAD PAGE" bridge all go. What remains is teams, deployment
  and the bench, which is what it is good at.

### 5.3 Stays

`software_page.gd` is untouched. Software is specced separately in
`docs/concepts/SOFTWARE_CONCEPTS.md` as seven branches that are *builds*, and
nothing in this document should pre-empt it.

---

## 6. Known breakage, and what to do about it

**Key 6 is already unreachable.** The Utility Harness stopped adding an
equipment slot on 2026-10-18, and no player chassis has three equipment
mounts, so nothing reaches slot 6. `test_equipment` still covers the mapping
with a hand-built record and says why. Either give some frame a third mount or
accept two throwables.

**`equipment_slot_bonus` is live but unused.** `SoldierRecord` still reads it;
no shipped item sets it. The "what hung in the bonus slot goes back to stores"
path therefore has no coverage, noted in `test_ledger`.

**Stores stop having a job.** `Armoury` survives this spec because weapons for
the player and consumables still pass through it, but the module and
squad-weapon traffic disappears. Do not delete it in the same pass.

**Seven chassis suites write loadout ids directly.** Under §1 they keep
working untouched. If anyone later makes the arrays derived, those seven are
the cost.

---

## 7. Order of work, with a gate on each

| # | step | gate |
|---|---|---|
| 1 | `ChassisMark` resource + `marks` on ChassisDefinition, authored for all 12 lines | `check.sh --changed` PASS; a probe prints each line's three specs |
| 2 | `line_marks` / `line_modules` on CampaignState + `apply_line_spec` | new suite: adopting Mk 1 rewrites every record on the line and nothing off it |
| 3 | `adopt_mark` / `adopt_module` with pricing and eligibility | `bucket.sh campaign`, especially `test_ledger`'s invariant |
| 4 | `SAVE_VERSION` 2, `migrate()` refuses v1 without deleting it | `test_profiles` — a v1 profile is listed, named as old, not loadable |
| 5 | Factory page rewrite | `bucket.sh campaign` + a `shot_` of the page |
| 6 | Squad page loses fitting | `test_squad_manager`, `test_induction` |
| 7 | Delete Armorer and Tooling, three tabs | full `bucket.sh` on all five, `smoke.sh` |

**Steps 1–4 are the risky half and 5–7 are the satisfying half.** Do not
reorder them: deleting the Armorer before the Factory can do its job leaves no
way to equip anything.

---

## 8. Still open, and belonging to the human

**Nothing here blocks a start.** The one decision that did — what happens to
saves — was settled on 2026-10-22: they are dropped (§4).

1. **Mark contents.** The brief proposes a full table using real item ids, but
   which gun belongs at which tier is a balance judgement, not an engineering
   one.
2. **Reclaimer, Mechanic and Spotter have thin rails.** No weapon mount or no
   equipment slots means their Marks are tuning only. That may be enough; they
   are the three lines most likely to feel like they are not progressing.
3. **Does the Reclaimer keep Overclock Servos?** `drives` covers wheels *and*
   tracks, so the legs-only rule excludes the tracked Reclaimer alongside the
   wheeled frames. Separating them needs a distinction the chassis data does
   not currently carry.
4. **Scrap.** With retroactive Marks a robot never goes obsolete, so scrap is
   for regret — a line you developed and did not like — rather than for
   replacement. Agreed in conversation; worth writing into the GDD before
   anyone balances against it.

---

## 9. What is already done

The five module retunes landed in `12bdfcff` and are not part of this work:
Armour Plating proportional, Cyclic Feed without its accuracy penalty,
Overclock Servos legs-only, Hardened Uplink boosted, Utility Harness
multiplying charges instead of adding a slot. They are prerequisites for the
design above rather than part of it.
