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
- **`EnemyHelicopter extends Soldier`** — a flying frame. Overrides only
  `handle_gravity`, `handle_movement`, `_apply_motion`, `move_to` and
  `_update_facing`; everything else is inherited. It extends *Soldier* rather
  than Enemy because `Squad.squad_members` is `Array[Soldier]` and
  `EnemyForceSpawner` casts with `as Soldier` — an Enemy-rooted scene cannot be
  a squad chassis at all.
- `enemy_chaser` (melee) and `enemy_nest-chaser` (leaper) now use `soldier.gd`
  for the same reason. There is no `appx/` folder any more.

### Equipment (`Character/equipment/`)

- `PlayerEquipment` — base: viewmodel pose, equip lifecycle, charge readout.
- `PlayerWeapon extends PlayerEquipment`; `HUDWeapon extends PlayerWeapon`.
- `EquipmentLoadout` — slots, keys 1–6, auto-revert, builds from the record.
- `AmmoPool` / `AmmoStock` — reserves keyed by ammo type.

### HUD (`Character/hud/`)

All code-built and self-wiring, because unassigned exports fail silently.
`squad_hud.gd`, `objective_hud.gd`, `squad_manager_ui.gd`, `hud.gd`.

- `comms_log.gd` — friendly radio traffic as text, bottom right. Driven by
  `BarkDirector`, so it prints exactly what was *heard* and never more.
- `objective_hud.gd` also owns the extraction marker and the payout card
  (reward, promotions, squad recovered/lost) shown on `Campaign.extracted`.
- Screen corners are divided deliberately: squad top-left, objectives top-right,
  comms bottom-right, health bottom-centre. Keep it that way or they overlap.

### Boot and audio

- **`Master` (`Managers/master.gd`)** — the only thing above `World`. Splash →
  FPO main menu → play, plus the ESC pause screen and the fullscreen toggle
  (which lives here because `_physics_process` is dead while paused). Exported
  `skip_splash` bypasses all of it.
- **`BarkDirector`** — a static arbiter that owns the voice channel. Every bark
  is a *request*; it elects one speaker per burst and drops the rest. Barking
  is a property of the CHANNEL, not of a robot — see §5.
- **`BarkSet`** — one `.tres` holding the clips per line, shared by every robot,
  so a voice is authored once instead of per chassis scene.

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

**`PROCESS_MODE_ALWAYS` is INHERITED.** Setting it on a node hands it to every
descendant using the default `PROCESS_MODE_INHERIT`. Setting it on `Master`
alone made the entire game unpausable — the squad manager, level loading and the
pause menu all still set `get_tree().paused` and none of them did anything.
`Master._pin_children_pausable()` holds `World` back to `PAUSABLE` for exactly
this. Anything under World that must run while paused sets ALWAYS on itself.

**A cache must never outlive the roster it was built from.** `AIManager`'s
per-faction hostile cache held hard references for 0.4s after the bodies were
freed, so level unload produced *"Invalid access to property 'global_position'
on a base object of type 'previously freed'"*. Clear the cache wherever the
roster changes, and guard every loop over `all_ai` with `is_instance_valid`.

**Register implies deregister.** `register_enemy()` had been called by the
spawner since day one and `deregister_enemy()` had **no callers at all** — so
every robot destroyed mid-mission stayed in `all_ai` as a dangling reference and
the O(n) hostile scan got slower with every kill. `Enemy._exit_tree()` now
deregisters. If you add a registry, add the removal at the same time.

**Mutate fully, THEN emit.** `ledger_changed` is wired straight to a synchronous
UI rebuild, so emitting halfway through a change means the panel redraws from a
half-applied state and then never corrects. This bit four times — `buy_item`,
`buy_chassis`, `sell_item` and `repair_soldier` all emitted before the armoury
or the record had caught up. Use `_allocate_quiet()` and emit once at the end.

**A deferred builder cannot be protected by `_clear()`.** `_add_slot_group()`
awaits a frame before adding its children, so when a second rebuild cleared the
panel there was nothing there to remove yet and both continuations then added a
full set. That is the duplicated WEAPON/EQUIPMENT/MODULES blocks — not the
`queue_free` deferral above. It is fixed with a generation counter: a stale
continuation checks the number and aborts.

**Nav queries are budgeted; nothing may call the agent directly.**
`get_next_path_position()` AND `is_navigation_finished()` both resolve the path
internally — they are twins, and throttling only one halves the cost and leaves
the other. All of it goes through `Enemy._tick_nav()`, gated by a per-robot
interval scaled by `lod_scale()` and a global per-frame budget. If you add a
call to `nav_agent`, put it there.

**Weapon range is not `max_effective_range` for melee.** `ai-wep_melee` never
overrode it, so it inherited `AIWeapon`'s 70m default and every chaser decided
it was "in range" at 49m, stopped, and swung at air. `_max_range()` returns
`melee_range` for `AIWeaponTypes.MELEE`. Anything reasoning in *fractions* of
weapon range (`range_ratio`) is meaningless for a melee frame — gate on absolute
distance instead, as `MovementOptions.LEAP` now does.

**Whatever `viewmodel` / `weapon_model` points at is owned by the pose system.**
`PlayerEquipment` writes its `position` and `rotation` every frame, so authored
orientation on that node is discarded. Put the model's orientation on a PARENT
holder and point the export at the child inside — see `m4_hud_weapon.tscn`,
`shotgun_hud_weapon.tscn` and the repair tool's `Holster`. Compounded by the
units bug in §6.

**Two-argument `apply_damage`.** Every damage source passes an attributor:
`apply_damage(amount, source)`. A one-parameter implementation raises "too many
arguments" instead of taking damage — which is why crates were never breakable.
Accept `_source = null` even when unused.

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

- **Shop screen.** *Buying and selling are in* — `[-]` and `[+]` on the armoury
  rows, selling at half what was paid. Still to do: chassis in the soldier
  detail panel (`buy_chassis` works, it has no UI) and ammo as a single priced
  service button.
- **TWO CATALOGUES EXIST.** `world.tscn` loads
  `Campaign/items & catalogue/test_item_catalogue.tres`. The other one,
  `Campaign/item_catalogue.tres`, is loaded by nothing and has drifted — it has
  `optics`, the live one has `dmr`. Edit the wrong file and your change silently
  does nothing. Pick a winner, repoint `world.tscn`, delete the other, and get
  it out of a folder whose name contains a space and an `&`.
- **Resources.** Intended split: *shards* (matter — weapons, repairs, ammo),
  *neural bits* (cognition — modules, high-tier chassis), and **compute** as a
  capacity rather than a currency, gating squad size, chassis tier *and the
  player's own skill tree* — so upgrading yourself competes with fielding
  another robot. Compute should be won, never bought, or that choice
  evaporates. Currently one undifferentiated `earned` pool, and changing it
  changes the save format.
- **Aggressive/cautious stance.** Designed, not built. It's what gives back the
  expressiveness lost when three verbs became two.
- **Reinforcement director.** `EnemySquadSpec.Posture.RESERVE` exists as the
  hook. Escalation should trigger on player *actions*, not a clock.
- **Ammo resupply.** `restock_roster()` is currently free on return to base.
  Charging for it is the decision that makes ammunition a campaign resource.
- **DMR and carbine** point at the M4's scenes; they need their own. Buying
  either currently gives you an Ancient Rifle. Waiting on art.
- **Viewmodel pose has a units bug.** `PlayerEquipment` writes
  `viewmodel.rotation_degrees = viewmodel.rotation` — a radians property
  assigned into a degrees one, then read back as radians next frame. So
  `base_rotation` never lands where you set it. Weapons work around it by
  putting the model's orientation on a *parent* holder node the pose system
  never touches (see `m4_hud_weapon.tscn` and `shotgun_hud_weapon.tscn`).
  Fixing it properly changes the resting pose of every weapon at once.
- **Suppression only degrades aim.** `receive_signal_damage` raises spread via
  `get_aim_spread_multiplier`, and that is the whole intended effect for now.
  `Soldier.enter_suppressed()` and `SoldierState.SUPPRESSED` exist but nothing
  calls them, deliberately — `Enemy._on_signal_damaged` is an unused hook.
- **Dead code, known and left alone:** `set_nco` (the NCO slot isn't the plan),
  `resume_objective`, `remove_ai_from_squad`, `get_living_soldiers` (duplicate
  of `get_living_members`), `force_check_detection`, and
  `compute_leap_velocity` (superseded by `compute_leap_velocity_fixed_speed`).
- **`_check_chokepoint` is a stub** that always returns false, so grenades never
  consider chokepoints.

---

## 7. Conventions

- Comments explain *why*, especially where something non-obvious prevents a bug
  we already hit. Those comments are load-bearing.
- Parse-check with `godot --headless --path <project> --check-only --script <file>`.
  Autoloads don't resolve in that mode; missing-asset errors are pre-existing noise.
  In practice, run `bash tools/check.sh --changed` instead — it wraps this over
  every changed script, filters both kinds of noise, and also validates scene
  and resource integrity.
- `bash tools/test.sh` runs the headless logic suites (`tools/test_*.gd`). The
  ledger has one; four ledger bugs shipped in two days before it existed.
- `bash tools/smoke.sh` boots the game headless and fails on runtime errors.
  check.sh proves scripts *parse*; this proves they *run*.
- `.tscn`/`.tres` edits: verify `ext_resource` ids are all declared and used, and
  that `load_steps` equals ext + sub + 1. Godot does not reliably pick up an
  externally edited `.tres` until the project is closed and reopened.
- When fixing a bug, ask whether the same class of thing exists elsewhere. Most
  of the bugs in this project came in families.
