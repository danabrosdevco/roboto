# Roboto — project briefing

Paste this into a new chat, or keep it at `docs/BRIEFING.md`. It is written for
someone (or something) picking the project up cold.

Branch: `td-w10-post-osx-summer-2026`. Godot 4.3. Levels are TrenchBroom brush
geometry via FuncGodot.

---

## 1. What the game is

A first-person shooter where you are a rogue agentic drone commanding a small
squad of robots, structured as **persistent squad + discrete handcrafted
missions** — XCOM's shape, not Helldivers' and not an open world.

The level pipeline decided that. TrenchBroom brush geometry is excellent for
dense handcrafted maps and hopeless for streaming terrain, so missions are
discrete maps reached from a home base.

The squad is the point. Soldiers are named, carry damage between missions, and
can be repaired, re-equipped and lost. Anything that makes them disposable is
working against the game.

---

## 2. Architecture

Four layers. They talk through data, not through each other's internals.

### Campaign (`Campaign/`)

Everything that survives a mission.

- `CampaignManager` (`campaign.gd`) — lifecycle. **A node under `World`, not an
  autoload.** Joins the `"campaign"` group so anything can find it.
- `CampaignState` — roster, ledger, armoury, squad name, save/load.
- `SoldierRecord` — a squadmate as data. Slots hold **item ids**, not resources.
- `Armoury` — spare stock as `{item_id: count}`.
- `ItemCatalogue` / `ItemDefinition` / `ChassisDefinition` — authored `.tres`.
- `MissionDefinition` — level, enemy force, active objectives, rewards, gating.
- `SquadSpawner` — records in, Soldiers out, and back again at extraction.
- `EnemyForceSpawner` + `EnemySquadSpec` — hostile force as mission data.
- `MissionObjective` and subclasses, `ObjectiveTracker`, `MissionTerminal`.

### AI (`Character/characters/ai/`, `Managers/AI/`)

- `Enemy` — the big one. Perception, targeting, combat, movement, downed state.
  `Soldier extends Enemy`, `Player extends AI`.
- `Squad` — objectives, roles, contact tracking, formation holds.
- `AIManager` — registry, cached hostile lists. `StimulusManager` — sound events.
- `PatrolPath` / `PatrolPoint` — level-authored routes with editor preview.

### Equipment (`Character/equipment/`)

- `PlayerEquipment` — base: viewmodel pose, equip lifecycle, charge readout.
- `PlayerWeapon extends PlayerEquipment`; `HUDWeapon extends PlayerWeapon`.
- `EquipmentLoadout` — slots, keys 1–6, auto-revert, builds from the record.
- `AmmoPool` / `AmmoStock` — reserves keyed by ammo type.

### HUD (`Character/hud/`)

All code-built and self-wiring, because unassigned exports fail silently.
`squad_hud.gd`, `objective_hud.gd`, `squad_manager_ui.gd`, `hud.gd`.

---

## 3. Invariants — break these and things rot quietly

**Enums are append-only.** `SquadObjective`, `InteractTypes` and friends are
stored as ints in `.tscn` and `.tres` files. Inserting a value silently remaps
every authored default in the project. `WITHDRAW` is unreachable from the UI and
stays in the enum for exactly this reason.

**The ledger never decrements.** `available() = earned - sum(allocations)`.
Buying adds an allocation; selling erases it and refunds exactly what was paid.
Consumed spend (repairs) is an allocation that's never refunded. There is no
second balance to drift.

**Records are data, nodes are instances.** A `SoldierRecord` outlives every
level. `SquadSpawner` builds nodes from records at deploy and reads survivors
back at extraction. Anything that edits a record while a body exists must push
the change onto the node too — see `rename_soldier`, `sync_record`.

**Missions reference levels by tag, never by node path.** `PatrolPath.tag`,
`SquadObjectivePoint.tag`. A tag survives a rename and works across maps.

**Player orders carry a position, never a body.** A designation outlives the
thing it named.

**Derived stats are cached, not computed on read.** `max_health` is
`chassis.base_health + module bonuses`, recomputed by
`SoldierRecord.recompute_stats()` on every mutation. Threading a catalogue
through every read site would be churn for no gain.

---

## 4. Failure patterns that bit repeatedly

These cost the most time. Check them first.

**Scene-stored exports beat script defaults.** Changing an `@export` default in
code does nothing for a node already placed in a scene — the scene has its own
copy. This caused: `starting_stock` not updating, `starting_chassis_id`
mismatching, and weapon `slot` values vanishing when instances were replaced.
In the inspector, a revert arrow means the value is overridden.

**Node ready order.** In `world.tscn`, `HUD` and `test_character` are declared
*above* `CampaignManager`, and children ready in declaration order. Anything
resolving the campaign in `_ready()` gets null. Resolve lazily, deferred, or via
the `"campaign"` group. This bit the squad manager UI, the objective HUD and the
player's loadout in turn.

**`queue_free()` is deferred.** The node stays a child until end of frame. When
rebuilding a UI list, `remove_child()` first or a second rebuild in the same
frame duplicates everything.

**A renamed `.tres` leaves a null in arrays.** The referencing resource still
loads; the entry is just gone. `ItemCatalogue` now errors loudly about this.
Rename from inside Godot's FileSystem dock, not the OS.

**Resources are shared between instances.** `AIEquipmentSlot` holds a runtime
use count — two soldiers sharing one `.tres` share a grenade count. `duplicate()`
before handing one to a node. Same reason `_flatten_collider()` rotates the
*node*, never the shape.

**Silent early returns.** Nearly every "it just doesn't work" in this project
was a function returning early without saying why. Every skip path in the
spawners, catalogue and readiness check now warns. Keep that up.

**`force = true` on `order_move_to` clears `combat_target`.** That is
deliberate ("fall back"), but routine repositioning must pass
`keep_target = true` or issuing any order drops the whole squad out of contact.

**Signals connected to nothing.** `exit_blocked` fired for a long time with no
listener. If you add a signal, wire it or delete it.

**GDScript gotcha:** `"%s" % some_array` treats the array as a format argument
*list*. Wrap it or use `str()`.

---

## 5. Systems worth knowing in detail

**Contact tracking.** `Squad.has_live_contact()` requires a live target, not
just `AIState.COMBAT` — a robot holding a downed target sits in COMBAT forever.
`CONTACT_GRACE` (6s) stops the readout flickering between kills.

**Downed, not dead.** `alive` still goes false; `downed` means recoverable. The
body collapses, the collider lies flat, then it sinks and switches its collider
and its `_physics_process` off. The repair tool revives at 50% health, and finds
targets through a proximity cone because a body on the floor is a poor ray
target.

**Vision.** Sight is `sensor_range` (45m base, inherent, upgradeable by modules)
— deliberately *not* derived from weapon range, so a rifle can out-shoot what it
can't out-spot until you fit optics. Cone + line of sight + acquisition time.
Raycasts are budgeted (`vision_los_checks`) and think-frames are staggered.

**Squad orders.** Two verbs: `ADVANCE` (maps to `SquadObjective.DEFEND` — go
there and hold) and `FOLLOW`. Tap for a contact call. Enemy squads still use
`ADVANCE`/`ATTACK`/`PATROL` postures. Formation holds re-assert position every
frame rather than issuing orders and hoping, because there are at least five
paths in `Enemy` that can start a movement.

**Performance.** ~35 always-active AI is the target. Costs, in order: vision
raycasts, `friendly_in_line` (4 per shot), `get_nearest_hostile`. All three are
budgeted, LOD-scaled or cached. `lod_scale()` returns 1.0 for squad members
always — you're looking right at them.

---

## 6. Open threads

- **Shop screen.** `buy_item`, `buy_chassis`, `sell_item` all work and are
  tested; there's no UI. Plan: one list of unlocked items with a BUY button,
  chassis in the soldier detail panel, ammo as a single priced service button.
- **Resources.** Intended split: *shards* (matter — weapons, repairs, ammo),
  *neural bits* (cognition — modules, player upgrades), and **compute** as a
  capacity rather than a currency, gating squad size and chassis tier. Currently
  one undifferentiated `earned` pool.
- **Aggressive/cautious stance.** Designed, not built. It's what gives back the
  expressiveness lost when three verbs became two.
- **Reinforcement director.** `EnemySquadSpec.Posture.RESERVE` exists as the
  hook. Escalation should trigger on player *actions*, not a clock.
- **Ammo resupply.** `restock_roster()` is currently free on return to base.
  Charging for it is the decision that makes ammunition a campaign resource.
- **Scanner** has no item definition, so it's absent from the player loadout.
- **DMR and carbine** point at the M4's scenes; they need their own.

---

## 7. Conventions

- Comments explain *why*, especially where something non-obvious prevents a bug
  we already hit. Those comments are load-bearing.
- Parse-check with `godot --headless --path <project> --check-only --script <file>`.
  Autoloads don't resolve in that mode; missing-asset errors are pre-existing noise.
  In practice, run `bash tools/check.sh --changed` instead — it wraps this over
  every changed script, filters both kinds of noise, and also validates scene
  and resource integrity.
- `.tscn`/`.tres` edits: verify `ext_resource` ids are all declared and used, and
  that `load_steps` equals ext + sub + 1.
- When fixing a bug, ask whether the same class of thing exists elsewhere. Most
  of the bugs in this project came in families.
