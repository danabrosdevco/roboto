# MEMORY — implementation spec

Written 2026-10-22 by GAMEPLAY, off a design conversation with the human.
**Status: BUILT 2026-10-22.** Was `WEAPON_RACK_SPEC.md`, renamed with the
screen.

The player's own weapons and equipment, and the shape of the screen that holds
them. This is the thing standing between the Mark system and step 7b
(`docs/briefs/archive/MARK_SYSTEM_SPEC.md` §5.1), and it is the last shop in the game.

---

## 1. Why this exists at all

The Mark system moved every robot's loadout onto its production line. It never
answered the same question for the PLAYER, whose record is a separate field
(`CampaignState.player_record`) and is not in `roster` — so `apply_line_spec`
does not touch it and never should: your gun is the one moment-to-moment
decision in a game whose other half is a strategy layer.

**Since step 6 the player cannot change their weapon at all.** The squad
page's stores list was the only route and it went with the fitting UI. The
campaign seed arms you once and that is the end of it. Deleting the Armorer
without this makes that permanent.

---

## 2. The screen

**MEMORY**, replacing SOFTWARE. Three tabs inside it, over one ledger:

| tab | holds |
|---|---|
| **WEAPONS** | the guns you may carry — §3 |
| **EQUIPMENT** | the kit you may carry — §3.2 |
| **UPGRADES** | the branches. Content is `docs/concepts/SOFTWARE_CONCEPTS.md`; only the screen is specced here |

### 2.1 Why not SOFTWARE

SOFTWARE described a tree of upgrades, and a gun rack bolted on beside it was
a tree of upgrades with a gun rack bolted on beside it. **MEMORY** is what all
three tabs actually are: everything the error keeps loaded.

It also states the rule the tree already has without a sentence of help — *"a
set of switches rather than a shop"*. A thing in memory is **held**, not
bought: it costs compute for exactly as long as it is loaded and returns all
of it when unloaded. So the question is never "can I afford this gun", it is
**how many guns do I want resident at once**.

And because compute is also seats, that question is really: **arm yourself, or
field another robot.** That tension is the most on-theme mechanic available
here — the player is an unauthorised process, and everything it keeps resident
is compute stolen from a system too busy with its own reward loop to notice.

Alternatives considered and rejected: COMPUTE (collides with the currency in
the purse, which the Factory spends too), PROCESSES (accurate, abstract at the
point of picking a gun), SELF (already a branch name, and three of the seven
branches are squad-wide), LOADOUT (does not cover the third tab).

### 2.2 One ledger, above all three tabs

```
4 loaded  ·  3 in seats  ·  2 free  of  9 compute
```

Numbers, once, and nothing else. **There is no per-card explanation** — the
old mock had *"2 compute while racked, all of it back on removal"* under every
card, which is the screen describing its own rule nine times on one page. A
card that cannot be afforded greys its own button; that is the whole
explanation, and it is in the place where the player is looking.

The EQUIPMENT tab appends ` · 0 of 2 slots carried` to the same line rather
than opening a second line of small print.

### 2.3 Loaded is not carried

The player chassis has **`weapon_slots = 1`** and **`equipment_slots = 2`**.
Memory is what you may CHOOSE from; carrying is free and reversible at base.
Loading a second gun buys an option, not a second weapon.

That is the one difference between the first two tabs: on WEAPONS, carrying is
a single pick, and on EQUIPMENT it is a set of two. CARRY greys out once both
slots are full.

---

## 3. WEAPONS

Every weapon with `usable_by_player = true` **that is actually a weapon**. No
new art or scenes are needed.

| weapon | id | compute | note |
|---|---|---|---|---|
| Ancient Rifle | `m4` | **0** | Issued. Always loaded, cannot be unloaded. |
| Mark One | `bolt` | 1 | |
| Repair Lance | `repair_lance` | 1 | A gun slot spent on keeping the squad up. |
| Squad Automatic | `squad_auto` | 2 | |
| Cluster Launcher | `cluster_launcher` | 2 | |

**Everything loaded at once is 6 compute**, against a cap that starts at 9 and
is also paying for seats.

**Cut: Scout Carbine (`carbine`) and Marksman Rifle (`dmr`).** Both are
`weapon_damage = 0`, `ammo_type = ""`, `in_shop = false`, and both point
`player_scene` at `m4_hud_weapon.tscn` — they are stubs wearing the Ancient
Rifle's gun, not weapons. Offering either would charge compute for a rifle
that behaves exactly like the free one. `dmr` is not in the catalogue at all;
`carbine` is, which is a separate thing worth looking at.

**No internal gating.** A tier here is a price band, not a ladder — unlike the
branches, where tier 2 needs a tier 1 beneath it. The cost is the gate.

### 3.1 The copy is the catalogue's

Every name and description on these cards is **copied verbatim from
`Campaign/items/*.tres`**, and the built screen must read `ItemDefinition`
rather than carry its own strings. A second description of the same weapon is
how two descriptions of the same weapon end up disagreeing, and the item
already has one.

## 3.2 EQUIPMENT

Same screen, same rule, same ledger. Every item with `usable_by_player` and
`kind = EQUIPMENT` in the catalogue, less the one cut below.

| equipment | id | compute | carried | note |
|---|---|---|---|---|
| Frag | `frag` | **0** | ×4 | Issued. Always loaded, cannot be unloaded. |
| Smoke Canister | `smoke` | 1 | ×4 |
| EMP Grenade | `emp` | 2 | ×4 |
| Heavy Mine | `mine_heavy` | 2 | ×4 |
| Cluster Mine | `mine_cluster` | 2 | ×4 |
| Recoilless Rifle | `recoilless` | 3 | ×2 |
| Drone Carrier Pack | `drone_pack` | 3 | ×2 |
| Hatchling Charge | `hatchling` | 3 | ×2 |

**Cut: Scanner (`scanner`).** One charge, one use, and nothing on screen to
read it on.

**Note the id.** The Recoilless Rifle's file is `item_rocket.tres` but its id
is `&"recoilless"`; the icon is `rocket_m.png`. A lookup written from the
filename finds nothing and fails silently.

**The Frag is issued, decided 2026-10-22.** The earlier draft started this tab
empty on the argument that nothing makes the grenade's case the way "you must
have a gun" makes the rifle's. The human's call went the other way, and the
reason is the one that mattered: mission one should have something to throw.

So both issued things are also **carried from the first frame** — see
`Campaign.gd _carry_issued()`. Ticking two free things on in a menu before the
first mission is a chore standing where a start should be.

Everything loaded across both tabs is **22 compute** (6 and 16), which no
campaign will ever have spare. A new one starts on `starting_compute = 2`.
That is the point in both tabs.

---

## 4. What it needs from the code

Small, because the machinery exists.

### 4.1 `software_tree.gd`

```gdscript
## The player's own weapons and equipment, as programs. A SEPARATE SPACE from
## BRANCHES: a branch is a build you commit to and a rifle is not.
const WEAPONS := [
    {"id": &"wep_m4",               "item": &"m4",               "cost": 0},
    {"id": &"wep_bolt",             "item": &"bolt",             "cost": 1},
    ...
]
const KIT := [ ... ]
static func player_items() -> Array           # both tabs, in order
static func load_block(state, id) -> String   # mirrors install_block
```

`install()` / `uninstall()` work unchanged — an entry has an id and a cost,
which is all they need. The Ancient Rifle's `uninstall_block` always refuses.

The file still has the FOUR original branches with `UNWRITTEN` placeholders in
them, which the UPGRADES tab inherits until `SOFTWARE_CONCEPTS.md` is built.
**The first two tabs do not depend on which of those is true** — that is the
reason for putting them beside the branches rather than inside them.

### 4.2 `CampaignState`

Nothing new to store. `is_installed(id)` and the compute ledger already cover
it. What is new is one derived question:

```gdscript
## Which weapons the player may carry — the list, filtered to loaded.
func player_weapons() -> Array[ItemDefinition]
func player_equipment() -> Array[ItemDefinition]
```

### 4.3 Carrying one

`player_record.weapon_ids[0]` is what `EquipmentLoadout.apply_record` reads, so
choosing a gun is a write to that field plus `recompute_stats`. It must refuse
anything not currently loaded, or an unload could leave you holding a gun you
no longer own. Equipment is the same against `equipment_ids`, bounded by
`equipment_slots`.

### 4.4 Where you choose

Two readings, and they are not exclusive: the MEMORY card itself (CARRY on a
loaded card, as mocked), and the player's own card on the SQUAD page — the one
place a per-robot loadout decision still belongs, because the player is the
one robot whose loadout is still theirs. Mock has the first; the second is
cheap to add and probably wants both.

---

## 5. What it unblocks

Step 7b: delete `armorer_page.gd`, drop the ARMORER tab, three tabs —
SQUAD, FACTORY, MEMORY. The armoury/stores system can then be retired
separately, since nothing buys copies of anything any more.

---

## 6. Settled, 2026-10-22

1. **One cost, not two.** Loading and holding are THE SAME ACT: load a gun, it
   holds its compute, unload it and all of it comes back. There is no separate
   unlock price. `test_memory_screen.gd` checks the refund BY AMOUNT rather
   than by "it went up", because a load that quietly spent instead of holding
   would pass every other check in the file.
2. **Smoke stays.** It was cut from SQUAD kit on 2026-10-18 — "a pain in the
   ass and doesn't add as much" — and that verdict was about squad kit, not
   about your own canister.
3. **The Frag is issued.** See §3.2.

## 6.1 Still open

1. **The bands.** Which gun is worth 1 and which is worth 3 is balance, not
   engineering. Nothing here has been played.
2. **Does SELF's ARMOURY feed this?** `SOFTWARE_CONCEPTS.md` has ARMOURY at
   SELF tier 2 — *"you carry vehicle-class weapons"*. That reads like the
   thing that adds autocannons and rocket pods to a list which otherwise holds
   small arms. If so, WEAPONS grows rather than being fixed at five.
3. **`carbine` is in the catalogue and `dmr` is not.** Both are cut from this
   screen either way, but a half-built weapon sitting in the shipping
   catalogue is its own small problem.
